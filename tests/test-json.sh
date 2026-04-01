#!/usr/bin/env bash
# Tests for lib/json.sh — shared JSON parsing helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/json.sh"

PASS=0
FAIL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local desc="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected '${expected}', got '${actual}'" >&2
  fi
}

# --- Test 1: Simple field extraction ---
result="$(parse_json_field '{"name":"test"}' '.name')"
assert_eq "test" "$result" "Simple field extraction"

# --- Test 2: Nested field extraction ---
result="$(parse_json_field '{"tool_input":{"file_path":"/tmp/foo.txt"}}' '.tool_input.file_path')"
assert_eq "/tmp/foo.txt" "$result" "Nested field extraction"

# --- Test 3: Missing field returns null ---
result="$(parse_json_field '{"name":"test"}' '.missing')"
assert_eq "null" "$result" "Missing field returns null"

# --- Test 4: Empty JSON object ---
result="$(parse_json_field '{}' '.name')"
assert_eq "null" "$result" "Empty object returns null"

# --- Test 5: Boolean value ---
result="$(parse_json_field '{"active":true}' '.active')"
assert_eq "true" "$result" "Boolean value extraction"

# --- Test 6: Field with spaces in value ---
result="$(parse_json_field '{"msg":"hello world"}' '.msg')"
assert_eq "hello world" "$result" "Value with spaces"

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
