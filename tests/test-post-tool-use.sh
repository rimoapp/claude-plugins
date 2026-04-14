#!/usr/bin/env bash
# Integration tests for hooks/post-tool-use.sh
# Tests that gitignored files written in a worktree are synced to the main repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Create a temporary git repo with a worktree for testing
# Use $HOME instead of /tmp for temp directory because the sync logic
# skips /tmp/* paths — on Linux mktemp -d returns /tmp/... which would
# cause Bash redirect sync tests to be silently skipped.
TEMP_DIR="${HOME}/.auto-worktree-test-$$"
mkdir -p "$TEMP_DIR"
trap 'cd /; rm -rf "$TEMP_DIR"' EXIT

MAIN_REPO="${TEMP_DIR}/main-repo"
mkdir -p "$MAIN_REPO"
cd "$MAIN_REPO"
git init -b main &>/dev/null
git config commit.gpgsign false
echo "dist/" > .gitignore
echo "build/" >> .gitignore
git add .gitignore &>/dev/null
git commit -m "initial commit" &>/dev/null

# Create a worktree
WORKTREE_DIR="${MAIN_REPO}/.claude/worktrees/test-wt"
git worktree add -b worktree-test "$WORKTREE_DIR" HEAD &>/dev/null

HOOK="${PLUGIN_ROOT}/hooks/post-tool-use.sh"

PASS=0
FAIL=0

