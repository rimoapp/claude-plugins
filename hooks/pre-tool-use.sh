#!/usr/bin/env bash
# PreToolUse hook for auto-worktree plugin.
# Intercepts Write, Edit, and Bash (mutating) tool calls.
# If Claude is working in the main repo (not a worktree), blocks the action
# and instructs Claude to call EnterWorktree first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/json.sh"
source "${PLUGIN_ROOT}/lib/worktree.sh"
source "${PLUGIN_ROOT}/lib/bash-filter.sh"
source "${PLUGIN_ROOT}/lib/config.sh"

# --- Main Logic ---
main() {
  local input
  input="$(cat)"

  local session_id tool_name cwd
  session_id="$(parse_json_field "$input" '.session_id')"
  tool_name="$(parse_json_field "$input" '.tool_name')"
  cwd="$(parse_json_field "$input" '.cwd')"

  # Guard: if we can't parse essential fields, allow
  if [[ -z "$session_id" || -z "$tool_name" || -z "$cwd" ]]; then
    exit 0
  fi

  # 1. Not a git repo? → no-op
  if ! is_git_repo "$cwd"; then
    exit 0
  fi

  # 1.5. Skipped directory? → no-op
  if is_skipped_directory "$cwd"; then
    exit 0
  fi

  # 2. Already inside a worktree? → allow (but block EnterWorktree)
  if is_inside_worktree "$cwd"; then
    if [[ "$tool_name" == "EnterWorktree" ]]; then
      echo "You are already inside a worktree. Continue working here — just commit your changes." >&2
      exit 2
    fi
    exit 0
  fi

  # 3. Not on the default branch? → allow (user intentionally checked out a branch)
  if ! is_on_default_branch "$cwd"; then
    exit 0
  fi

  # 4. EnterWorktree in main repo on default branch? → allow (let Claude create the worktree)
  if [[ "$tool_name" == "EnterWorktree" ]]; then
    exit 0
  fi

  # 5. For Write/Edit, allow if target file is outside the repo or gitignored
  if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" ]]; then
    local file_path
    file_path="$(parse_json_field "$input" '.tool_input.file_path')"
    if [[ -n "$file_path" ]] && is_outside_repo_or_ignored "$cwd" "$file_path"; then
      exit 0
    fi
  fi

  # 6. For Bash tool, only intercept mutating commands
  if [[ "$tool_name" == "Bash" ]]; then
    local bash_command
    bash_command="$(parse_json_field "$input" '.tool_input.command')"
    if [[ -n "$bash_command" ]] && ! is_mutating_command "$bash_command" "$cwd"; then
      exit 0
    fi
  fi

  # 7. Block and instruct Claude to enter a worktree first
  echo "You are about to modify files on the default branch." >&2
  echo "Please call the EnterWorktree tool first to create an isolated worktree, then retry your action." >&2
  exit 2
}

main
