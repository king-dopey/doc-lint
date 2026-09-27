# Example YAML Lint Plugin

This is an example plugin that demonstrates how to create a custom linter for doc-lint.

## What it does

Validates YAML syntax using the `yq` tool and reports errors in the intermediate format expected by doc-lint.

## Plugin Structure

```
example-yaml-lint/
├── plugin.json    # Plugin manifest with metadata
├── lint.sh        # Executable linter script
└── README.md      # This file
```

## plugin.json

The manifest file defines the plugin metadata:

```json
{
  "name": "example-yaml-lint",
  "version": "1.0.0",
  "description": "Example YAML linter plugin using yq",
  "extensions": [".yaml", ".yml"],
  "command": "./lint.sh",
  "author": "doc-lint community",
  "license": "MIT"
}
```

### Required Fields

- `name`: Unique identifier for the plugin
- `version`: Semantic version (e.g., "1.0.0")
- `extensions`: Array of file extensions this plugin handles (with or without leading dot)
- `command`: Path to the executable script (relative to plugin directory)

### Optional Fields

- `description`: Human-readable description
- `author`: Plugin author
- `license`: License identifier

## lint.sh

The linter script receives file paths via stdin and outputs results to stdout.

### Input Format

```
/path/to/file1.yaml
/path/to/file2.yml
```

### Output Format

Results must be in the intermediate format:

```
file:line:col:rule:severity:message
```

Example:

```
config.yaml:5:3:yaml-syntax:error:mapping values are not allowed here
```

### Exit Codes

- `0`: All files passed validation
- `1`: Lint failures detected (but plugin executed successfully)
- `2`: Plugin error (missing dependency, etc.)

## Usage

### Install the plugin

Copy the plugin directory to the plugins directory:

```bash
cp -r plugins/example-yaml-lint /opt/lint/plugins/
```

Or mount it when running doc-lint:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -v "$PWD/plugins:/opt/lint/plugins" \
  -w /work \
  doc-lint:latest lint config.yaml
```

### Test the plugin

```bash
# Create a test YAML file with syntax error
cat > test.yaml <<EOF
key: value
  invalid: indentation
EOF

# Run doc-lint with the plugin
docker run --rm \
  -v "$PWD:/work" \
  -v "$PWD/plugins:/opt/lint/plugins" \
  -w /work \
  doc-lint:latest lint test.yaml
```

## Creating Your Own Plugin

1. Create a new directory in `plugins/`
2. Create `plugin.json` with your plugin metadata
3. Create an executable script (e.g., `lint.sh`)
4. Implement the plugin contract:
   - Read file paths from stdin
   - Validate files using your chosen tool
   - Output results in intermediate format
   - Exit with appropriate code

## Dependencies

This example plugin requires `yq` to be installed in the doc-lint image. If your plugin requires additional tools, you'll need to:

1. Modify the Dockerfile to install them, or
2. Create a custom image based on doc-lint

## Debugging

Enable verbose output to see plugin execution:

```bash
export DOC_LINT_DEBUG=1
docker run --rm \
  -e DOC_LINT_DEBUG=1 \
  -v "$PWD:/work" \
  -v "$PWD/plugins:/opt/lint/plugins" \
  -w /work \
  doc-lint:latest lint config.yaml
```

## Timeout

Plugins have a default timeout of 30 seconds per file. Override with:

```bash
export DOC_LINT_PLUGIN_TIMEOUT=60
```

## Resources

- [Plugin Loader Source](../../bin/plugin-loader.sh)
- [doc-lint Documentation](../../README.md)
- [Intermediate Format Specification](../../README.md#intermediate-format-specification)
