#!/usr/bin/env bash
# Integration tests for hooks/session-start.sh
# Tests that the hook outputs proactive instructions on the default branch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Create a temporary git repo for testing
TEMP_DIR="$(mktemp -d)"
trap 'cd /; rm -rf "$TEMP_DIR"' EXIT

# Create a bare remote so that the test repo has a remote configured
REMOTE_DIR="${TEMP_DIR}/remote.git"
git init --bare -b main "$REMOTE_DIR" &>/dev/null

REPO_DIR="${TEMP_DIR}/test-repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"
git init -b main &>/dev/null
git config commit.gpgsign false
git commit --allow-empty -m "initial commit" &>/dev/null
git remote add origin "$REMOTE_DIR" &>/dev/null

HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

PASS=0
FAIL=0

assert_output() {
  local expected_pattern="$1"
  local actual="$2"
  local desc="$3"
  if echo "$actual" | grep -q "$expected_pattern"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected pattern '${expected_pattern}' not found in output" >&2
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

run_hook() {
  local json="$1"
  echo "$json" | bash "$HOOK" 2>/dev/null || true
}

# --- Test 1: On default branch in main repo → should output instruction ---
output="$(run_hook "{\"cwd\":\"${REPO_DIR}\"}")"
assert_output "EnterWorktree" "$output" "On default branch should mention EnterWorktree"

# --- Test 2: Output should mention auto-worktree ---
assert_output "auto-worktree" "$output" "Output should mention auto-worktree"

# --- Test 3: In a worktree → no output ---
WORKTREE_DIR="${TEMP_DIR}/test-worktree"
git worktree add "$WORKTREE_DIR" -b test-branch &>/dev/null
output="$(run_hook "{\"cwd\":\"${WORKTREE_DIR}\"}")"
assert_empty "$output" "In worktree should produce no output"

# --- Test 4: On non-default branch (no tracked changes) → auto-switch + instruction ---
git -C "$REPO_DIR" checkout -b feature-branch &>/dev/null
output="$(run_hook "{\"cwd\":\"${REPO_DIR}\"}")"
assert_output "Switched from 'feature-branch' to 'main'" "$output" "On non-default branch should auto-switch and report"
assert_output "EnterWorktree" "$output" "After auto-switch should still output EnterWorktree instruction"
# Hook already switched back to main; explicit checkout is a no-op but kept for clarity
git -C "$REPO_DIR" checkout main &>/dev/null

# --- Test 4b: Non-default + tracked changes → warning, no switch, but local default fast-forwarded ---
# Set up origin so it has a commit ahead of REPO_DIR's local main, then verify
# the hook advances local main via background fetch without changing the working branch.
git -C "$REPO_DIR" push -u origin main &>/dev/null

AHEAD_CLONE="${TEMP_DIR}/ahead-clone"
git clone "$REMOTE_DIR" "$AHEAD_CLONE" &>/dev/null
git -C "$AHEAD_CLONE" config commit.gpgsign false
git -C "$AHEAD_CLONE" config user.email "test@example.com"
git -C "$AHEAD_CLONE" config user.name "Test"
git -C "$AHEAD_CLONE" commit --allow-empty -m "remote progress" &>/dev/null
git -C "$AHEAD_CLONE" push origin main &>/dev/null

local_main_before="$(git -C "$REPO_DIR" rev-parse main)"
remote_main_tip="$(git -C "$AHEAD_CLONE" rev-parse main)"

git -C "$REPO_DIR" checkout -b branch-with-changes &>/dev/null
echo "change" >> "${REPO_DIR}/file.txt"
git -C "$REPO_DIR" add file.txt &>/dev/null
output="$(run_hook "{\"cwd\":\"${REPO_DIR}\"}")"
assert_output "unsaved work" "$output" "Non-default + dirty should warn about unsaved work"
assert_output "Updated local 'main' to origin/main" "$output" "Non-default + dirty should report background fast-forward"

local_main_after="$(git -C "$REPO_DIR" rev-parse main)"
if [[ "$local_main_after" == "$remote_main_tip" && "$local_main_after" != "$local_main_before" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: local main should have advanced from ${local_main_before} to ${remote_main_tip}, got ${local_main_after}" >&2
fi

current="$(git -C "$REPO_DIR" branch --show-current)"
if [[ "$current" == "branch-with-changes" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: Branch should not have switched when tracked changes exist, but is now on '${current}'" >&2
fi
git -C "$REPO_DIR" reset HEAD file.txt &>/dev/null
rm -f "${REPO_DIR}/file.txt"
git -C "$REPO_DIR" checkout main &>/dev/null
git -C "$REPO_DIR" branch -D branch-with-changes &>/dev/null

# --- Test 4c: auto_return_to_default=false + non-default branch → no output ---
git -C "$REPO_DIR" checkout -b another-branch &>/dev/null
output="$(CLAUDE_PLUGIN_OPTION_AUTO_RETURN_TO_DEFAULT=false run_hook "{\"cwd\":\"${REPO_DIR}\"}")"
assert_empty "$output" "auto_return_to_default=false should produce no output on non-default branch"
git -C "$REPO_DIR" checkout main &>/dev/null
git -C "$REPO_DIR" branch -D another-branch &>/dev/null

# --- Test 4d: Default branch with untracked file → note about previous session ---
touch "${REPO_DIR}/untracked.txt"
output="$(run_hook "{\"cwd\":\"${REPO_DIR}\"}")"
assert_output "previous session" "$output" "Default branch with untracked files should note previous session state"
rm -f "${REPO_DIR}/untracked.txt"

# --- Test 4e: pull_default_branch=false + non-default + dirty → warn but skip background fetch ---
git -C "$AHEAD_CLONE" commit --allow-empty -m "remote progress 2" &>/dev/null
git -C "$AHEAD_CLONE" push origin main &>/dev/null

local_main_before="$(git -C "$REPO_DIR" rev-parse main)"
git -C "$REPO_DIR" checkout -b dirty-no-pull &>/dev/null
echo "x" >> "${REPO_DIR}/file2.txt"
git -C "$REPO_DIR" add file2.txt &>/dev/null
output="$(CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH=false run_hook "{\"cwd\":\"${REPO_DIR}\"}")"
assert_output "unsaved work" "$output" "Warning still printed when pull disabled"
local_main_after="$(git -C "$REPO_DIR" rev-parse main)"
if [[ "$local_main_after" == "$local_main_before" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: local main should NOT advance when pull_default_branch=false, but moved from ${local_main_before} to ${local_main_after}" >&2
fi
git -C "$REPO_DIR" reset HEAD file2.txt &>/dev/null
rm -f "${REPO_DIR}/file2.txt"
git -C "$REPO_DIR" checkout main &>/dev/null
git -C "$REPO_DIR" branch -D dirty-no-pull &>/dev/null

# --- Test 4g: auto_return_to_default=false + remote ahead → still fetches and advances local default ---
git -C "$AHEAD_CLONE" commit --allow-empty -m "remote progress 3" &>/dev/null
git -C "$AHEAD_CLONE" push origin main &>/dev/null

local_main_before="$(git -C "$REPO_DIR" rev-parse main)"
remote_main_tip="$(git -C "$AHEAD_CLONE" rev-parse main)"

git -C "$REPO_DIR" checkout -b auto-disabled-branch &>/dev/null
output="$(CLAUDE_PLUGIN_OPTION_AUTO_RETURN_TO_DEFAULT=false run_hook "{\"cwd\":\"${REPO_DIR}\"}")"
assert_output "Updated local 'main' to origin/main" "$output" "auto_return=false should still fetch and advance local default"

local_main_after="$(git -C "$REPO_DIR" rev-parse main)"
if [[ "$local_main_after" == "$remote_main_tip" && "$local_main_after" != "$local_main_before" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: local main should have advanced from ${local_main_before} to ${remote_main_tip} even when auto-return is disabled, got ${local_main_after}" >&2
fi

current="$(git -C "$REPO_DIR" branch --show-current)"
if [[ "$current" == "auto-disabled-branch" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: Branch should not have switched when auto-return is disabled, but is now on '${current}'" >&2
fi

# When auto-return is disabled there should be no "unsaved work" warning either
if echo "$output" | grep -q "unsaved work"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: auto-return=false should not print the 'unsaved work' warning" >&2
else
  PASS=$((PASS + 1))
fi

git -C "$REPO_DIR" checkout main &>/dev/null
git -C "$REPO_DIR" branch -D auto-disabled-branch &>/dev/null

# --- Test 4f: Repo with no detectable default branch → no output ---
NO_DEFAULT_REMOTE="${TEMP_DIR}/no-default-remote.git"
NO_DEFAULT_DIR="${TEMP_DIR}/no-default-repo"
git init --bare -b develop "$NO_DEFAULT_REMOTE" &>/dev/null
git init -b develop "$NO_DEFAULT_DIR" &>/dev/null
git -C "$NO_DEFAULT_DIR" config commit.gpgsign false
git -C "$NO_DEFAULT_DIR" config user.email "test@example.com"
git -C "$NO_DEFAULT_DIR" config user.name "Test"
git -C "$NO_DEFAULT_DIR" commit --allow-empty -m "init" &>/dev/null
git -C "$NO_DEFAULT_DIR" remote add origin "$NO_DEFAULT_REMOTE" &>/dev/null
output="$(run_hook "{\"cwd\":\"${NO_DEFAULT_DIR}\"}")"
assert_empty "$output" "Repo with no detectable default branch should produce no output"

# --- Test 5: Non-git directory → no output ---
NON_GIT_DIR="$(mktemp -d)"
output="$(run_hook "{\"cwd\":\"${NON_GIT_DIR}\"}")"
assert_empty "$output" "Non-git directory should produce no output"
rmdir "$NON_GIT_DIR"

# --- Test 6: Empty JSON → no output (fail open) ---
output="$(run_hook "{}")"
assert_empty "$output" "Empty JSON should produce no output"

# --- Test 7: Exit code is always 0 ---
exit_code=0
echo "{\"cwd\":\"${REPO_DIR}\"}" | bash "$HOOK" 2>/dev/null || exit_code=$?
if [[ "$exit_code" -eq 0 ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: Exit code should always be 0, got ${exit_code}" >&2
fi

# --- Test 8: No remote configured → no output ---
NO_REMOTE_DIR="${TEMP_DIR}/no-remote-repo"
mkdir -p "$NO_REMOTE_DIR"
git -C "$NO_REMOTE_DIR" init -b main &>/dev/null
git -C "$NO_REMOTE_DIR" config commit.gpgsign false
git -C "$NO_REMOTE_DIR" commit --allow-empty -m "init" &>/dev/null
output="$(run_hook "{\"cwd\":\"${NO_REMOTE_DIR}\"}")"
assert_empty "$output" "No remote configured should produce no output"

# --- Cleanup ---
git -C "$REPO_DIR" worktree remove "$WORKTREE_DIR" 2>/dev/null || true

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
