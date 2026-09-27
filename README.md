# doc-lint: Documentation Linting Service for AI Coding Agents

A self-contained Docker image that validates documentation artifacts
(Markdown, Mermaid diagrams, JSON, XML, YAML, TOML) using industry-standard linters.
Designed as a validation gate for AI Coding Agents, particularly the
Documentation Writer mode, to ensure documentation quality before handoff.

## Project Overview

`doc-lint` provides a unified linting interface for six documentation formats commonly produced by AI agents:

- **Markdown** (`.md`, `.markdown`) — validated with `markdownlint-cli2`
- **Mermaid diagrams** (`.mmd`, `.mermaid`) — validated with `@mermaid-js/mermaid-cli` (`mmdc`)
- **JSON** (`.json`) — syntax validation with Node.js, optional schema validation with `ajv`
- **XML** (`.xml`) — well-formedness validation with `xmllint`
- **YAML** (`.yaml`, `.yml`) — syntax validation with `yq`
- **TOML** (`.toml`) — syntax validation with Python `tomli`

The image auto-detects file types by extension, runs the appropriate
linters, and aggregates exit codes. A non-zero exit indicates at least
one lint failure.

## Target Audience

This project is designed for **AI Coding Agents** operating in automated documentation workflows, specifically:

- **Documentation Writer mode** agents that generate or update
  documentation files and need to validate them before completing a task
- **Orchestration systems** that coordinate multi-agent workflows and require validation gates
- **CI/CD pipelines** that need lightweight, reproducible documentation linting

The tool is not intended for interactive human use, though it can be used that way.

## Repository Structure

```text
doc-lint/
├── Dockerfile                    # Multi-stage build for doc-lint image
├── package.json                  # Node.js dependencies (linters)
├── SKILL.md                      # Skill definition for Documentation Writer mode
├── README.md                     # This file
├── bin/
│   ├── lint.sh                   # Main entrypoint script (copied as /opt/lint/bin/lint)
│   ├── cache.sh                  # Content-addressable cache helpers
│   ├── plugin-loader.sh          # Plugin discovery and execution
│   ├── json-schema-check.js      # JSON Schema validation helper (ajv)
│   └── formatters/               # Output formatters
│       ├── text.sh               # Human-readable text output (default)
│       ├── json.sh               # JSON structured output
│       ├── junit.sh              # JUnit XML for CI test reporting
│       └── sarif.sh              # SARIF v2.1.0 for GitHub Code Scanning
├── configs/
│   └── .markdownlint.yaml        # Default markdownlint configuration
├── plugins/
│   ├── README.md                 # Plugin development guide
│   └── example-yaml-lint/        # Example YAML linter plugin
│       ├── plugin.json           # Plugin manifest
│       ├── lint.sh               # Plugin executable
│       └── README.md             # Plugin documentation
└── test/
    ├── run-tests.sh              # Test harness
    └── fixtures/                 # Test fixtures (valid/invalid samples)
```

### Key Components

#### `Dockerfile`

Builds a `node:20-bookworm-slim`-based image with:

- `chromium` and fonts for Mermaid diagram rendering
- `libxml2-utils` for XML validation
- Non-root runtime user (`linter`, UID 1000)
- Entrypoint at `/opt/lint/bin/lint`

#### `bin/lint.sh`

Bash script that:

1. Parses command-line arguments (targets, optional `--schema` for JSON validation)
2. Collects files by extension from specified paths (files or directories)
3. Runs the appropriate linter for each file type
4. Aggregates exit codes and prints a summary

Exit codes:

- `0` — all lints passed
- `1` — at least one lint failed
- `2` — usage or environment error (missing target, bad schema path)

#### `bin/json-schema-check.js`

Node.js script that validates JSON data against a JSON Schema using
`ajv`. Invoked by `lint.sh` when `--schema` is provided.

#### `configs/.markdownlint.yaml`

Default configuration for `markdownlint-cli2`, tuned for AI-generated
documentation:

