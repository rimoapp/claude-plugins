#!/usr/bin/env bash
# Tests for lib/bash-filter.sh — mutation detection heuristic.
# After the minimal-blocking change, only output redirects to tracked repo files
# are considered mutating. All other commands are allowed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/worktree.sh"
source "${PLUGIN_ROOT}/lib/bash-filter.sh"

# Create a temporary git repo for path-aware redirect tests
TEMP_DIR="$(mktemp -d)"
trap 'cd /; rm -rf "$TEMP_DIR"' EXIT

REPO_DIR="${TEMP_DIR}/test-repo"
mkdir -p "$REPO_DIR/src"
cd "$REPO_DIR"
git init -b main &>/dev/null
git config commit.gpgsign false
echo "tracked" > "$REPO_DIR/src/main.py"
echo "ignored.txt" > "$REPO_DIR/.gitignore"
git add . &>/dev/null
git commit -m "initial" &>/dev/null

PASS=0
FAIL=0

assert_mutating() {
  local cmd="$1"
  local cwd="${2:-$REPO_DIR}"
  local desc="${3:-$cmd}"
  if is_mutating_command "$cmd" "$cwd"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: Expected mutating: ${desc}" >&2
  fi
}

assert_readonly() {
  local cmd="$1"
  local cwd="${2:-$REPO_DIR}"
  local desc="${3:-$cmd}"
  if ! is_mutating_command "$cmd" "$cwd"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: Expected read-only: ${desc}" >&2
  fi
}

# === Redirect to tracked repo files (mutating) ===
assert_mutating 'echo "hello" > file.txt' "$REPO_DIR" "redirect to tracked file"
assert_mutating 'echo "hello" >> file.txt' "$REPO_DIR" "append to tracked file"
assert_mutating 'echo "data" > src/main.py' "$REPO_DIR" "redirect to tracked src file"

# === Redirect to safe targets (read-only) ===
assert_readonly 'echo "test" > /tmp/test.txt' "$REPO_DIR" "redirect to /tmp"
assert_readonly 'echo "test" > /var/tmp/test.txt' "$REPO_DIR" "redirect to /var/tmp"
assert_readonly 'echo "test" > /dev/null' "$REPO_DIR" "redirect to /dev/null"
assert_readonly 'echo "test" > ignored.txt' "$REPO_DIR" "redirect to gitignored file"
assert_readonly 'command 2>&1' "$REPO_DIR" "stderr redirect only"

# === Commands previously blocked, now allowed ===
assert_readonly 'tee output.txt' "$REPO_DIR" "tee command"
assert_readonly 'sed -i "s/foo/bar/" file.txt' "$REPO_DIR" "sed in-place"
assert_readonly 'perl -i -pe "s/foo/bar/" file.txt' "$REPO_DIR" "perl in-place"
assert_readonly 'mv old.txt new.txt' "$REPO_DIR" "mv command"
assert_readonly 'cp src.txt dst.txt' "$REPO_DIR" "cp command"
assert_readonly 'rm file.txt' "$REPO_DIR" "rm command"
assert_readonly 'rm -rf /tmp/test' "$REPO_DIR" "rm -rf command"
assert_readonly 'mkdir -p /tmp/newdir' "$REPO_DIR" "mkdir command"
assert_readonly 'touch newfile.txt' "$REPO_DIR" "touch command"
assert_readonly 'chmod +x script.sh' "$REPO_DIR" "chmod command"
assert_readonly 'chown user:group file.txt' "$REPO_DIR" "chown command"
assert_readonly 'ln -s /src /dst' "$REPO_DIR" "ln symlink"
assert_readonly 'patch -p1 < diff.patch' "$REPO_DIR" "patch command"
assert_readonly 'truncate -s 0 file.txt' "$REPO_DIR" "truncate command"

# === Git commands (all allowed) ===
assert_readonly 'git checkout feature-branch' "$REPO_DIR" "git checkout"
assert_readonly 'git reset --hard HEAD~1' "$REPO_DIR" "git reset"
assert_readonly 'git merge main' "$REPO_DIR" "git merge"
assert_readonly 'git rebase main' "$REPO_DIR" "git rebase"
assert_readonly 'git stash' "$REPO_DIR" "git stash"
assert_readonly 'git status' "$REPO_DIR" "git status"
assert_readonly 'git log --oneline' "$REPO_DIR" "git log"
assert_readonly 'git diff' "$REPO_DIR" "git diff"
assert_readonly 'git add .' "$REPO_DIR" "git add"
assert_readonly 'git commit -m "test"' "$REPO_DIR" "git commit"
assert_readonly 'git push origin main' "$REPO_DIR" "git push"
assert_readonly 'git branch -a' "$REPO_DIR" "git branch list"

# === Package managers (all allowed) ===
assert_readonly 'npm install express' "$REPO_DIR" "npm install"
assert_readonly 'npm i lodash' "$REPO_DIR" "npm i"
assert_readonly 'pip install requests' "$REPO_DIR" "pip install"
assert_readonly 'yarn add react' "$REPO_DIR" "yarn add"
assert_readonly 'brew install jq' "$REPO_DIR" "brew install"
assert_readonly 'cargo install ripgrep' "$REPO_DIR" "cargo install"
assert_readonly 'go install golang.org/x/tools/...' "$REPO_DIR" "go install"

# === Standard read-only commands ===
assert_readonly 'ls -la' "$REPO_DIR" "ls"
assert_readonly 'cat file.txt' "$REPO_DIR" "cat"
assert_readonly 'grep -r "pattern" .' "$REPO_DIR" "grep"
assert_readonly 'echo hello' "$REPO_DIR" "echo without redirect"
assert_readonly 'pwd' "$REPO_DIR" "pwd"
assert_readonly 'whoami' "$REPO_DIR" "whoami"
assert_readonly 'head -10 file.txt' "$REPO_DIR" "head"
assert_readonly 'tail -20 file.txt' "$REPO_DIR" "tail"
assert_readonly 'wc -l file.txt' "$REPO_DIR" "wc"
assert_readonly 'find . -name "*.txt"' "$REPO_DIR" "find"
assert_readonly 'npm list' "$REPO_DIR" "npm list"
assert_readonly 'node -e "console.log(1)"' "$REPO_DIR" "node eval"

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
