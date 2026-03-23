#!/usr/bin/env bash
# Integration tests for hooks/pre-tool-use.sh
# Tests that the hook blocks mutations in main repo and allows in worktrees.

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

HOOK="${PLUGIN_ROOT}/hooks/pre-tool-use.sh"

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

# --- Test 1: Write tool in main repo → exit 2 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-1\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 2 "$result" "Write in main repo should exit 2"

# --- Test 2: Stderr should mention EnterWorktree ---
stderr_output="$(run_hook_stderr "{\"session_id\":\"${SESSION}-2\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${REPO_DIR}\"}")"
if echo "$stderr_output" | grep -q "EnterWorktree"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: stderr should mention EnterWorktree" >&2
fi

# --- Test 3: Edit tool in main repo → exit 2 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-3\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 2 "$result" "Edit in main repo should exit 2"

# --- Test 4: Write tool in a worktree → exit 0 ---
WORKTREE_DIR="${TEMP_DIR}/test-worktree"
git worktree add "$WORKTREE_DIR" -b test-branch &>/dev/null
result="$(run_hook "{\"session_id\":\"${SESSION}-4\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Write in worktree should exit 0"

# --- Test 5: Bash read-only command in main repo → exit 0 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-5\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Bash read-only (ls) should exit 0"

# --- Test 6: Bash non-redirect command in main repo → exit 0 (no longer blocked) ---
result="$(run_hook "{\"session_id\":\"${SESSION}-6\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"touch newfile.txt\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Bash touch (no redirect) should exit 0"

# --- Test 7: Bash mutating in worktree → exit 0 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-7\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"touch newfile.txt\"},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 0 "$result" "Bash mutating in worktree should exit 0"

# --- Test 8: Non-git directory → exit 0 ---
NON_GIT_DIR="$(mktemp -d)"
result="$(run_hook "{\"session_id\":\"${SESSION}-8\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${NON_GIT_DIR}\"}")"
assert_exit_code 0 "$result" "Write in non-git dir should exit 0"
rmdir "$NON_GIT_DIR"

# --- Test 9: Empty/invalid JSON → exit 0 (fail open) ---
result="$(run_hook "{}")"
assert_exit_code 0 "$result" "Empty JSON should exit 0 (fail open)"

# --- Test 10: Write to file outside the repo → exit 0 ---
OUTSIDE_DIR="$(mktemp -d)"
result="$(run_hook "{\"session_id\":\"${SESSION}-10\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${OUTSIDE_DIR}/memory.md\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Write to file outside repo should exit 0"
rmdir "$OUTSIDE_DIR"

# --- Test 11: Edit a gitignored file → exit 0 ---
echo "ignored-file.txt" > "${REPO_DIR}/.gitignore"
git -C "$REPO_DIR" add .gitignore &>/dev/null
git -C "$REPO_DIR" commit -m "add gitignore" &>/dev/null
result="$(run_hook "{\"session_id\":\"${SESSION}-11\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"${REPO_DIR}/ignored-file.txt\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Edit gitignored file should exit 0"

# --- Test 12: Write to a non-ignored file in repo → exit 2 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-12\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${REPO_DIR}/src/main.py\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 2 "$result" "Write to non-ignored file in repo should exit 2"

# --- Test 13: Write to .claude/ when gitignored → exit 0 ---
echo ".claude/" >> "${REPO_DIR}/.gitignore"
git -C "$REPO_DIR" add .gitignore &>/dev/null
git -C "$REPO_DIR" commit -m "ignore .claude" &>/dev/null
mkdir -p "${REPO_DIR}/.claude"
result="$(run_hook "{\"session_id\":\"${SESSION}-13\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${REPO_DIR}/.claude/plan.md\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Write to gitignored .claude/ dir should exit 0"

# --- Test 14: Bash non-redirect command no longer blocked ---
result="$(run_hook "{\"session_id\":\"${SESSION}-14\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf src/\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Bash rm (no redirect) should exit 0"

# --- Test 17: Bash redirect to tracked file in main repo → exit 2 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-17\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello > src/main.py\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 2 "$result" "Bash redirect to tracked file should exit 2"

# --- Test 18: Bash redirect to /tmp in main repo → exit 0 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-18\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello > /tmp/test.txt\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Bash redirect to /tmp should exit 0"

# --- Test 19: Bash git checkout in main repo → exit 0 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-19\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git checkout -b new-branch\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Bash git checkout should exit 0"

# --- Test 20: Bash npm install in main repo → exit 0 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-20\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm install express\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Bash npm install should exit 0"

# --- Test 21: Bash redirect to gitignored file → exit 0 ---
result="$(run_hook "{\"session_id\":\"${SESSION}-21\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo data > ignored-file.txt\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Bash redirect to gitignored file should exit 0"

# --- Test 22: Write on non-default branch → exit 0 (allow) ---
FEATURE_BRANCH="feature-test-$$"
git -C "$REPO_DIR" checkout -b "$FEATURE_BRANCH" &>/dev/null
result="$(run_hook "{\"session_id\":\"${SESSION}-22\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${REPO_DIR}/src/main.py\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Write on non-default branch should exit 0"

# --- Test 23: Edit on non-default branch → exit 0 (allow) ---
result="$(run_hook "{\"session_id\":\"${SESSION}-23\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"test.txt\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Edit on non-default branch should exit 0"

# --- Test 24: Bash redirect on non-default branch → exit 0 (allow) ---
result="$(run_hook "{\"session_id\":\"${SESSION}-24\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello > src/main.py\"},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "Bash redirect on non-default branch should exit 0"

# Switch back to main for remaining tests
git -C "$REPO_DIR" checkout main &>/dev/null

# --- Test 15: EnterWorktree in worktree → exit 2 (block) ---
result="$(run_hook "{\"session_id\":\"${SESSION}-15\",\"tool_name\":\"EnterWorktree\",\"tool_input\":{},\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_exit_code 2 "$result" "EnterWorktree in worktree should exit 2"

# --- Test 16: EnterWorktree in main repo → exit 0 (allow) ---
result="$(run_hook "{\"session_id\":\"${SESSION}-16\",\"tool_name\":\"EnterWorktree\",\"tool_input\":{},\"cwd\":\"${REPO_DIR}\"}")"
assert_exit_code 0 "$result" "EnterWorktree in main repo should exit 0"

# --- Cleanup ---
git -C "$REPO_DIR" worktree remove "$WORKTREE_DIR" 2>/dev/null || true

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