- Relaxes line-length rules (MD013) for tables and code blocks
- Allows inline HTML (MD033) for badges and anchors
- Enforces structural rules (headings, blank lines, list markers)

A repository-provided `.markdownlint.*` file in the working directory takes precedence over this bundled default.

## Installation & Setup

### Prerequisites

- Docker (tested with Docker Engine 24+)
- Git (for cloning the repository, if building from source)

### Pull from Docker Hub

The pre-built image is available on Docker Hub:

```bash
docker pull dheaps/doc-lint:latest
```

### Build the Docker Image (Optional)

Alternatively, clone or update the repository from GitHub and build the image locally:

```bash
# 1. Check whether the image already exists
if ! docker image inspect doc-lint:latest >/dev/null 2>&1; then
  # 2. Clone the repository (or pull if it already exists)
  if [ ! -d "doc-lint" ]; then
    git clone https://github.com/king-dopey/doc-lint.git
  else
    git -C doc-lint pull --ff-only
  fi
  # 3. Build the image from the cloned repository
  docker build -t doc-lint:latest ./doc-lint
fi
```

The build context must include:

- `Dockerfile`
- `package.json`
- `configs/.markdownlint.yaml`
- `bin/lint.sh`
- `bin/cache.sh`
- `bin/plugin-loader.sh`
- `bin/json-schema-check.js`
- `bin/formatters/` (all formatter scripts)
- `plugins/` (plugin system and example plugins)

### Verify the Image

```bash
docker image inspect doc-lint:latest >/dev/null 2>&1 && echo "Image present" || echo "Image missing"
```

## Usage Guidelines for AI Agents

### Basic Invocation

Mount the working directory and pass file paths or directories to lint:

```bash
# Lint specific files
docker run --rm \
  -v "$PWD:/work" -w /work \
  doc-lint:latest lint docs/CHANGELOG.md docs/api.md

# Lint an entire directory (recursively)
docker run --rm \
  -v "$PWD:/work" -w /work \
  doc-lint:latest lint docs/

# Validate JSON against a JSON Schema
docker run --rm \
  -v "$PWD:/work" -w /work \
  doc-lint:latest lint --schema schemas/review-report.schema.json docs/review-report.json
```

### Output Formats

doc-lint supports multiple output formats for different use cases:

```bash
# Human-readable text output (default)
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --format text docs/

# JSON structured output (for programmatic consumption)
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --format json docs/

# JUnit XML (for CI test reporting)
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --format junit docs/ > test-results.xml

# SARIF v2.1.0 (for GitHub Code Scanning)
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --format sarif docs/ > results.sarif
```

### Parallel Processing

Enable parallel linting across file formats for improved performance:

```bash
# Run linters in parallel (faster for large repositories)
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --parallel docs/

# Explicitly disable parallel processing (default behavior)
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --no-parallel docs/
```

### Caching

Enable content-addressable caching to skip unchanged files:

```bash
# Enable caching (mount cache volume for persistence)
docker run --rm \
  -v "$PWD:/work" -w /work \
  -v doc-lint-cache:/home/linter/.cache/doc-lint \
  doc-lint:latest lint --cache docs/

# Disable caching (default)
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --no-cache docs/

# Clean old cache entries (older than 30 days)
docker run --rm \
  -v doc-lint-cache:/home/linter/.cache/doc-lint \
  doc-lint:latest --cache-clean 30
```

### File Exclusion

Exclude files or directories from linting:

```bash
# Exclude specific patterns
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --exclude '*.draft.md' --exclude 'vendor/*' docs/

# Exclude multiple patterns
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint \
    --exclude 'node_modules/*' \
    --exclude '*.tmp' \
    --exclude 'archive/*' \
    docs/
```

### Auto-Fix Mode

Automatically fix common linting violations:

```bash
# Auto-fix violations (creates .bak backup files by default)
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --fix docs/

# Auto-fix without creating backups
docker run --rm -v "$PWD:/work" -w /work \
  doc-lint:latest lint --fix --no-backup docs/
```

**Supported auto-fixes:**

