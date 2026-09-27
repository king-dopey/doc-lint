#!/usr/bin/env bash
# =============================================================================
# doc-lint: Generic documentation linting entrypoint
# =============================================================================
# Lints documentation artifacts by extension and aggregates results.
#
#   markdown (.md/.markdown)  -> markdownlint-cli2
#   mermaid  (.mmd/.mermaid)  -> mmdc (render-to-svg; fails on syntax errors)
#   json     (.json)          -> node JSON.parse (syntax) [+ ajv if schema given]
#   xml      (.xml)           -> xmllint --noout (well-formedness)
#   yaml     (.yaml/.yml)     -> yq eval (syntax validation)
#   toml     (.toml)          -> python3 tomli (syntax validation)
#
# Usage:
#   lint <path> [path ...]            # lint files and/or directories
#   lint --schema file.json <json>    # also validate JSON against a schema
#   lint --format json <path>         # output in JSON format
#   lint --format sarif <path>        # output in SARIF format (GitHub Code Scanning)
#   lint --format junit <path>        # output in JUnit XML format
#   lint --parallel <path>            # run linters in parallel (default: sequential)
#   lint --exclude <pattern> <path>   # exclude files matching pattern (can be repeated)
#   lint --plugins-dir <path>         # specify custom plugin directory
#   lint --fix <path>                 # auto-fix violations (Markdown/JSON only)
#   lint --no-backup                  # skip backup creation in fix mode
#
# Exit codes: 0 = all pass, 1 = at least one fail, 2 = usage/env error
# =============================================================================
set -uo pipefail

# Source cache helpers
# shellcheck disable=SC1091
source /opt/lint/bin/cache.sh

# Source plugin loader
# shellcheck disable=SC1091
source /opt/lint/bin/plugin-loader.sh

WORKDIR="${DOC_LINT_WORKDIR:-$(pwd)}"
MERMAID_OUT_DIR="${DOC_LINT_MERMAID_OUT:-/tmp/doc-lint-mermaid}"
PLUGINS_DIR="${DOC_LINT_PLUGINS_DIR:-/opt/lint/plugins}"
SCHEMA_FILE=""
FORMAT="${DOC_LINT_FORMAT:-text}"
PARALLEL="${DOC_LINT_PARALLEL:-false}"
CACHE_ENABLED="${DOC_LINT_CACHE:-false}"
CACHE_CLEAN_DAYS=""
FIX_MODE="${DOC_LINT_FIX:-false}"
NO_BACKUP="${DOC_LINT_NO_BACKUP:-false}"
TARGETS=()
EXCLUDE_PATTERNS=()
RESULTS_FILE=""
PARALLEL_DIR=""

# ---- Parse args -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --schema)    SCHEMA_FILE="$2"; shift 2 ;;
    --workdir)   WORKDIR="$2"; shift 2 ;;
    --format)    FORMAT="$2"; shift 2 ;;
    --parallel)  PARALLEL="true"; shift ;;
    --no-parallel) PARALLEL="false"; shift ;;
    --cache)     CACHE_ENABLED="true"; shift ;;
    --no-cache)  CACHE_ENABLED="false"; shift ;;
    --cache-clean) CACHE_CLEAN_DAYS="${2:-30}"; shift 2 ;;
    --exclude)   EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
    --plugins-dir) PLUGINS_DIR="$2"; shift 2 ;;
    --fix)       FIX_MODE="true"; shift ;;
    --no-backup) NO_BACKUP="true"; shift ;;
    -h|--help)   sed -n '2,26p' "$0"; exit 0 ;;
    *)           TARGETS+=("$1"); shift ;;
  esac
done

# Validate format
case "$FORMAT" in
  text|json|junit|sarif) ;;
  *)
    echo "doc-lint: unknown format '$FORMAT'. Use text, json, junit, or sarif." >&2
    exit 2
    ;;
esac

