#!/usr/bin/env bash
# Tests for lib/worktree.sh — git worktree detection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/worktree.sh"

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

assert_true() {
  local desc="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected true" >&2
  fi
}

assert_false() {
  local desc="$1"
  shift
  if ! "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected false" >&2
  fi
}

# --- Test is_git_repo ---
assert_true "is_git_repo in repo" is_git_repo "$REPO_DIR"
assert_false "is_git_repo in /tmp" is_git_repo "/tmp"

# --- Test is_inside_worktree (main repo) ---
assert_false "not inside worktree in main repo" is_inside_worktree "$REPO_DIR"

# --- Test is_inside_worktree (in worktree) ---
WT_PATH="${TEMP_DIR}/test-worktree"
git worktree add "$WT_PATH" -b "test-branch" &>/dev/null
assert_true "is_inside_worktree in worktree" is_inside_worktree "$WT_PATH"

# --- Cleanup worktree ---
git -C "$REPO_DIR" worktree remove "$WT_PATH" 2>/dev/null || true

# --- Test is_outside_repo_or_ignored ---

# Outside repo → true
OUTSIDE_DIR="$(mktemp -d)"
assert_true "outside repo is detected" is_outside_repo_or_ignored "$REPO_DIR" "${OUTSIDE_DIR}/file.txt"
rmdir "$OUTSIDE_DIR"

# Inside repo, not ignored → false
assert_false "non-ignored repo file" is_outside_repo_or_ignored "$REPO_DIR" "${REPO_DIR}/src/main.py"

# Gitignored file → true
echo "*.log" > "${REPO_DIR}/.gitignore"
git -C "$REPO_DIR" add .gitignore &>/dev/null
git -C "$REPO_DIR" commit -m "add gitignore" &>/dev/null
touch "${REPO_DIR}/debug.log"
assert_true "gitignored file" is_outside_repo_or_ignored "$REPO_DIR" "${REPO_DIR}/debug.log"

# Non-ignored file in same repo → false
assert_false "non-ignored file in repo" is_outside_repo_or_ignored "$REPO_DIR" "${REPO_DIR}/README.md"

# --- Test is_on_default_branch ---

# On main branch → true
assert_true "on default branch (main)" is_on_default_branch "$REPO_DIR"

# On a feature branch → false
git -C "$REPO_DIR" checkout -b feature-branch &>/dev/null
assert_false "on feature branch" is_on_default_branch "$REPO_DIR"

# Back to main → true
git -C "$REPO_DIR" checkout main &>/dev/null
assert_true "back on main" is_on_default_branch "$REPO_DIR"

# With origin/HEAD set → uses that
REMOTE_REPO="${TEMP_DIR}/remote-repo"
git init -b develop "$REMOTE_REPO" &>/dev/null
git -C "$REMOTE_REPO" config commit.gpgsign false
git -C "$REMOTE_REPO" commit --allow-empty -m "init" &>/dev/null
CLONE_REPO="${TEMP_DIR}/clone-repo"
git clone "$REMOTE_REPO" "$CLONE_REPO" &>/dev/null
assert_true "on default branch (develop via origin/HEAD)" is_on_default_branch "$CLONE_REPO"
git -C "$CLONE_REPO" checkout -b other-branch &>/dev/null
assert_false "on non-default branch in clone" is_on_default_branch "$CLONE_REPO"

echo "${PASS} passed, ${FAIL} failed"
if [[ $FAIL -gt 0 ]]; then exit 1; fi
