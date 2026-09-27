#!/usr/bin/env bash
# =============================================================================
# doc-lint test harness
# =============================================================================
# Runs lint.sh against test fixtures and verifies expected outcomes.
# Exit codes: 0 = all tests pass, 1 = at least one test failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
IMAGE_NAME="doc-lint:test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

# ---- Helper functions -------------------------------------------------------
log_info() {
  echo -e "${YELLOW}[INFO]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((PASS_COUNT++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((FAIL_COUNT++))
}

# ---- Build test image -------------------------------------------------------
build_image() {
  log_info "Building test image: $IMAGE_NAME"
  if ! docker build --no-cache -t "$IMAGE_NAME" "$SCRIPT_DIR/.." >/dev/null 2>&1; then
    log_fail "Failed to build test image"
    exit 1
  fi
  log_pass "Image built successfully"
}

# ---- Test: Valid markdown should pass --------------------------------------
test_valid_markdown() {
  log_info "Testing valid markdown..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" valid.md >/dev/null 2>&1; then
    log_pass "valid.md passes lint"
  else
    log_fail "valid.md should pass but failed"
  fi
}

# ---- Test: Invalid markdown should fail ------------------------------------
test_invalid_markdown() {
  log_info "Testing invalid markdown..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" invalid.md >/dev/null 2>&1; then
    log_fail "invalid.md should fail but passed"
  else
    log_pass "invalid.md fails lint as expected"
  fi
}

# ---- Test: Valid Mermaid should pass ---------------------------------------
test_valid_mermaid() {
  log_info "Testing valid Mermaid diagram..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" valid.mmd >/dev/null 2>&1; then
    log_pass "valid.mmd passes lint"
  else
    log_fail "valid.mmd should pass but failed"
  fi
}

# ---- Test: Invalid Mermaid should fail -------------------------------------
test_invalid_mermaid() {
  log_info "Testing invalid Mermaid diagram..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" invalid.mmd >/dev/null 2>&1; then
    log_fail "invalid.mmd should fail but passed"
  else
    log_pass "invalid.mmd fails lint as expected"
  fi
}

# ---- Test: Valid JSON should pass ------------------------------------------
test_valid_json() {
  log_info "Testing valid JSON..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" valid.json >/dev/null 2>&1; then
    log_pass "valid.json passes lint"
  else
    log_fail "valid.json should pass but failed"
  fi
}

# ---- Test: Invalid JSON should fail ----------------------------------------
test_invalid_json() {
  log_info "Testing invalid JSON..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" invalid.json >/dev/null 2>&1; then
    log_fail "invalid.json should fail but passed"
  else
    log_pass "invalid.json fails lint as expected"
  fi
}

# ---- Test: Valid XML should pass -------------------------------------------
test_valid_xml() {
  log_info "Testing valid XML..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" valid.xml >/dev/null 2>&1; then
    log_pass "valid.xml passes lint"
  else
    log_fail "valid.xml should pass but failed"
  fi
}

# ---- Test: Invalid XML should fail -----------------------------------------
test_invalid_xml() {
  log_info "Testing invalid XML..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" invalid.xml >/dev/null 2>&1; then
    log_fail "invalid.xml should fail but passed"
  else
    log_pass "invalid.xml fails lint as expected"
  fi
}

# ---- Test: Valid YAML should pass ------------------------------------------
test_valid_yaml() {
  log_info "Testing valid YAML..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" valid.yaml >/dev/null 2>&1; then
    log_pass "valid.yaml passes lint"
  else
    log_fail "valid.yaml should pass but failed"
  fi
}

# ---- Test: Invalid YAML should fail ----------------------------------------
test_invalid_yaml() {
  log_info "Testing invalid YAML..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" invalid.yaml >/dev/null 2>&1; then
    log_fail "invalid.yaml should fail but passed"
  else
    log_pass "invalid.yaml fails lint as expected"
  fi
}

# ---- Test: Valid TOML should pass ------------------------------------------
test_valid_toml() {
  log_info "Testing valid TOML..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" valid.toml >/dev/null 2>&1; then
    log_pass "valid.toml passes lint"
  else
    log_fail "valid.toml should pass but failed"
  fi
}

# ---- Test: Invalid TOML should fail ----------------------------------------
test_invalid_toml() {
  log_info "Testing invalid TOML..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" invalid.toml >/dev/null 2>&1; then
    log_fail "invalid.toml should fail but passed"
  else
    log_pass "invalid.toml fails lint as expected"
  fi
}

# ---- Test: JSON schema validation ------------------------------------------
test_json_schema_valid() {
  log_info "Testing JSON schema validation (valid)..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" --schema schema.json valid.json >/dev/null 2>&1; then
    log_pass "valid.json passes schema validation"
  else
    log_fail "valid.json should pass schema validation but failed"
  fi
}

# ---- Test: Multiple files --------------------------------------------------
test_multiple_files() {
  log_info "Testing multiple files..."
  if docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" valid.md valid.json valid.xml >/dev/null 2>&1; then
    log_pass "Multiple valid files pass lint"
  else
    log_fail "Multiple valid files should pass but failed"
  fi
}

# ---- Test: Directory scanning ----------------------------------------------
test_directory_scan() {
  log_info "Testing directory scanning..."
  # Create a temp directory with only valid files
  local temp_dir
  temp_dir=$(mktemp -d)
  chmod 755 "$temp_dir"  # Allow container's non-root user to access
  cp "$FIXTURES_DIR/valid.md" "$temp_dir/"
  cp "$FIXTURES_DIR/valid.json" "$temp_dir/"
  
  if docker run --rm -v "$temp_dir:/work" -w /work "$IMAGE_NAME" . >/dev/null 2>&1; then
    log_pass "Directory scanning works for valid files"
  else
    log_fail "Directory scanning should pass for valid files"
  fi
  
  rm -rf "$temp_dir"
}

