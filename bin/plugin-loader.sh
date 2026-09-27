#!/usr/bin/env bash
# =============================================================================
# doc-lint: Plugin loader and executor
# =============================================================================
# Discovers and executes custom linter plugins from a specified directory.
#
# Plugin Contract:
#   - Each plugin is a directory containing plugin.json and an executable
#   - plugin.json defines: name, version, extensions, command
#   - Plugin receives file paths via stdin (one per line)
#   - Plugin outputs results in intermediate format to stdout:
#     file:line:col:rule:severity:message
#   - Exit codes: 0 = pass, 1 = fail, 2 = error
# =============================================================================
set -uo pipefail

PLUGINS_DIR="${DOC_LINT_PLUGINS_DIR:-/opt/lint/plugins}"
PLUGIN_TIMEOUT="${DOC_LINT_PLUGIN_TIMEOUT:-30}"

# ---- Discover plugins -------------------------------------------------------
# Scans plugins directory for valid plugins and returns their paths
discover_plugins() {
  local plugins_dir="$1"
  
  if [[ ! -d "$plugins_dir" ]]; then
    return 0
  fi
  
  # Find all plugin.json files
  while IFS= read -r manifest; do
    local plugin_dir
    plugin_dir=$(dirname "$manifest")
    
    # Validate manifest
    if validate_plugin_manifest "$manifest"; then
      echo "$plugin_dir"
    fi
  done < <(find "$plugins_dir" -maxdepth 2 -name "plugin.json" -type f 2>/dev/null)
}

# ---- Validate plugin manifest -----------------------------------------------
# Checks if plugin.json has required fields and valid structure
validate_plugin_manifest() {
  local manifest="$1"
  
  # Check if file exists and is readable
  if [[ ! -f "$manifest" || ! -r "$manifest" ]]; then
    echo "doc-lint: plugin manifest not found or not readable: $manifest" >&2
    return 1
  fi
  
  # Parse JSON and check required fields
  local name version extensions command
  name=$(jq -r '.name // empty' "$manifest" 2>/dev/null)
  version=$(jq -r '.version // empty' "$manifest" 2>/dev/null)
  extensions=$(jq -r '.extensions // empty' "$manifest" 2>/dev/null)
  command=$(jq -r '.command // empty' "$manifest" 2>/dev/null)
  
  # Validate required fields
  if [[ -z "$name" ]]; then
    echo "doc-lint: plugin missing required field 'name': $manifest" >&2
    return 1
  fi
  
  if [[ -z "$version" ]]; then
    echo "doc-lint: plugin missing required field 'version': $manifest" >&2
    return 1
  fi
  
  if [[ -z "$extensions" || "$extensions" == "null" ]]; then
    echo "doc-lint: plugin missing required field 'extensions': $manifest" >&2
    return 1
  fi
  
  if [[ -z "$command" ]]; then
    echo "doc-lint: plugin missing required field 'command': $manifest" >&2
    return 1
  fi
  
  # Check if command executable exists
  local plugin_dir
  plugin_dir=$(dirname "$manifest")
  local cmd_path="$plugin_dir/$command"
  
  if [[ ! -f "$cmd_path" ]]; then
    echo "doc-lint: plugin command not found: $cmd_path" >&2
    return 1
  fi
  
  if [[ ! -x "$cmd_path" ]]; then
    echo "doc-lint: plugin command not executable: $cmd_path" >&2
    return 1
  fi
  
  return 0
}

# ---- Get plugin metadata ----------------------------------------------------
# Extracts metadata from plugin.json
get_plugin_metadata() {
  local manifest="$1"
  local field="$2"
  
  jq -r ".$field // empty" "$manifest" 2>/dev/null
}

# ---- Get plugin extensions --------------------------------------------------
# Returns space-separated list of file extensions handled by plugin
get_plugin_extensions() {
  local manifest="$1"
  
  jq -r '.extensions[]?' "$manifest" 2>/dev/null | tr '\n' ' '
}

# ---- Execute plugin ---------------------------------------------------------
# Runs a plugin with the given files and captures output
execute_plugin() {
  local plugin_dir="$1"
  shift
  local files=("$@")
  
  local manifest="$plugin_dir/plugin.json"
  local command
  command=$(get_plugin_metadata "$manifest" "command")
  local cmd_path="$plugin_dir/$command"
  
  # Execute plugin with timeout
  local output
  local exit_code=0
  
  # Pass files via stdin
  output=$(printf '%s\n' "${files[@]}" | timeout "$PLUGIN_TIMEOUT" "$cmd_path" 2>&1) || exit_code=$?
  
  # Handle timeout
  if [[ $exit_code -eq 124 ]]; then
    echo "doc-lint: plugin timed out after ${PLUGIN_TIMEOUT}s: $plugin_dir" >&2
    return 2
  fi
  
  # Output results to stdout
  echo "$output"
  
  return $exit_code
}

# ---- Match files to plugins -------------------------------------------------
# Returns plugins that handle the given file extensions
match_files_to_plugins() {
  local plugins_dir="$1"
  shift
  local files=("$@")
  
  # Build extension map
  declare -A ext_to_plugin
  
  while IFS= read -r plugin_dir; do
    [[ -z "$plugin_dir" ]] && continue
    
    local manifest="$plugin_dir/plugin.json"
    local extensions
    extensions=$(get_plugin_extensions "$manifest")
    
    for ext in $extensions; do
      # Normalize extension (ensure it starts with .)
      if [[ "$ext" != .* ]]; then
        ext=".$ext"
      fi
      ext_to_plugin["$ext"]="$plugin_dir"
    done
  done < <(discover_plugins "$plugins_dir")
  
  # Match files to plugins
  declare -A plugin_files
  
  for file in "${files[@]}"; do
    local ext=".${file##*.}"
    
    if [[ -n "${ext_to_plugin[$ext]:-}" ]]; then
      local plugin_dir="${ext_to_plugin[$ext]}"
      plugin_files["$plugin_dir"]+="$file"$'\n'
    fi
  done
  
  # Output plugin:files pairs
  for plugin_dir in "${!plugin_files[@]}"; do
    local files_list="${plugin_files[$plugin_dir]}"
    echo "$plugin_dir|$files_list"
  done
}

# ---- Main execution ---------------------------------------------------------
# If called directly, run discovery and validation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Discovering plugins in: $PLUGINS_DIR"
  
  while IFS= read -r plugin_dir; do
    [[ -z "$plugin_dir" ]] && continue
    
    manifest="$plugin_dir/plugin.json"
    name=""
    version=""
    name=$(get_plugin_metadata "$manifest" "name")
    version=$(get_plugin_metadata "$manifest" "version")
    
    echo "  ✓ $name v$version"
  done < <(discover_plugins "$PLUGINS_DIR")
fi
