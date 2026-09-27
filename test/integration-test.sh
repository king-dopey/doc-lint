#!/usr/bin/env bash
# =============================================================================
# doc-lint Integration Test Suite
# =============================================================================
# Tests all Phase 1 features: output formatters, parallel processing,
# caching, security hardening, and file exclusion patterns.
#
# Usage: ./test/integration-test.sh
# Exit codes: 0 = all tests pass, 1 = at least one test failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
IMAGE_NAME="doc-lint:integration-test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# ---- Helper functions -------------------------------------------------------
log_info() {
  echo -e "${YELLOW}[INFO]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((PASS_COUNT++))
  ((TOTAL_COUNT++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((FAIL_COUNT++))
  ((TOTAL_COUNT++))
}

log_section() {
  echo ""
  echo -e "${BLUE}==============================================${NC}"
  echo -e "${BLUE}$*${NC}"
  echo -e "${BLUE}==============================================${NC}"
}

# ---- Build test image -------------------------------------------------------
build_image() {
  log_info "Building test image: $IMAGE_NAME"
  if ! docker build -t "$IMAGE_NAME" "$PROJECT_DIR" >/dev/null 2>&1; then
    log_fail "Failed to build test image"
    exit 1
  fi
  log_pass "Image built successfully"
}

# ---- Test: Output Formatters ------------------------------------------------
test_output_formatters() {
  log_section "Testing Output Formatters"
  
  # Test text format (default)
  log_info "Testing text format..."
  local output
  output=$(docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" --format text valid.md 2>&1)
  if [[ "$output" == *"ALL PASS"* ]]; then
    log_pass "Text format produces expected output"
  else
    log_fail "Text format output unexpected"
  fi
  
  # Test JSON format
  log_info "Testing JSON format..."
  output=$(docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" --format json invalid.md 2>&1)
  if echo "$output" | jq -e '.files' >/dev/null 2>&1; then
    log_pass "JSON format produces valid JSON"
  else
    log_fail "JSON format output is not valid JSON"
  fi
  
  # Test JUnit format
  log_info "Testing JUnit format..."
  output=$(docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" --format junit invalid.md 2>&1)
  if [[ "$output" == *"<testsuites"* ]]; then
    log_pass "JUnit format produces XML output"
  else
    log_fail "JUnit format output is not valid XML"
  fi
  
  # Test SARIF format
  log_info "Testing SARIF format..."
  output=$(docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" --format sarif invalid.md 2>&1)
  if echo "$output" | jq -e '.runs[0].tool.driver.name' >/dev/null 2>&1; then
    log_pass "SARIF format produces valid SARIF JSON"
  else
    log_fail "SARIF format output is not valid SARIF"
  fi
}

# ---- Test: Parallel Processing ----------------------------------------------
test_parallel_processing() {
  log_section "Testing Parallel Processing"
  
  # Test parallel flag
  log_info "Testing parallel processing..."
  local output
  output=$(docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" --parallel valid.md valid.json valid.xml 2>&1)
  if [[ "$output" == *"ALL PASS"* ]]; then
    log_pass "Parallel processing works correctly"
  else
    log_fail "Parallel processing failed"
  fi
  
  # Test no-parallel flag
  log_info "Testing sequential processing..."
  output=$(docker run --rm -v "$FIXTURES_DIR:/work" -w /work "$IMAGE_NAME" --no-parallel valid.md valid.json valid.xml 2>&1)
  if [[ "$output" == *"ALL PASS"* ]]; then
    log_pass "Sequential processing works correctly"
  else
    log_fail "Sequential processing failed"
  fi
}

# ---- Test: Caching ----------------------------------------------------------
test_caching() {
  log_section "Testing Caching"
  
  # Create a temporary cache directory
  local cache_dir
  cache_dir=$(mktemp -d)
  
  # Test cache flag
  log_info "Testing cache enablement..."
  local output
  output=$(docker run --rm \
    -v "$FIXTURES_DIR:/work" -w /work \
    -v "$cache_dir:/home/linter/.cache/doc-lint" \
    "$IMAGE_NAME" --cache valid.md 2>&1)
  if [[ "$output" == *"ALL PASS"* ]]; then
    log_pass "Cache flag works correctly"
  else
    log_fail "Cache flag failed"
  fi
  
  # Test no-cache flag
  log_info "Testing cache disablement..."
  output=$(docker run --rm \
    -v "$FIXTURES_DIR:/work" -w /work \
    "$IMAGE_NAME" --no-cache valid.md 2>&1)
  if [[ "$output" == *"ALL PASS"* ]]; then
    log_pass "No-cache flag works correctly"
  else
    log_fail "No-cache flag failed"
  fi
  
  # Clean up
  rm -rf "$cache_dir"
}

# ---- Test: File Exclusion ---------------------------------------------------
test_file_exclusion() {
  log_section "Testing File Exclusion"
  
  # Create test files
  local temp_dir
  temp_dir=$(mktemp -d)
  chmod 755 "$temp_dir"
  cp "$FIXTURES_DIR/valid.md" "$temp_dir/test.md"
  cp "$FIXTURES_DIR/valid.md" "$temp_dir/test.draft.md"
  cp "$FIXTURES_DIR/valid.json" "$temp_dir/test.json"
  
  # Test exclude pattern
  log_info "Testing file exclusion..."
  local output
  output=$(docker run --rm \
    -v "$temp_dir:/work" -w /work \
    "$IMAGE_NAME" --exclude '*.draft.md' . 2>&1)
  if [[ "$output" == *"ALL PASS"* ]]; then
    log_pass "File exclusion works correctly"
  else
    log_fail "File exclusion failed"
  fi
  
  # Clean up
  rm -rf "$temp_dir"
}

# ---- Test: Security Hardening -----------------------------------------------
test_security_hardening() {
  log_section "Testing Security Hardening"
  
  # Test with security flags
  log_info "Testing with security flags..."
  local output
  output=$(docker run --rm \
    --network=none \
    --read-only \
    --tmpfs /tmp \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    -v "$FIXTURES_DIR:/work" -w /work \
    "$IMAGE_NAME" valid.md 2>&1)
  if [[ "$output" == *"ALL PASS"* ]]; then
    log_pass "Security flags work correctly"
  else
    log_fail "Security flags failed"
  fi
}

# ---- Test: Combined Features ------------------------------------------------
test_combined_features() {
  log_section "Testing Combined Features"
  
  # Test parallel + format
  log_info "Testing parallel + JSON format..."
  local output
  output=$(docker run --rm \
    -v "$FIXTURES_DIR:/work" -w /work \
    "$IMAGE_NAME" --parallel --format json valid.md valid.json 2>&1)
  if echo "$output" | jq -e '.files' >/dev/null 2>&1; then
    log_pass "Parallel + JSON format works"
  else
    log_fail "Parallel + JSON format failed"
  fi
  
  # Test exclude + parallel
  log_info "Testing exclude + parallel..."
  local temp_dir
  temp_dir=$(mktemp -d)
  chmod 755 "$temp_dir"
  cp "$FIXTURES_DIR/valid.md" "$temp_dir/test.md"
  cp "$FIXTURES_DIR/valid.md" "$temp_dir/test.draft.md"
  
  output=$(docker run --rm \
    -v "$temp_dir:/work" -w /work \
    "$IMAGE_NAME" --parallel --exclude '*.draft.md' . 2>&1)
  if [[ "$output" == *"ALL PASS"* ]]; then
    log_pass "Exclude + parallel works"
  else
    log_fail "Exclude + parallel failed"
  fi
  
  rm -rf "$temp_dir"
}

# ---- Main -------------------------------------------------------------------
main() {
  echo "=============================================="
  echo "doc-lint Integration Test Suite"
  echo "=============================================="
  echo ""
  
  build_image
  
  test_output_formatters
  test_parallel_processing
  test_caching
  test_file_exclusion
  test_security_hardening
  test_combined_features
  
  echo ""
  echo "=============================================="
  echo "Test Summary"
  echo "=============================================="
  echo -e "Total:  $TOTAL_COUNT"
  echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
  echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
  echo ""
  
  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All integration tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some integration tests failed.${NC}"
    exit 1
  fi
}

main "$@"
