#!/usr/bin/env bash
# Stop hook for auto-worktree plugin.
# If Claude is in a worktree, prints a summary of branch and uncommitted changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/json.sh"
source "${PLUGIN_ROOT}/lib/worktree.sh"

main() {
  local input
  input="$(cat)"

  # Prevent infinite loops: if stop hook already triggered a continuation, bail out
  local stop_hook_active
  stop_hook_active="$(parse_json_field "$input" '.stop_hook_active')"
  if [[ "$stop_hook_active" == "true" ]]; then
    exit 0
  fi

  local cwd
  cwd="$(parse_json_field "$input" '.cwd')"

  if [[ -z "$cwd" ]]; then
    exit 0
  fi

  # Only show summary if we're in a worktree
  if ! is_inside_worktree "$cwd"; then
    exit 0
  fi

  local worktree_root branch_name
  worktree_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
  branch_name="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0

  echo "" >&2
  echo "=== Auto-Worktree Session Summary ===" >&2
  echo "  Worktree: ${worktree_root}" >&2
  echo "  Branch:   ${branch_name}" >&2

  local status_output
  status_output="$(git -C "$worktree_root" status --porcelain 2>/dev/null)" || true

  if [[ -n "$status_output" ]]; then
    echo "" >&2
    echo "  Uncommitted changes:" >&2
    echo "$status_output" | while IFS= read -r line; do
      echo "    ${line}" >&2
    done
  fi

  echo "======================================" >&2
  exit 0
}

main