- **Markdown**: Trailing spaces, blank lines around headings, list formatting (via `markdownlint-cli2 --fix`)
- **JSON**: Formatting and indentation (via `prettier`)

**Note:** Auto-fix mode creates `.bak` backup files by default. Use `--no-backup` to skip backup creation.

### Plugin System

Extend doc-lint with custom linters using the plugin system:

```bash
# Mount custom plugins directory
docker run --rm \
  -v "$PWD:/work" -w /work \
  -v "$PWD/plugins:/opt/lint/plugins" \
  doc-lint:latest lint docs/

# Use custom plugins directory location
docker run --rm \
  -v "$PWD:/work" -w /work \
  -v "$PWD/my-plugins:/custom/plugins" \
  doc-lint:latest lint --plugins-dir /custom/plugins docs/
```

**Creating a plugin:**

1. Create a plugin directory with `plugin.json` manifest
2. Implement an executable script that reads file paths from stdin
3. Output results in intermediate format: `file:line:col:rule:severity:message`
4. See `plugins/example-yaml-lint/` for a complete example

See [plugins/README.md](plugins/README.md) for detailed plugin development guide.

### Integration with Documentation Writer Mode

1. After writing or updating documentation files (`.md`, `.mmd`, `.json`,
   `.xml`, `.yaml`, `.yml`, `.toml`), run `doc-lint` on exactly those files.
2. If the lint passes (exit code `0`), set the handoff `evidence_ref` to the lint command + `"ALL PASS"`.
3. If the lint fails (exit code `1`), do **not** hand off. Emit a
   handoff payload with `status=FAIL`, `blocker_tag=tool-failure`, and
   route back via `switch_mode` → `code` for rework.

### Interpreting Output

The entrypoint prints one `==> [label] command` line per check with an `OK` or `FAIL` result, followed by a summary:

```text
==> [markdown] npx --no-install markdownlint-cli2 docs/README.md
    OK
==> [json-syntax:docs/config.json] node -e "JSON.parse(...)" docs/config.json
    OK

doc-lint: ALL PASS
```

On failure, read the linter's stderr for specific rule codes and line
numbers:

- **Markdown**: `MDxxx` rule code and `file:line`
- **Mermaid**: Parser error naming the offending diagram token
- **JSON**: Syntax errors show parse position; schema errors list `instancePath` + message
- **XML**: `xmllint` reports byte/line of the first well-formedness violation
- **YAML**: `yq` reports line number and error message
- **TOML**: Python `tomli` reports line and column for syntax errors

### Intermediate Format Specification

doc-lint uses an intermediate format internally to collect linting results
from all linters. This format is also used by plugins to report their findings.

**Format:**

```text
file:line:col:rule:severity:message
```

**Fields:**

- `file`: Path to the file being linted (relative to working directory)
- `line`: Line number where the issue occurs (1-based)
- `col`: Column number where the issue occurs (1-based)
- `rule`: Rule identifier (e.g., `MD013`, `yaml-syntax`, `json-syntax`)
- `severity`: Severity level (`error`, `warning`, or `info`)
- `message`: Human-readable description of the issue

**Example:**

```text
docs/config.yaml:5:3:yaml-syntax:error:mapping values are not allowed here
docs/api.md:10:1:MD013:error:Line length exceeded
```

**Usage:**

- Built-in linters automatically convert their output to this format
- Plugins must output results in this format to stdout
- The format is used internally for aggregation and output formatting
- When using `--format json` or `--format sarif`, results are converted from this intermediate format

### Environment Variables

- `DOC_LINT_WORKDIR` — working directory inside the container (default `/work`)
- `DOC_LINT_MERMAID_OUT` — directory where `mmdc` writes temporary SVGs (default `/tmp/doc-lint-mermaid`)
- `DOC_LINT_PLUGINS_DIR` — custom plugin directory (default `/opt/lint/plugins`)
- `DOC_LINT_PLUGIN_TIMEOUT` — plugin execution timeout in seconds (default `30`)
- `DOC_LINT_FIX` — enable auto-fix mode (default `false`)
- `DOC_LINT_NO_BACKUP` — disable backup creation in auto-fix mode (default `false`)

