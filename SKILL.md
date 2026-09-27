---
name: docs-linting
description: Lint documentation artifacts (Markdown, Mermaid, JSON, XML, YAML, TOML) produced by the Documentation Writer mode using the doc-lint Docker image. Use after writing or updating any .md, .mmd/.mermaid, .json, .xml, .yaml, .yml, or .toml doc file to verify formatting, diagram syntax, JSON validity, XML well-formedness, YAML syntax, and TOML syntax before handoff.
---

# Docs Linting

Lint documentation artifacts with the **`doc-lint`** Docker image. This is the
validation gate for the Documentation Writer mode: run it after creating or updating
any doc file, and only mark the change complete when all lints pass.

## When to use

- After `write_to_file` creates/updates a `.md`, `.mmd`/`.mermaid`, `.json`, `.xml`, `.yaml`, `.yml`, or `.toml` file.
- Before emitting the Documentation Writer handoff payload (as evidence for `evidence_ref`).
- Never to modify files — this skill is read-only validation. Fix failures via the normal
  `code` mode rework loop, not here.

## Linters used (and why)

| Format | Tool | Why this one |
| :--- | :--- | :--- |
| Markdown | `markdownlint-cli2` | De-facto standard; 100+ rules, config-driven, official Docker image. |
| Mermaid | `@mermaid-js/mermaid-cli` (`mmdc`) | Official CLI; rendering to SVG fails on syntax errors, so it doubles as a validator. |
| JSON | `node` (syntax) + `ajv` (schema) | `ajv` is the highest-volume JSON Schema validator (~272M weekly downloads). |
| XML | `xmllint` (libxml2) | Industry-standard well-formedness checker, present in every major distro. |
| YAML | `yq` | Fast, lightweight YAML processor with excellent error messages. |
| TOML | Python `tomli` | Reference TOML parser with clear syntax error reporting. |

## Image

- **Name:** `doc-lint:latest`
- **Base:** `node:20-bookworm-slim` + `chromium` (for `mmdc`) + `libxml2-utils` (for `xmllint`).
- **Entrypoint:** `/opt/lint/bin/lint` — auto-detects linters by file extension and
  aggregates exit codes. Non-zero if any lint fails.

## Build the image (only if not already present)

The skill assumes the image is built. If `docker image inspect doc-lint:latest`
fails, clone or update the repository and build the image from its `Dockerfile`:

```bash
# 1. Check whether the image already exists
if ! docker image inspect doc-lint:latest >/dev/null 2>&1; then
  # 2. Clone the repository (or pull if it already exists)
  if [ ! -d "docs-linting" ]; then
    git clone https://github.com/king-dopey/docs-linting.git
  else
    git -C docs-linting pull --ff-only
  fi
  # 3. Build the image from the cloned repository
  docker build -t doc-lint:latest ./docs-linting
fi
```

## How to run

```bash
# Lint specific files (most common — pass the exact files you just wrote)
docker run --rm \
  -v "$PWD:/work" -w /work \
  doc-lint:latest lint docs/CHANGELOG.md docs/api.md

# Lint an entire directory (recursively picks up md/mmd/json/xml/yaml/toml)
docker run --rm -v "$PWD:/work" -w /work doc-lint:latest lint docs/

# Validate JSON against a JSON Schema
docker run --rm \
  -v "$PWD:/work" -w /work \
  doc-lint:latest lint --schema schemas/review-report.schema.json docs/review-report.json

# Lint a file outside the repo (e.g., docs/plan.xml)
docker run --rm -v "$PWD:/work" -w /work doc-lint:latest lint docs/plan.xml

# Lint YAML configuration files
docker run --rm -v "$PWD:/work" -w /work doc-lint:latest lint config.yaml

# Lint TOML configuration files
docker run --rm -v "$PWD:/work" -w /work doc-lint:latest lint Cargo.toml
```

### Auto-fix mode

Automatically fix common linting violations (Markdown and JSON only):

```bash
# Auto-fix violations (creates .bak backup files by default)
docker run --rm -v "$PWD:/work" -w /work doc-lint:latest lint --fix docs/

# Auto-fix without creating backups
docker run --rm -v "$PWD:/work" -w /work doc-lint:latest lint --fix --no-backup docs/
```

**Note:** Auto-fix mode only supports Markdown and JSON. YAML, TOML, XML, and Mermaid files cannot be auto-fixed.

### Plugin system

Extend doc-lint with custom linters:

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

See [plugins/README.md](plugins/README.md) for plugin development guide.

### Exit codes
- `0` — all lints passed (or nothing to lint).
- `1` — at least one lint failed. **Stop and fix before handoff.**
- `2` — usage or environment error (missing target, bad schema path).

### Environment variables
- `DOC_LINT_WORKDIR` — working directory inside the container (default `/work`).
- `DOC_LINT_MERMAID_OUT` — where `mmdc` writes temp SVGs (default `/tmp/doc-lint-mermaid`).
- `DOC_LINT_PLUGINS_DIR` — custom plugin directory (default `/opt/lint/plugins`).
- `DOC_LINT_PLUGIN_TIMEOUT` — plugin execution timeout in seconds (default `30`).
- `DOC_LINT_FIX` — enable auto-fix mode (default `false`).
- `DOC_LINT_NO_BACKUP` — disable backup creation in auto-fix mode (default `false`).

## Interpreting output

The entrypoint prints one `==> [label] command` line per check with an `OK`/`FAIL` result,
then a final `ALL PASS` or `FAILURES DETECTED`. On failure:

1. Read the linter's stderr for the specific rule / line / error.
2. Markdown: note the `MDxxx` rule code and file:line.
3. Mermaid: the `mmdc` parser error names the offending diagram token.
4. JSON: syntax errors show a parse position; schema errors list each `instancePath` + message.
5. XML: `xmllint` reports the byte/line of the first well-formedness violation.
6. YAML: `yq` reports the line number and error message for syntax violations.
7. TOML: Python `tomli` reports the line and column for syntax errors.

## Integration with Documentation Writer mode

1. After writing doc files, run this skill on exactly those files.
2. If it passes, set handoff `evidence_ref` to the lint command + `ALL PASS`.
3. If it fails, do **not** hand off. Emit a handoff payload with
   `status=FAIL`, `blocker_tag=tool-failure`, and route back via the normal rework path
   (`switch_mode` → `code`) so the doc files are corrected.

## Constraints

- Read-only: never edit doc files from this skill.
- Deterministic: same inputs → same lint results; do not "eyeball" past a failure.
- Scope: only lints the six supported formats (Markdown, Mermaid, JSON, XML, YAML, TOML); other file types are ignored, not errors.
