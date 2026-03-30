#!/usr/bin/env bash
# Tests for lib/config.sh — user configuration helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/config.sh"

# Create temporary git repos for testing (is_skipped_directory resolves repo root)
TEMP_DIR="$(mktemp -d)"
trap 'cd /; rm -rf "$TEMP_DIR"' EXIT

REPO_A="${TEMP_DIR}/repo-a"
REPO_B="${TEMP_DIR}/repo-b"
mkdir -p "$REPO_A/subdir" "$REPO_B"
git -C "$REPO_A" init -b main &>/dev/null
git -C "$REPO_A" config commit.gpgsign false
git -C "$REPO_A" commit --allow-empty -m "init" &>/dev/null
git -C "$REPO_B" init -b main &>/dev/null
git -C "$REPO_B" config commit.gpgsign false
git -C "$REPO_B" commit --allow-empty -m "init" &>/dev/null

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
assert_false "Empty env → not skipped" is_skipped_directory "$REPO_A"

# Test 2: Exact repo root match
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="$REPO_A"
assert_true "Exact repo root match should be skipped" is_skipped_directory "$REPO_A"

# Test 3: Subdirectory of skipped repo → skipped (resolves to same repo root)
assert_true "Subdirectory should resolve to repo root and be skipped" is_skipped_directory "$REPO_A/subdir"

# Test 4: Different repo → not skipped
assert_false "Different repo should not be skipped" is_skipped_directory "$REPO_B"

# Test 5: Multiple directories, second matches
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="/nonexistent,$REPO_B"
assert_true "Second entry should match" is_skipped_directory "$REPO_B"

# Test 6: Multiple directories with spaces
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="/nonexistent , $REPO_A"
assert_true "Trimmed entry should match" is_skipped_directory "$REPO_A"

# Test 7: Non-git directory → not skipped (git rev-parse fails)
NON_GIT_DIR="$(mktemp -d)"
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="$NON_GIT_DIR"
assert_false "Non-git directory should not be skipped" is_skipped_directory "$NON_GIT_DIR"
rmdir "$NON_GIT_DIR"

# Test 8: Empty string in skip list
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES=","
assert_false "Empty entries should not match" is_skipped_directory "$REPO_A"

# Test 9: Tilde (~/) expansion
# Create a repo inside $HOME for this test
TILDE_REPO="${HOME}/.auto-worktree-test-$$"
mkdir -p "$TILDE_REPO"
git -C "$TILDE_REPO" init -b main &>/dev/null
git -C "$TILDE_REPO" config commit.gpgsign false
git -C "$TILDE_REPO" commit --allow-empty -m "init" &>/dev/null
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="~/.auto-worktree-test-$$"
assert_true "Tilde path should expand and match" is_skipped_directory "$TILDE_REPO"
rm -rf "$TILDE_REPO"

# --- is_pull_enabled tests ---

# Test 9: Default (unset) → enabled
unset CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH 2>/dev/null || true
assert_true "Default should be enabled" is_pull_enabled

# Test 10: Explicit true
export CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH="true"
assert_true "Explicit true should be enabled" is_pull_enabled

# Test 11: Explicit false
export CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH="false"
assert_false "Explicit false should be disabled" is_pull_enabled

# Test 12: "0" → disabled
export CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH="0"
assert_false "0 should be disabled" is_pull_enabled

# Test 13: "no" → disabled
export CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH="no"
assert_false "no should be disabled" is_pull_enabled

# Test 14: "off" → disabled
export CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH="off"
assert_false "off should be disabled" is_pull_enabled

# Test 15: "FALSE" (case insensitive) → disabled
export CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH="FALSE"
assert_false "FALSE (uppercase) should be disabled" is_pull_enabled

# Test 16: Random string → enabled (truthy)
export CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH="yes"
assert_true "yes should be enabled" is_pull_enabled

# Cleanup
unset CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH 2>/dev/null || true

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
