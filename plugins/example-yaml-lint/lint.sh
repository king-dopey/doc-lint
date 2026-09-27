#!/usr/bin/env bash
# =============================================================================
# Example YAML linter plugin
# =============================================================================
# Validates YAML syntax using yq
# Input: File paths via stdin (one per line)
# Output: Results in intermediate format to stdout
# =============================================================================
set -uo pipefail

# Read file paths from stdin
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ ! -f "$file" ]] && continue
  
  # Validate YAML syntax using yq
  if ! yq eval '.' "$file" > /dev/null 2>&1; then
    # Parse error message
    error_output=$(yq eval '.' "$file" 2>&1)
    
    # Extract line number if available
    line=$(echo "$error_output" | grep -oP 'line \K[0-9]+' | head -1)
    line=${line:-1}
    
    # Extract column if available
    col=$(echo "$error_output" | grep -oP 'column \K[0-9]+' | head -1)
    col=${col:-1}
    
    # Extract error message
    message=$(echo "$error_output" | head -1 | sed 's/^.*: //')
    
    # Output in intermediate format
    echo "$file:$line:$col:yaml-syntax:error:$message"
  fi
done

exit 0
