# doc-lint Plugins

This directory contains custom linter plugins that extend doc-lint's functionality.

## What are Plugins?

Plugins allow you to add custom linters for file types not supported by doc-lint's built-in linters, or to use alternative linting tools for supported formats.

## Available Plugins

### example-yaml-lint

Example plugin that validates YAML syntax using `yq`.

- **Extensions**: `.yaml`, `.yml`
- **Tool**: [yq](https://github.com/mikefarah/yq)
- **Purpose**: Demonstrates plugin structure and contract

## Using Plugins

Plugins are automatically discovered from `/opt/lint/plugins/` when doc-lint runs.

### Mount Custom Plugins

```bash
docker run --rm \
  -v "$PWD:/work" \
  -v "$PWD/my-plugins:/opt/lint/plugins" \
  -w /work \
  doc-lint:latest lint config.yaml
```

### Override Plugin Directory

```bash
docker run --rm \
  -e DOC_LINT_PLUGINS_DIR=/custom/plugins \
  -v "$PWD:/work" \
  -v "$PWD/my-plugins:/custom/plugins" \
  -w /work \
  doc-lint:latest lint config.yaml
```

## Creating a Plugin

See the [example-yaml-lint](./example-yaml-lint/README.md) documentation for a complete guide.

### Quick Start

1. Create a plugin directory:
   ```bash
   mkdir -p plugins/my-linter
   ```

2. Create `plugin.json`:
   ```json
   {
     "name": "my-linter",
     "version": "1.0.0",
     "description": "My custom linter",
     "extensions": [".ext"],
     "command": "./lint.sh"
   }
   ```

3. Create executable `lint.sh`:
   ```bash
   #!/usr/bin/env bash
   # Read files from stdin, output results to stdout
   while read -r file; do
     # Your linting logic here
     echo "$file:1:1:rule:error:message"
   done
   ```

4. Make it executable:
   ```bash
   chmod +x plugins/my-linter/lint.sh
   ```

## Plugin Contract

### Input

Plugins receive file paths via **stdin**, one per line:

```
/path/to/file1.ext
/path/to/file2.ext
```

### Output

Plugins output results to **stdout** in the intermediate format:

```
file:line:col:rule:severity:message
```

Example:

```
config.yaml:5:3:yaml-syntax:error:mapping values are not allowed here
```

### Exit Codes

- `0`: All files passed validation
- `1`: Lint failures detected (plugin executed successfully)
- `2`: Plugin error (missing dependency, etc.)

### Timeout

Plugins have a default timeout of 30 seconds per file. Override with:

```bash
export DOC_LINT_PLUGIN_TIMEOUT=60
```

## Plugin Manifest Schema

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Unique plugin identifier |
| `version` | string | Semantic version (e.g., "1.0.0") |
| `extensions` | array | File extensions to handle (with or without `.`) |
| `command` | string | Path to executable (relative to plugin dir) |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Human-readable description |
| `author` | string | Plugin author |
| `license` | string | License identifier |

## Debugging

Enable debug mode to see plugin execution details:

```bash
export DOC_LINT_DEBUG=1
docker run --rm \
  -e DOC_LINT_DEBUG=1 \
  -v "$PWD:/work" \
  -v "$PWD/plugins:/opt/lint/plugins" \
  -w /work \
  doc-lint:latest lint config.yaml
```

## Security Considerations

Plugins execute arbitrary code within the doc-lint container. Only use plugins from trusted sources.

**Best Practices**:

- Review plugin source code before use
- Run doc-lint with restricted permissions (`--read-only`, `--network=none`)
- Use plugins with minimal dependencies
- Report suspicious plugins to the community

## Resources

- [Plugin Loader Source](../bin/plugin-loader.sh)
- [Example Plugin](./example-yaml-lint/)
- [doc-lint Documentation](../README.md)

## Contributing

Share your plugins with the community! Submit a pull request to add your plugin to this directory.