cd "$WORKDIR" || exit 1

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "doc-lint: no targets given. Pass files or directories to lint." >&2
  exit 2
fi

mkdir -p "$MERMAID_OUT_DIR"

# ---- Handle cache-clean and exit --------------------------------------------
if [[ -n "$CACHE_CLEAN_DAYS" ]]; then
  cache_clean "$CACHE_CLEAN_DAYS"
  exit 0
fi

# ---- Initialize cache -------------------------------------------------------
cache_init

# Compute cache key for all input files
CACHE_KEY_INPUT="${TARGETS[*]}"
for target in "${TARGETS[@]}"; do
  if [[ -f "$target" ]]; then
    CACHE_KEY_INPUT+="$(sha256sum "$target" 2>/dev/null | cut -d' ' -f1)"
  elif [[ -d "$target" ]]; then
    CACHE_KEY_INPUT+="$(find "$target" -type f \( -name '*.md' -o -name '*.mmd' -o -name '*.json' -o -name '*.xml' -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' \) -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -d' ' -f1)"
  fi
done

# Check cache
if cache_get "$CACHE_KEY_INPUT"; then
  echo "doc-lint: cache hit, skipping linting"
  exit "$CACHE_EXIT_CODE"
fi

# ---- Intermediate results collection ----------------------------------------
# For non-text formats, collect results in intermediate format:
# file:line:col:rule:severity:message
if [[ "$FORMAT" != "text" ]]; then
  RESULTS_FILE=$(mktemp /tmp/doc-lint-results.XXXXXX)
fi

# ---- Parallel processing temp directory -------------------------------------
if [[ "$PARALLEL" == "true" ]]; then
  PARALLEL_DIR=$(mktemp -d /tmp/doc-lint-parallel.XXXXXX)
fi

# Cleanup on exit
cleanup() {
  # shellcheck disable=SC2317
  [[ -n "$RESULTS_FILE" && -f "$RESULTS_FILE" ]] && rm -f "$RESULTS_FILE"
  # shellcheck disable=SC2317
  [[ -n "$PARALLEL_DIR" && -d "$PARALLEL_DIR" ]] && rm -rf "$PARALLEL_DIR"
}
trap cleanup EXIT

# ---- Collect files by extension --------------------------------------------
declare -a MD_FILES=() MMMD_FILES=() JSON_FILES=() XML_FILES=() YAML_FILES=() TOML_FILES=()

# Check if file matches any exclusion pattern
is_excluded() {
  local file="$1"
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    # Use bash pattern matching
    # shellcheck disable=SC2053
    if [[ "$file" == $pattern ]]; then
      return 0
    fi
  done
  return 1
}

