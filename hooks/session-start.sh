#!/usr/bin/env bash
# SessionStart hook for auto-worktree plugin.
# If Claude is on the default branch in the main repo (not a worktree),
# outputs a proactive instruction to stdout so Claude knows to call
# EnterWorktree before modifying any files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/worktree.sh"
source "${PLUGIN_ROOT}/lib/config.sh"

parse_json_field() {
  local json="$1"
  local field="$2"
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r "$field"
  elif command -v python3 &>/dev/null; then
    echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(eval('d' + ''.join('[\"' + k + '\"]' for k in '$field'.strip('.').split('.'))))" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

main() {
  local input
  input="$(cat)"

  local cwd
  cwd="$(parse_json_field "$input" '.cwd')"

  if [[ -z "$cwd" ]]; then
    exit 0
  fi

  # Not a git repo? → no-op
  if ! is_git_repo "$cwd"; then
    exit 0
  fi

  # Skipped directory? → no-op
  if is_skipped_directory "$cwd"; then
    exit 0
  fi

  # Already inside a worktree? → no-op
  if is_inside_worktree "$cwd"; then
    exit 0
  fi

  # Not on the default branch? → no-op (user intentionally on a branch)
  if ! is_on_default_branch "$cwd"; then
    exit 0
  fi

  # Fetch the latest default branch from origin if enabled
  if is_fetch_enabled; then
    git -C "$cwd" fetch origin --quiet 2>/dev/null || true
  fi

  # On the default branch in main repo → instruct Claude proactively
  # stdout output is added as context for Claude
  cat <<'MSG'
[auto-worktree] You are currently on the default branch in the main repository.
IMPORTANT: Before modifying any files, you MUST call the EnterWorktree tool first to create an isolated worktree.
Do NOT attempt to Write, Edit, or run mutating Bash commands before entering a worktree.
MSG

  exit 0
}

main