assert_file_exists() {
  local path="$1"
  local desc="$2"
  if [[ -f "$path" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: file not found: ${path}" >&2
  fi
}

assert_file_not_exists() {
  local path="$1"
  local desc="$2"
  if [[ ! -f "$path" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: file should not exist: ${path}" >&2
  fi
}

assert_file_content() {
  local path="$1"
  local expected="$2"
  local desc="$3"
  if [[ -f "$path" ]] && [[ "$(cat "$path")" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected content '${expected}' in ${path}" >&2
  fi
}

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

run_hook() {
  local json="$1"
  local exit_code=0
  echo "$json" | bash "$HOOK" 2>/dev/null || exit_code=$?
  echo $exit_code
}

run_hook_stderr() {
  local json="$1"
  echo "$json" | bash "$HOOK" 2>&1 >/dev/null || true
}

SESSION="test-$(date +%s)-$$"

# Ensure sync is enabled
export CLAUDE_PLUGIN_OPTION_SYNC_GITIGNORED_WRITES="true"

# --- Test 1: Write to gitignored path in worktree → synced to main ---
mkdir -p "${WORKTREE_DIR}/dist"
echo "bundle content" > "${WORKTREE_DIR}/dist/bundle.js"
result="$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${WORKTREE_DIR}/dist/bundle.js\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Write to gitignored path should exit 0"
assert_file_exists "${MAIN_REPO}/dist/bundle.js" "Write: gitignored file should be synced to main repo"
assert_file_content "${MAIN_REPO}/dist/bundle.js" "bundle content" "Write: synced file should have correct content"

# --- Test 2: Write to tracked path in worktree → NOT synced ---
echo "tracked content" > "${WORKTREE_DIR}/tracked.txt"
rm -f "${MAIN_REPO}/tracked.txt" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${WORKTREE_DIR}/tracked.txt\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Write to tracked path should exit 0"
assert_file_not_exists "${MAIN_REPO}/tracked.txt" "Write: tracked file should NOT be synced to main repo"

# --- Test 3: Write to path outside repo → NOT synced ---
OUTSIDE_FILE="${TEMP_DIR}/outside.txt"
echo "outside" > "$OUTSIDE_FILE"
result="$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${OUTSIDE_FILE}\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Write to outside path should exit 0"

# --- Test 4: Edit to gitignored path → synced ---
mkdir -p "${WORKTREE_DIR}/build"
echo "build output" > "${WORKTREE_DIR}/build/index.html"
rm -f "${MAIN_REPO}/build/index.html" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"${WORKTREE_DIR}/build/index.html\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Edit to gitignored path should exit 0"
assert_file_exists "${MAIN_REPO}/build/index.html" "Edit: gitignored file should be synced to main repo"

# --- Test 5: Bash redirect to gitignored path → synced ---
mkdir -p "${WORKTREE_DIR}/dist"
echo "redirect content" > "${WORKTREE_DIR}/dist/output.txt"
rm -f "${MAIN_REPO}/dist/output.txt" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello > ${WORKTREE_DIR}/dist/output.txt\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Bash redirect to gitignored path should exit 0"
assert_file_exists "${MAIN_REPO}/dist/output.txt" "Bash: gitignored redirect target should be synced"

# --- Test 6: Bash redirect to /tmp → NOT synced (no error) ---
result="$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello > /tmp/test-output.txt\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Bash redirect to /tmp should exit 0"

# --- Test 7: Sync disabled via config → NOT synced ---
export CLAUDE_PLUGIN_OPTION_SYNC_GITIGNORED_WRITES="false"
mkdir -p "${WORKTREE_DIR}/dist"
echo "disabled sync" > "${WORKTREE_DIR}/dist/disabled.js"
rm -f "${MAIN_REPO}/dist/disabled.js" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${WORKTREE_DIR}/dist/disabled.js\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Disabled sync should exit 0"
assert_file_not_exists "${MAIN_REPO}/dist/disabled.js" "Disabled: gitignored file should NOT be synced when disabled"
export CLAUDE_PLUGIN_OPTION_SYNC_GITIGNORED_WRITES="true"

# --- Test 8: Not in worktree (main repo) → no sync ---
echo "main content" > "${MAIN_REPO}/dist/main-only.js"
rm -f "${MAIN_REPO}/dist/main-synced.js" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${MAIN_REPO}/dist/main-only.js\"},\"cwd\":\"${MAIN_REPO}\"}")"
assert_exit_code 0 "$result" "Not in worktree should exit 0"

# --- Test 9: Stderr shows sync message ---
mkdir -p "${WORKTREE_DIR}/dist"
echo "stderr test" > "${WORKTREE_DIR}/dist/stderr-test.js"
rm -f "${MAIN_REPO}/dist/stderr-test.js" 2>/dev/null || true
stderr="$(run_hook_stderr "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${WORKTREE_DIR}/dist/stderr-test.js\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
if echo "$stderr" | grep -q "Synced.*gitignored"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: Stderr should contain sync message, got: ${stderr}" >&2
fi

# --- Test 10: Nested gitignored path → synced with correct structure ---
mkdir -p "${WORKTREE_DIR}/dist/assets/img"
echo "logo" > "${WORKTREE_DIR}/dist/assets/img/logo.png"
rm -rf "${MAIN_REPO}/dist/assets" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${WORKTREE_DIR}/dist/assets/img/logo.png\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Nested gitignored path should exit 0"
assert_file_exists "${MAIN_REPO}/dist/assets/img/logo.png" "Nested: intermediate dirs should be created"

# --- Test 11: File doesn't actually exist → no error ---
rm -f "${WORKTREE_DIR}/dist/nonexistent.js" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${WORKTREE_DIR}/dist/nonexistent.js\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Nonexistent file should exit 0 without error"

# --- Test 12: Relative Write path resolved against cwd → synced (P1 fix) ---
mkdir -p "${WORKTREE_DIR}/dist"
echo "relative content" > "${WORKTREE_DIR}/dist/relative.js"
rm -f "${MAIN_REPO}/dist/relative.js" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"dist/relative.js\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Relative Write path should exit 0"
assert_file_exists "${MAIN_REPO}/dist/relative.js" "Relative: file should be synced via cwd resolution"

# --- Test 13: Multiple Bash redirects on one line → all synced (P2 fix) ---
mkdir -p "${WORKTREE_DIR}/dist"
echo "first" > "${WORKTREE_DIR}/dist/first.txt"
echo "second" > "${WORKTREE_DIR}/dist/second.txt"
rm -f "${MAIN_REPO}/dist/first.txt" "${MAIN_REPO}/dist/second.txt" 2>/dev/null || true
result="$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo a > ${WORKTREE_DIR}/dist/first.txt && echo b > ${WORKTREE_DIR}/dist/second.txt\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Multiple redirects should exit 0"
assert_file_exists "${MAIN_REPO}/dist/first.txt" "Multiple redirects: first file should be synced"
assert_file_exists "${MAIN_REPO}/dist/second.txt" "Multiple redirects: second file should be synced"

# Cleanup
unset CLAUDE_PLUGIN_OPTION_SYNC_GITIGNORED_WRITES 2>/dev/null || true

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
