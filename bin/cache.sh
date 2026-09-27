#!/usr/bin/env bash
# =============================================================================
# doc-lint: Content-addressable cache helpers
# =============================================================================
# Provides functions for caching lint results based on file content hash.
# Cache key = sha256(file_content) + linter_version + config_hash
#
# Usage: source this file from lint.sh
#
# Functions:
#   cache_init          - Initialize cache directory
#   cache_compute_key   - Compute cache key for a file
#   cache_get           - Retrieve cached result (returns 0 on hit, 1 on miss)
#   cache_put           - Store result in cache
#   cache_clean         - Remove cache entries older than N days
# =============================================================================

CACHE_DIR="${DOC_LINT_CACHE_DIR:-${HOME}/.cache/doc-lint}"
CACHE_ENABLED="${DOC_LINT_CACHE:-false}"

# Linter versions for cache key (update when linter versions change)
_CACHE_MD_VERSION="0.22.1"
_CACHE_MMMD_VERSION="11.6.0"
_CACHE_JSON_VERSION="8.17.1"
_CACHE_XML_VERSION="2.9"

# ---- Initialize cache directory ---------------------------------------------
cache_init() {
  if [[ "$CACHE_ENABLED" == "true" ]]; then
    mkdir -p "$CACHE_DIR"
  fi
}

# ---- Compute cache key for a file -------------------------------------------
# Usage: cache_compute_key <file> <linter_type>
# Returns: hash string via stdout
cache_compute_key() {
  local file="$1"
  local linter_type="$2"
  
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  
  local content_hash
  content_hash=$(sha256sum "$file" | cut -d' ' -f1)
  
  local version=""
  case "$linter_type" in
    markdown)  version="$_CACHE_MD_VERSION" ;;
    mermaid)   version="$_CACHE_MMMD_VERSION" ;;
    json)      version="$_CACHE_JSON_VERSION" ;;
    xml)       version="$_CACHE_XML_VERSION" ;;
    *)         version="unknown" ;;
  esac
  
  # Include config hash if markdownlint config exists
  local config_hash=""
  if [[ "$linter_type" == "markdown" ]]; then
    for c in .markdownlint.json .markdownlint.jsonc .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs .markdownlint-cli2.jsonc .markdownlint-cli2.yaml; do
      if [[ -f "$c" ]]; then
        config_hash=$(sha256sum "$c" | cut -d' ' -f1)
        break
      fi
    done
    # Also include bundled config
    if [[ -f /opt/lint/configs/.markdownlint.yaml ]]; then
      config_hash="${config_hash}$(sha256sum /opt/lint/configs/.markdownlint.yaml | cut -d' ' -f1)"
    fi
  fi
  
  # Include schema hash if JSON schema validation
  local schema_hash=""
  if [[ "$linter_type" == "json" && -n "${SCHEMA_FILE:-}" ]]; then
    if [[ -f "$SCHEMA_FILE" ]]; then
      schema_hash=$(sha256sum "$SCHEMA_FILE" | cut -d' ' -f1)
    fi
  fi
  
  echo "${content_hash}:${version}:${config_hash}:${schema_hash}"
}

# ---- Retrieve cached result -------------------------------------------------
# Usage: cache_get <cache_key>
# Returns: 0 on hit (result in CACHE_RESULT), 1 on miss
cache_get() {
  local key="$1"
  local key_hash
  key_hash=$(echo -n "$key" | sha256sum | cut -d' ' -f1)
  local cache_entry="$CACHE_DIR/$key_hash"
  
  if [[ -f "$cache_entry/exit_code" && -f "$cache_entry/result" ]]; then
    # shellcheck disable=SC2034
    CACHE_EXIT_CODE=$(cat "$cache_entry/exit_code")
    # shellcheck disable=SC2034
    CACHE_RESULT=$(cat "$cache_entry/result")
    # Update access time for LRU cleanup
    touch "$cache_entry"
    return 0
  fi
  
  return 1
}

# ---- Store result in cache --------------------------------------------------
# Usage: cache_put <cache_key> <exit_code> <result>
cache_put() {
  local key="$1"
  local exit_code="$2"
  local result="$3"
  
  if [[ "$CACHE_ENABLED" != "true" ]]; then
    return 0
  fi
  
  local key_hash
  key_hash=$(echo -n "$key" | sha256sum | cut -d' ' -f1)
  local cache_entry="$CACHE_DIR/$key_hash"
  
  mkdir -p "$cache_entry"
  echo "$exit_code" > "$cache_entry/exit_code"
  echo "$result" > "$cache_entry/result"
  date +%s > "$cache_entry/timestamp"
}

# ---- Clean old cache entries ------------------------------------------------
# Usage: cache_clean [days]
# Default: remove entries older than 30 days
cache_clean() {
  local days="${1:-30}"
  
  if [[ ! -d "$CACHE_DIR" ]]; then
    return 0
  fi
  
  local count=0
  while IFS= read -r entry; do
    rm -rf "$entry"
    ((count++))
  done < <(find "$CACHE_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$days")
  
  echo "doc-lint: cleaned $count cache entries older than $days days"
}
