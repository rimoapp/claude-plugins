#!/usr/bin/env bash
# Integration tests for userConfig options with hooks.
# Tests skip_directories and fetch_default_branch behavior in actual hooks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Create a temporary git repo for testing
TEMP_DIR="$(mktemp -d)"
trap 'cd /; rm -rf "$TEMP_DIR"' EXIT

REPO_DIR="${TEMP_DIR}/test-repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"
git init -b main &>/dev/null
git config commit.gpgsign false
git commit --allow-empty -m "initial commit" &>/dev/null

PASS=0
FAIL=0

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local desc="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected exit ${expected}, got ${actual}" >&2
  fi
}

assert_empty() {
  local actual="$1"
  local desc="$2"
  if [[ -z "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected empty output, got: ${actual}" >&2
  fi
}

assert_output() {
  local pattern="$1"
  local actual="$2"
  local desc="$3"
  if echo "$actual" | grep -q "$pattern"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected pattern '${pattern}' not found" >&2
  fi
}

SESSION="config-test-$$"

# --- skip_directories with session-start.sh ---

# Test 1: Skipped directory → no session-start output
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="${REPO_DIR}"
output="$(echo "{\"cwd\":\"${REPO_DIR}\"}" | bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null || true)"
assert_empty "$output" "session-start: skipped directory should produce no output"

# Test 2: Non-skipped directory → session-start outputs instruction
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="/some/other/dir"
output="$(echo "{\"cwd\":\"${REPO_DIR}\"}" | bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null || true)"
assert_output "EnterWorktree" "$output" "session-start: non-skipped directory should output instruction"

# --- skip_directories with pre-tool-use.sh ---

# Test 3: Skipped directory → Write allowed (exit 0)
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="${REPO_DIR}"
exit_code=0
echo "{\"session_id\":\"${SESSION}-3\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${REPO_DIR}\"}" \
  | bash "${PLUGIN_ROOT}/hooks/pre-tool-use.sh" 2>/dev/null || exit_code=$?
assert_exit_code 0 "$exit_code" "pre-tool-use: Write in skipped directory should exit 0"

# Test 4: Non-skipped directory → Write blocked (exit 2)
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="/some/other/dir"
exit_code=0
echo "{\"session_id\":\"${SESSION}-4\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${REPO_DIR}\"}" \
  | bash "${PLUGIN_ROOT}/hooks/pre-tool-use.sh" 2>/dev/null || exit_code=$?
assert_exit_code 2 "$exit_code" "pre-tool-use: Write in non-skipped directory should exit 2"

# Test 5: Subdirectory of skipped dir → also allowed
mkdir -p "${REPO_DIR}/subdir"
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES="${REPO_DIR}"
exit_code=0
echo "{\"session_id\":\"${SESSION}-5\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${REPO_DIR}/subdir\"}" \
  | bash "${PLUGIN_ROOT}/hooks/pre-tool-use.sh" 2>/dev/null || exit_code=$?
assert_exit_code 0 "$exit_code" "pre-tool-use: Write in subdirectory of skipped dir should exit 0"

# --- fetch_default_branch with session-start.sh ---

# Test 6: fetch disabled → session-start still outputs instruction (just no fetch)
export CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES=""
export CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH="false"
output="$(echo "{\"cwd\":\"${REPO_DIR}\"}" | bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null || true)"
assert_output "EnterWorktree" "$output" "session-start: fetch disabled still outputs instruction"

# Cleanup
unset CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH 2>/dev/null || true

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