## Known Implementation Gaps & Limitations

### Current Limitations

1. **Mermaid validation via rendering**: `mmdc` does not have a dedicated
   `--parse` flag; validation requires rendering to SVG, which is slower
   than pure syntax checking. This is the documented behavior of the
   official CLI.

2. **Image size**: The inclusion of Chromium for Mermaid rendering makes
   the image larger (~1.5GB) than a minimal linter image. A lighter
   alternative would be a standalone Rust-based Mermaid parser, but
   `mmdc` is the official tool and guarantees compatibility.

3. **JSON Schema validation is opt-in**: Plain JSON files receive
   syntax-only checks by default. Schema validation requires passing
   `--schema <path>` explicitly.

4. **Auto-fix limitations**: Auto-fix mode only supports Markdown and JSON.
   YAML, TOML, XML, and Mermaid files cannot be auto-fixed. Some Markdown
   violations (e.g., MD025 multiple top-level headings) require manual intervention.

### Missing Features

- **Incremental linting**: No tracking of which files have changed since the last run (though caching is available).
- **Watch mode**: No continuous linting during file edits.

### Areas for Further Development

- Implement distributed caching for CI/CD environments (S3, GCS)
- Add watch mode for continuous linting during development
- Extend auto-fix support to additional formats (YAML, TOML)

## Security Considerations

doc-lint is designed with security in mind. The linters do not require
network access or persistent storage, making the container suitable for
restricted environments.

### Recommended Security Flags

For maximum security, run the container with these flags:

```bash
docker run --rm \
  --network=none \
  --read-only \
  --tmpfs /tmp \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  -v "$PWD:/work" -w /work \
  doc-lint:latest lint docs/
```

**Flag explanations:**

- `--network=none`: Disables all network access. Linters are offline tools
  and do not need network connectivity.
- `--read-only`: Makes the container filesystem read-only, preventing any
  writes except to explicitly mounted volumes or tmpfs.
- `--tmpfs /tmp`: Provides a temporary writable filesystem for `/tmp`, which
  is required for Mermaid diagram rendering (SVG output) and other temporary
  operations.
- `--security-opt=no-new-privileges`: Prevents processes from gaining
  additional privileges via setuid/setgid binaries.
- `--cap-drop=ALL`: Drops all Linux capabilities. The linters do not require
  any special capabilities.

### Trade-offs

- **`--read-only` with Mermaid**: Mermaid rendering requires writing SVG files to `/tmp`.
  The `--tmpfs /tmp` flag provides a writable temporary directory while keeping
  the rest of the filesystem read-only.
- **Cache with `--read-only`**: If using `--cache`, mount a volume for the cache directory: `-v doc-lint-cache:/home/linter/.cache/doc-lint`.

### Verifying Container Security

You can verify the container's security posture using these tools:

```bash
# Inspect container configuration
docker inspect doc-lint:latest

# Analyze image layers and security
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  wagoodman/dive:latest doc-lint:latest

# Check for vulnerabilities (requires Trivy)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image doc-lint:latest
```

### Build-Time Binary Verification

Third-party binaries downloaded during image build are verified against the
release's `SHA256SUMS` artifact. For example, the `yq` binary download
verifies its SHA256 checksum before installation; a mismatch causes the
Docker build to fail. This prevents supply-chain compromise of pinned
dependencies.

### Output Escaping

Structured formatters (JSON, SARIF) use language-native serialization
(`JSON.stringify`) which inherently escapes special characters. The JUnit
XML formatter now explicitly escapes `&`, `<`, `>`, `"`, and `'` in all
interpolated values to prevent XML injection from crafted linter or plugin
output.

### Non-root User

The container runs as a non-root user (`linter`, UID 1000) by default. This
limits the impact of any potential vulnerabilities in the linters or their
dependencies.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

This project is provided as-is for use in AI Coding Agent workflows. No warranty is expressed or implied.
