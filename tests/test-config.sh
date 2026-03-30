#!/usr/bin/env bash
# Tests for lib/config.sh — user configuration helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/config.sh"

PASS=0
FAIL=0

assert_true() {
  local desc="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}" >&2
  fi
}

assert_false() {
  local desc="$1"
  shift
  if ! "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}" >&2
  fi
}

# --- is_skipped_directory tests ---

# Test 1: No skip_directories set → not skipped
unset CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES 2>/dev/null || true
assert_false "Empty env → not skipped" is_skipped_directory "/some/dir"

# Test 2: Exact match
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="/Users/test/notes"
assert_true "Exact match should be skipped" is_skipped_directory "/Users/test/notes"

# Test 3: Subdirectory match
assert_true "Subdirectory should be skipped" is_skipped_directory "/Users/test/notes/2024"

# Test 4: Non-matching directory
assert_false "Non-matching dir should not be skipped" is_skipped_directory "/Users/test/code"

# Test 5: Multiple directories, second matches
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="/Users/test/notes,/Users/test/scratch"
assert_true "Second entry should match" is_skipped_directory "/Users/test/scratch"

# Test 6: Multiple directories with spaces
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="/Users/test/notes , /Users/test/scratch"
assert_true "Trimmed entry should match" is_skipped_directory "/Users/test/scratch"

# Test 7: Partial path should not match (prefix but not at directory boundary)
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="/Users/test/not"
assert_false "Partial path should not match" is_skipped_directory "/Users/test/notes"

# Test 8: Empty string in skip list
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES=","
assert_false "Empty entries should not match" is_skipped_directory "/some/dir"

# --- is_fetch_enabled tests ---

# Test 9: Default (unset) → enabled
unset CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH 2>/dev/null || true
assert_true "Default should be enabled" is_fetch_enabled

# Test 10: Explicit true
export CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH="true"
assert_true "Explicit true should be enabled" is_fetch_enabled

# Test 11: Explicit false
export CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH="false"
assert_false "Explicit false should be disabled" is_fetch_enabled

# Test 12: "0" → disabled
export CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH="0"
assert_false "0 should be disabled" is_fetch_enabled

# Test 13: "no" → disabled
export CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH="no"
assert_false "no should be disabled" is_fetch_enabled

# Test 14: "off" → disabled
export CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH="off"
assert_false "off should be disabled" is_fetch_enabled

# Test 15: "FALSE" (case insensitive) → disabled
export CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH="FALSE"
assert_false "FALSE (uppercase) should be disabled" is_fetch_enabled

# Test 16: Random string → enabled (truthy)
export CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH="yes"
assert_true "yes should be enabled" is_fetch_enabled

# Cleanup
unset CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH 2>/dev/null || true

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