collect() {
  local p="$1"
  if [[ -d "$p" ]]; then
    while IFS= read -r f; do
      # Skip if excluded
      if is_excluded "$f"; then
        continue
      fi
      
      case "${f##*.}" in
        md|markdown)  MD_FILES+=("$f") ;;
        mmd|mermaid)  MMMD_FILES+=("$f") ;;
        json)         JSON_FILES+=("$f") ;;
        xml)          XML_FILES+=("$f") ;;
        yaml|yml)     YAML_FILES+=("$f") ;;
        toml)         TOML_FILES+=("$f") ;;
      esac
    done < <(find "$p" -type f \( -name '*.md' -o -name '*.markdown' -o -name '*.mmd' -o -name '*.mermaid' -o -name '*.json' -o -name '*.xml' -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' \) -not -path '*/node_modules/*' -not -path '*/.git/*')
  elif [[ -f "$p" ]]; then
    # Skip if excluded
    if is_excluded "$p"; then
      return 0
    fi
    
    case "${p##*.}" in
      md|markdown)  MD_FILES+=("$p") ;;
      mmd|mermaid)  MMMD_FILES+=("$p") ;;
      json)         JSON_FILES+=("$p") ;;
      xml)          XML_FILES+=("$p") ;;
      yaml|yml)     YAML_FILES+=("$p") ;;
      toml)         TOML_FILES+=("$p") ;;
    esac
  else
    echo "doc-lint: target not found: $p" >&2
    exit 2
  fi
}
for t in "${TARGETS[@]}"; do collect "$t"; done

# ---- Auto-fix mode ----------------------------------------------------------
if [[ "$FIX_MODE" == "true" ]]; then
  echo "==> [fix-mode] Auto-fixing violations..."
  
  # Fix Markdown files
  if [[ ${#MD_FILES[@]} -gt 0 ]]; then
    echo "  Fixing ${#MD_FILES[@]} markdown file(s)..."
    for f in "${MD_FILES[@]}"; do
      # Create backup unless --no-backup is set
      if [[ "$NO_BACKUP" != "true" ]]; then
        cp "$f" "$f.bak"
      fi
      # Run markdownlint with --fix
      if npx --no-install markdownlint-cli2 --fix "$f" > /dev/null 2>&1; then
        echo "    ✓ Fixed: $f"
      else
        echo "    ✗ Failed to fix: $f" >&2
      fi
    done
  fi
  
  # Fix JSON files
  if [[ ${#JSON_FILES[@]} -gt 0 ]]; then
    echo "  Fixing ${#JSON_FILES[@]} JSON file(s)..."
    for f in "${JSON_FILES[@]}"; do
      # Create backup unless --no-backup is set
      if [[ "$NO_BACKUP" != "true" ]]; then
        cp "$f" "$f.bak"
      fi
      # Run prettier to format JSON
      if npx --no-install prettier --write "$f" > /dev/null 2>&1; then
        echo "    ✓ Fixed: $f"
      else
        echo "    ✗ Failed to fix: $f" >&2
      fi
    done
  fi
  
  echo "  Auto-fix complete."
  echo ""
fi

FAIL=0

# ---- Helper: record result for structured formats ---------------------------
record_result() {
  local file="$1" line="$2" col="$3" rule="$4" severity="$5" message="$6"
  if [[ -n "$RESULTS_FILE" ]]; then
    echo "${file}:${line}:${col}:${rule}:${severity}:${message}" >> "$RESULTS_FILE"
  fi
}

# ---- Helper: record result from intermediate format line --------------------
record_result_from_line() {
  local line="$1"
  if [[ -n "$RESULTS_FILE" ]]; then
    echo "$line" >> "$RESULTS_FILE"
  fi
}

# ---- Helper: run linter (text mode) -----------------------------------------
run() { # run <label> <cmd...>
  local label="$1"; shift
  echo "==> [${label}] $*"
  if "$@"; then
    echo "    OK"
  else
    echo "    FAIL" >&2
    FAIL=1
  fi
}

# ---- Helper: run linter and capture output for structured formats -----------
run_and_capture() { # run_and_capture <label> <format_type> <cmd...>
  local label="$1"; shift
  local format_type="$1"; shift
  local output
  local exit_code=0
  
  output=$("$@" 2>&1) || exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    if [[ "$FORMAT" == "text" ]]; then
      echo "==> [${label}] OK"
    fi
  else
    FAIL=1
    if [[ "$FORMAT" == "text" ]]; then
      echo "==> [${label}] $*"
      echo "$output"
      echo "    FAIL" >&2
    else
      # Parse output based on format_type and record results
      parse_linter_output "$format_type" "$label" "$output"
    fi
  fi
}

# ---- Helper: parse linter output into intermediate format -------------------
parse_linter_output() {
  local format_type="$1"
  local label="$2"
  local output="$3"
  
  case "$format_type" in
    markdown)
      # markdownlint-cli2 output: "file:line:col rule message" or similar
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Try to parse "file:line:col MDxxx message"
        if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+)[[:space:]]+(MD[0-9]+)[[:space:]]+(.*) ]]; then
          record_result "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "error" "${BASH_REMATCH[5]}"
        elif [[ "$line" =~ ^([^:]+):([0-9]+)[[:space:]]+(MD[0-9]+)[[:space:]]+(.*) ]]; then
          record_result "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "1" "${BASH_REMATCH[3]}" "error" "${BASH_REMATCH[4]}"
        fi
      done <<< "$output"
      ;;
    mermaid)
      # mmdc output: error messages, may not have line/col
      record_result "$label" "1" "1" "mermaid-syntax" "error" "Mermaid diagram syntax error"
      ;;
    json-syntax)
      # Node.js JSON.parse error: "Unexpected token X in JSON at position Y"
      if [[ "$output" =~ Unexpected[[:space:]]+token[[:space:]]+.*[[:space:]]+in[[:space:]]+JSON[[:space:]]+at[[:space:]]+position[[:space:]]+([0-9]+) ]]; then
        record_result "$label" "1" "1" "json-syntax" "error" "JSON syntax error at position ${BASH_REMATCH[1]}"
      else
        record_result "$label" "1" "1" "json-syntax" "error" "JSON syntax error"
      fi
      ;;
    json-schema)
      # ajv output: "instancePath: message"
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^\[json-schema\][[:space:]]+(.*):[[:space:]]+(.*) ]]; then
          local path="${BASH_REMATCH[1]}"
          local msg="${BASH_REMATCH[2]}"
          if [[ "$path" == "INVALID" ]]; then
            continue
          fi
          record_result "$label" "1" "1" "json-schema" "error" "$path: $msg"
        fi
      done <<< "$output"
      ;;
    xml)
      # xmllint output: "file:line: parser error : message"
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([^:]+):([0-9]+):[[:space:]]+parser[[:space:]]+error[[:space:]]+:[[:space:]]+(.*) ]]; then
          record_result "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "1" "xml-wellformed" "error" "${BASH_REMATCH[3]}"
        fi
      done <<< "$output"
      ;;
    yaml)
      # yq output: "Error: bad file 'file.yaml': yaml: line X: mapping values are not allowed in this context"
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ Error:[[:space:]]+bad[[:space:]]+file[[:space:]]+\'([^\']+)\':[[:space:]]+yaml:[[:space:]]+line[[:space:]]+([0-9]+):[[:space:]]+(.*) ]]; then
          record_result "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "1" "yaml-syntax" "error" "${BASH_REMATCH[3]}"
        elif [[ "$line" =~ Error:[[:space:]]+(.*) ]]; then
          record_result "$label" "1" "1" "yaml-syntax" "error" "${BASH_REMATCH[1]}"
        fi
      done <<< "$output"
      ;;
    toml)
      # Python tomli output: "Error parsing TOML file: ..."
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ TOML[[:space:]]+parse[[:space:]]+error[[:space:]]+at[[:space:]]+line[[:space:]]+([0-9]+),[[:space:]]+column[[:space:]]+([0-9]+) ]]; then
          record_result "$label" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "toml-syntax" "error" "$line"
        elif [[ "$line" =~ Error:[[:space:]]+(.*) ]]; then
          record_result "$label" "1" "1" "toml-syntax" "error" "${BASH_REMATCH[1]}"
        fi
      done <<< "$output"
      ;;
  esac
}

# ---- Parallel linter functions ----------------------------------------------
# These functions are designed to run in background jobs when PARALLEL=true

run_markdown_parallel() {
  local output_file="$PARALLEL_DIR/markdown.out"
  local exit_file="$PARALLEL_DIR/markdown.exit"
  local results_file="$PARALLEL_DIR/markdown.results"
  
  local local_config_present=false
  for c in .markdownlint.json .markdownlint.jsonc .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs .markdownlint-cli2.jsonc .markdownlint-cli2.yaml; do
    [[ -f "$c" ]] && local_config_present=true && break
  done
  
  local exit_code=0
  if $local_config_present; then
    npx --no-install markdownlint-cli2 "${MD_FILES[@]}" > "$output_file" 2>&1 || exit_code=$?
  else
    npx --no-install markdownlint-cli2 --config /opt/lint/configs/.markdownlint.yaml "${MD_FILES[@]}" > "$output_file" 2>&1 || exit_code=$?
  fi
  
  echo "$exit_code" > "$exit_file"
  
  if [[ "$FORMAT" != "text" && $exit_code -ne 0 ]]; then
    # Parse and record results
    local output
    output=$(cat "$output_file")
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+)[[:space:]]+(MD[0-9]+)[[:space:]]+(.*) ]]; then
        echo "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}:error:${BASH_REMATCH[5]}" >> "$results_file"
      elif [[ "$line" =~ ^([^:]+):([0-9]+)[[:space:]]+(MD[0-9]+)[[:space:]]+(.*) ]]; then
        echo "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:1:${BASH_REMATCH[3]}:error:${BASH_REMATCH[4]}" >> "$results_file"
      fi
    done <<< "$output"
  fi
}

run_mermaid_parallel() {
  local output_file="$PARALLEL_DIR/mermaid.out"
  local exit_file="$PARALLEL_DIR/mermaid.exit"
  local results_file="$PARALLEL_DIR/mermaid.results"
  
  local exit_code=0
  for f in "${MMMD_FILES[@]}"; do
    [[ -z "$f" ]] && continue
    local out
    out="$MERMAID_OUT_DIR/$(basename "${f%.*}").svg"
    mmdc -i "$f" -o "$out" -q -p /opt/lint/puppeteer-config.json >> "$output_file" 2>&1 || exit_code=$?
  done
  
  echo "$exit_code" > "$exit_file"
  
  if [[ "$FORMAT" != "text" && $exit_code -ne 0 ]]; then
    for f in "${MMMD_FILES[@]}"; do
      [[ -z "$f" ]] && continue
      echo "$f:1:1:mermaid-syntax:error:Mermaid diagram syntax error" >> "$results_file"
    done
  fi
}

run_json_parallel() {
  local output_file="$PARALLEL_DIR/json.out"
  local exit_file="$PARALLEL_DIR/json.exit"
  local results_file="$PARALLEL_DIR/json.results"
  
  local exit_code=0
  for f in "${JSON_FILES[@]}"; do
    [[ -z "$f" ]] && continue
    node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$f" >> "$output_file" 2>&1 || exit_code=$?
    if [[ -n "$SCHEMA_FILE" ]]; then
      node /opt/lint/bin/json-schema-check.js "$f" "$SCHEMA_FILE" >> "$output_file" 2>&1 || exit_code=$?
    fi
  done
  
  echo "$exit_code" > "$exit_file"
  
  if [[ "$FORMAT" != "text" && $exit_code -ne 0 ]]; then
    local output
    output=$(cat "$output_file")
    for f in "${JSON_FILES[@]}"; do
      [[ -z "$f" ]] && continue
      if [[ "$output" =~ Unexpected[[:space:]]+token ]]; then
        echo "$f:1:1:json-syntax:error:JSON syntax error" >> "$results_file"
      fi
    done
  fi
}

run_xml_parallel() {
  local output_file="$PARALLEL_DIR/xml.out"
  local exit_file="$PARALLEL_DIR/xml.exit"
  local results_file="$PARALLEL_DIR/xml.results"
  
  local exit_code=0
  for f in "${XML_FILES[@]}"; do
    [[ -z "$f" ]] && continue
    xmllint --noout --nonet "$f" >> "$output_file" 2>&1 || exit_code=$?
  done
  
  echo "$exit_code" > "$exit_file"
  
  if [[ "$FORMAT" != "text" && $exit_code -ne 0 ]]; then
    local output
    output=$(cat "$output_file")
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" =~ ^([^:]+):([0-9]+):[[:space:]]+parser[[:space:]]+error[[:space:]]+:[[:space:]]+(.*) ]]; then
        echo "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:1:xml-wellformed:error:${BASH_REMATCH[3]}" >> "$results_file"
      fi
    done <<< "$output"
  fi
}

run_yaml_parallel() {
  local output_file="$PARALLEL_DIR/yaml.out"
  local exit_file="$PARALLEL_DIR/yaml.exit"
  local results_file="$PARALLEL_DIR/yaml.results"
  
  local exit_code=0
  for f in "${YAML_FILES[@]}"; do
    [[ -z "$f" ]] && continue
    yq eval '.' "$f" > /dev/null 2>> "$output_file" || exit_code=$?
  done
  
  echo "$exit_code" > "$exit_file"
  
  if [[ "$FORMAT" != "text" && $exit_code -ne 0 ]]; then
    local output
    output=$(cat "$output_file")
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" =~ Error:[[:space:]]+bad[[:space:]]+file[[:space:]]+\'([^\']+)\':[[:space:]]+yaml:[[:space:]]+line[[:space:]]+([0-9]+):[[:space:]]+(.*) ]]; then
        echo "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:1:yaml-syntax:error:${BASH_REMATCH[3]}" >> "$results_file"
      fi
    done <<< "$output"
  fi
}

run_toml_parallel() {
  local output_file="$PARALLEL_DIR/toml.out"
  local exit_file="$PARALLEL_DIR/toml.exit"
  local results_file="$PARALLEL_DIR/toml.results"
  
  local exit_code=0
  for f in "${TOML_FILES[@]}"; do
    [[ -z "$f" ]] && continue
    python3 -c "import tomli, sys; tomli.load(open(sys.argv[1], 'rb'))" "$f" > /dev/null 2>> "$output_file" || exit_code=$?
  done
  
  echo "$exit_code" > "$exit_file"
  
  if [[ "$FORMAT" != "text" && $exit_code -ne 0 ]]; then
    local output
    output=$(cat "$output_file")
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" =~ TOML[[:space:]]+parse[[:space:]]+error[[:space:]]+at[[:space:]]+line[[:space:]]+([0-9]+),[[:space:]]+column[[:space:]]+([0-9]+) ]]; then
        echo "$f:${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:toml-syntax:error:$line" >> "$results_file"
      fi
    done <<< "$output"
  fi
}

# ---- Execute linters --------------------------------------------------------
if [[ "$PARALLEL" == "true" ]]; then
  # Parallel execution
  declare -a PIDS=()
  
  if [[ ${#MD_FILES[@]} -gt 0 ]]; then
    run_markdown_parallel &
    PIDS+=($!)
  fi
  
  if [[ ${#MMMD_FILES[@]} -gt 0 ]]; then
    run_mermaid_parallel &
    PIDS+=($!)
  fi
  
  if [[ ${#JSON_FILES[@]} -gt 0 ]]; then
    run_json_parallel &
    PIDS+=($!)
  fi
  
  if [[ ${#XML_FILES[@]} -gt 0 ]]; then
    run_xml_parallel &
    PIDS+=($!)
  fi
  
  if [[ ${#YAML_FILES[@]} -gt 0 ]]; then
    run_yaml_parallel &
    PIDS+=($!)
  fi
  
  if [[ ${#TOML_FILES[@]} -gt 0 ]]; then
    run_toml_parallel &
    PIDS+=($!)
  fi
  
  # Wait for all background jobs
  for pid in "${PIDS[@]}"; do
    wait "$pid" || true
  done
  
  # Aggregate results
  for format_type in markdown mermaid json xml yaml toml; do
    exit_file="$PARALLEL_DIR/$format_type.exit"
    output_file="$PARALLEL_DIR/$format_type.out"
    results_file="$PARALLEL_DIR/$format_type.results"
    
    if [[ -f "$exit_file" ]]; then
      exit_code=$(cat "$exit_file")
      if [[ $exit_code -ne 0 ]]; then
        FAIL=1
      fi
      
      if [[ "$FORMAT" == "text" ]]; then
        echo "==> [$format_type]"
        if [[ -f "$output_file" ]]; then
          cat "$output_file"
        fi
        if [[ $exit_code -eq 0 ]]; then
          echo "    OK"
        else
          echo "    FAIL" >&2
        fi
      fi
    fi
    
    # Merge results for structured formats
    if [[ "$FORMAT" != "text" && -f "$results_file" ]]; then
      cat "$results_file" >> "$RESULTS_FILE"
    fi
  done
else
  # Sequential execution (original behavior)
  # ---- Markdown ---------------------------------------------------------------
  if [[ ${#MD_FILES[@]} -gt 0 ]]; then
    local_config_present=false
    for c in .markdownlint.json .markdownlint.jsonc .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs .markdownlint-cli2.jsonc .markdownlint-cli2.yaml; do
      [[ -f "$c" ]] && local_config_present=true && break
    done
    if [[ "$FORMAT" == "text" ]]; then
      if $local_config_present; then
        run "markdown" npx --no-install markdownlint-cli2 "${MD_FILES[@]}"
      else
        run "markdown" npx --no-install markdownlint-cli2 --config /opt/lint/configs/.markdownlint.yaml "${MD_FILES[@]}"
      fi
    else
      if $local_config_present; then
        run_and_capture "markdown" "markdown" npx --no-install markdownlint-cli2 "${MD_FILES[@]}"
      else
        run_and_capture "markdown" "markdown" npx --no-install markdownlint-cli2 --config /opt/lint/configs/.markdownlint.yaml "${MD_FILES[@]}"
      fi
    fi
  fi
  
  # ---- Mermaid ----------------------------------------------------------------
  for f in "${MMMD_FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    out="$MERMAID_OUT_DIR/$(basename "${f%.*}").svg"
    if [[ "$FORMAT" == "text" ]]; then
      run "mermaid:$f" mmdc -i "$f" -o "$out" -q -p /opt/lint/puppeteer-config.json
    else
      run_and_capture "mermaid:$f" "mermaid" mmdc -i "$f" -o "$out" -q -p /opt/lint/puppeteer-config.json
    fi
  done
  
  # ---- JSON -------------------------------------------------------------------
  for f in "${JSON_FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    if [[ "$FORMAT" == "text" ]]; then
      run "json-syntax:$f" node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$f"
      if [[ -n "$SCHEMA_FILE" ]]; then
        run "json-schema:$f" node /opt/lint/bin/json-schema-check.js "$f" "$SCHEMA_FILE"
      fi
    else
      run_and_capture "json-syntax:$f" "json-syntax" node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$f"
      if [[ -n "$SCHEMA_FILE" ]]; then
        run_and_capture "json-schema:$f" "json-schema" node /opt/lint/bin/json-schema-check.js "$f" "$SCHEMA_FILE"
      fi
    fi
  done
  
  # ---- XML --------------------------------------------------------------------
  for f in "${XML_FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    if [[ "$FORMAT" == "text" ]]; then
      run "xml-wellformed:$f" xmllint --noout --nonet "$f"
    else
      run_and_capture "xml-wellformed:$f" "xml" xmllint --noout --nonet "$f"
    fi
  done
  
  # ---- YAML -------------------------------------------------------------------
  for f in "${YAML_FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    if [[ "$FORMAT" == "text" ]]; then
      run "yaml:$f" yq eval '.' "$f" > /dev/null
    else
      run_and_capture "yaml:$f" "yaml" yq eval '.' "$f" > /dev/null
    fi
  done
  
  # ---- TOML -------------------------------------------------------------------
  for f in "${TOML_FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    if [[ "$FORMAT" == "text" ]]; then
      run "toml:$f" python3 -c "import tomli, sys; tomli.load(open(sys.argv[1], 'rb'))" "$f" > /dev/null
    else
      run_and_capture "toml:$f" "toml" python3 -c "import tomli, sys; tomli.load(open(sys.argv[1], 'rb'))" "$f" > /dev/null
    fi
  done
fi

# ---- Execute plugins --------------------------------------------------------
if [[ -d "$PLUGINS_DIR" ]]; then
  # Discover plugins
  mapfile -t AVAILABLE_PLUGINS < <(discover_plugins "$PLUGINS_DIR")
  
  if [[ ${#AVAILABLE_PLUGINS[@]} -gt 0 ]]; then
    # Collect all files for plugin matching
    ALL_FILES=("${MD_FILES[@]}" "${MMMD_FILES[@]}" "${JSON_FILES[@]}" "${XML_FILES[@]}" "${YAML_FILES[@]}" "${TOML_FILES[@]}")
    
    # Match files to plugins
    while IFS='|' read -r plugin_dir files_list; do
      [[ -z "$plugin_dir" ]] && continue
      
      # Convert newline-separated list to array
      mapfile -t plugin_files <<< "$files_list"
      # Remove empty entries
      plugin_files=("${plugin_files[@]/#/}")
      plugin_files=("${plugin_files[@]%$'\n'}")
      
      if [[ ${#plugin_files[@]} -gt 0 ]]; then
        # Get plugin name
        plugin_name=$(basename "$plugin_dir")
        
        if [[ "$FORMAT" == "text" ]]; then
          echo "==> [plugin:$plugin_name] ${#plugin_files[@]} file(s)"
        fi
        
        # Execute plugin
        plugin_output=$(execute_plugin "$plugin_dir" "${plugin_files[@]}")
        plugin_exit=$?
        
        if [[ $plugin_exit -eq 0 ]]; then
          if [[ "$FORMAT" == "text" ]]; then
            echo "    OK"
          fi
        elif [[ $plugin_exit -eq 1 ]]; then
          FAIL=1
          if [[ "$FORMAT" == "text" ]]; then
            echo "$plugin_output"
            echo "    FAIL" >&2
          else
            # Parse plugin output (already in intermediate format)
            while IFS= read -r line; do
              [[ -z "$line" ]] && continue
              record_result_from_line "$line"
            done <<< "$plugin_output"
          fi
        else
          # Plugin error
          echo "doc-lint: plugin error ($plugin_exit): $plugin_name" >&2
          if [[ -n "$plugin_output" ]]; then
            echo "$plugin_output" >&2
          fi
        fi
      fi
    done < <(match_files_to_plugins "$PLUGINS_DIR" "${ALL_FILES[@]}")
  fi
fi

# ---- Output -----------------------------------------------------------------
if [[ "$FORMAT" == "text" ]]; then
  echo ""
  if [[ $FAIL -eq 0 ]]; then
    echo "doc-lint: ALL PASS"
  else
    echo "doc-lint: FAILURES DETECTED" >&2
  fi
else
  # Invoke the appropriate formatter
  FORMATTER_SCRIPT="/opt/lint/formatters/${FORMAT}.sh"
  if [[ -f "$FORMATTER_SCRIPT" ]]; then
    if [[ "$FORMAT" == "json" || "$FORMAT" == "sarif" ]]; then
      node "$FORMATTER_SCRIPT" < "$RESULTS_FILE"
    else
      bash "$FORMATTER_SCRIPT" < "$RESULTS_FILE"
    fi
  else
    echo "doc-lint: formatter not found: $FORMATTER_SCRIPT" >&2
    exit 2
  fi
fi

# Store result in cache if enabled
if [[ "$CACHE_ENABLED" == "true" && -n "${CACHE_KEY_INPUT:-}" ]]; then
  cache_put "$CACHE_KEY_INPUT" "$FAIL"
fi

exit $FAIL
