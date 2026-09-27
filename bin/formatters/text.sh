#!/usr/bin/env bash
# =============================================================================
# doc-lint text formatter
# =============================================================================
# Reads intermediate format from stdin and produces human-readable text output.
# Intermediate format: file:line:col:rule:severity:message
# =============================================================================
set -uo pipefail

while IFS=: read -r file line col rule severity message; do
  [[ -z "$file" ]] && continue
  echo "$file:$line:$col: $rule ($severity) - $message"
done
