#!/usr/bin/env bash
# PreToolUse hook for auto-worktree plugin.
# Intercepts Write, Edit, and Bash (mutating) tool calls.
# If Claude is working in the main repo (not a worktree), blocks the action
# and instructs Claude to call EnterWorktree first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/worktree.sh"
source "${PLUGIN_ROOT}/lib/bash-filter.sh"

# --- JSON Parsing ---
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

  # 2. Already inside a worktree? → allow (but block EnterWorktree)
  if is_inside_worktree "$cwd"; then
    if [[ "$tool_name" == "EnterWorktree" ]]; then
      echo "You are already inside a worktree. Continue working here — just commit your changes." >&2
      exit 2
    fi
    exit 0
  fi

  # 3. EnterWorktree in main repo? → allow (let Claude create the worktree)
  if [[ "$tool_name" == "EnterWorktree" ]]; then
    exit 0
  fi

  # 4. For Write/Edit, allow if target file is outside the repo or gitignored
  if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" ]]; then
    local file_path
    file_path="$(parse_json_field "$input" '.tool_input.file_path')"
    if [[ -n "$file_path" ]] && is_outside_repo_or_ignored "$cwd" "$file_path"; then
      exit 0
    fi
  fi

  # 5. For Bash tool, only intercept mutating commands
  if [[ "$tool_name" == "Bash" ]]; then
    local bash_command
    bash_command="$(parse_json_field "$input" '.tool_input.command')"
    if [[ -n "$bash_command" ]] && ! is_mutating_command "$bash_command"; then
      exit 0
    fi
  fi

  # 6. Block and instruct Claude to enter a worktree first
  echo "You are about to modify files in the main repository." >&2
  echo "Please call the EnterWorktree tool first to create an isolated worktree, then retry your action." >&2
  exit 2
}

main