# ---- Test: No targets should fail ------------------------------------------
test_no_targets() {
  log_info "Testing no targets (should fail with exit 2)..."
  local exit_code
  # Override CMD to prevent --help from running
  docker run --rm --entrypoint /opt/lint/bin/lint -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" >/dev/null 2>&1
  exit_code=$?
  if [[ $exit_code -eq 2 ]]; then
    log_pass "No targets exits with code 2"
  else
    log_fail "No targets should exit with code 2, got $exit_code"
  fi
}

# ---- Test: Auto-fix mode ---------------------------------------------------
test_fix_mode() {
  log_info "Testing auto-fix mode..."
  
  # Create a temporary directory for fix tests
  local temp_dir
  temp_dir=$(mktemp -d)
  chmod 777 "$temp_dir"  # Allow container's non-root user to write
  
  # Copy fixable files and make them writable
  cp "$FIXTURES_DIR/fixable.md" "$temp_dir/"
  cp "$FIXTURES_DIR/fixable.json" "$temp_dir/"
  chmod 666 "$temp_dir/fixable.md" "$temp_dir/fixable.json"
  
  # Run with --fix flag
  if docker run --rm -v "$temp_dir:/work" -w /work "$IMAGE_NAME" --fix . >/dev/null 2>&1; then
    # Check if backup files were created
    if [[ -f "$temp_dir/fixable.md.bak" && -f "$temp_dir/fixable.json.bak" ]]; then
      log_pass "Auto-fix mode creates backup files"
    else
      log_fail "Auto-fix mode should create backup files"
    fi
    
    # Check if files were actually fixed (should pass lint now)
    if docker run --rm -v "$temp_dir:/work" -w /work "$IMAGE_NAME" fixable.md fixable.json >/dev/null 2>&1; then
      log_pass "Auto-fix mode fixes violations"
    else
      log_fail "Auto-fix mode should fix violations"
    fi
  else
    log_fail "Auto-fix mode should complete successfully"
  fi
  
  rm -rf "$temp_dir"
}

# ---- Test: Auto-fix with --no-backup ---------------------------------------
test_fix_mode_no_backup() {
  log_info "Testing auto-fix mode with --no-backup..."
  
  # Create a temporary directory for fix tests
  local temp_dir
  temp_dir=$(mktemp -d)
  chmod 777 "$temp_dir"  # Allow container's non-root user to write
  
  # Copy fixable files and make them writable
  cp "$FIXTURES_DIR/fixable.md" "$temp_dir/"
  chmod 666 "$temp_dir/fixable.md"
  
  # Run with --fix --no-backup flags
  if docker run --rm -v "$temp_dir:/work" -w /work "$IMAGE_NAME" --fix --no-backup . >/dev/null 2>&1; then
    # Check that backup files were NOT created
    if [[ ! -f "$temp_dir/fixable.md.bak" ]]; then
      log_pass "Auto-fix with --no-backup does not create backups"
    else
      log_fail "Auto-fix with --no-backup should not create backup files"
    fi
  else
    log_fail "Auto-fix with --no-backup should complete successfully"
  fi
  
  rm -rf "$temp_dir"
}

# ---- Test: JUnit XML escaping ------------------------------------------------
test_junit_escaping() {
  log_info "Testing JUnit XML escaping..."
  
  # Create a temp file with crafted payload containing XML metacharacters.
  # Format: file:line:col:rule:severity:message (message may contain colons)
  local tmpfile
  tmpfile=$(mktemp)
  chmod 644 "$tmpfile"
  printf 'path&file<>"a.md:5:1:MD001:error:"Test <script>&alert"\n' > "$tmpfile"
  
  # Mount the file into the container and run the formatter
  local xml_output
  xml_output=$(docker run --rm -v "$tmpfile:/tmp/junit_input.txt:ro" --entrypoint sh "$IMAGE_NAME" -c "node /opt/lint/formatters/junit.sh < /tmp/junit_input.txt")
  
  rm -f "$tmpfile"
  
  # Check that special characters are properly escaped (not raw)
  if echo "$xml_output" | grep -q '&' && ! echo "$xml_output" | grep -q 'name="path&file' ; then
    log_pass "JUnit XML escaping produces well-formed XML"
  else
    log_fail "JUnit XML output has unescaped special characters (possible injection)"
    echo "  DEBUG: formatter output:" >&2
    echo "$xml_output" >&2
  fi
}

# ---- Main -------------------------------------------------------------------
main() {
  echo "=============================================="
  echo "doc-lint Test Suite"
  echo "=============================================="
  echo ""
  
  build_image
  
  echo ""
  echo "Running tests..."
  echo "----------------------------------------------"
  
  test_valid_markdown
  test_invalid_markdown
  test_valid_mermaid
  test_invalid_mermaid
  test_valid_json
  test_invalid_json
  test_valid_xml
  test_invalid_xml
  test_valid_yaml
  test_invalid_yaml
  test_valid_toml
  test_invalid_toml
  test_json_schema_valid
  test_multiple_files
  test_directory_scan
  test_no_targets
  test_fix_mode
  test_fix_mode_no_backup
  test_junit_escaping
  
  echo ""
  echo "=============================================="
  echo "Test Summary"
  echo "=============================================="
  echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
  echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
  echo ""
  
  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
  fi
}

main "$@"
