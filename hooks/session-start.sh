#!/usr/bin/env bash
# SessionStart hook for auto-worktree plugin.
# If Claude is on the default branch in the main repo (not a worktree),
# outputs a proactive instruction to stdout so Claude knows to call
# EnterWorktree before modifying any files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/json.sh"
source "${PLUGIN_ROOT}/lib/worktree.sh"
source "${PLUGIN_ROOT}/lib/config.sh"
source "${PLUGIN_ROOT}/lib/bypass.sh"

readonly NETWORK_TIMEOUT_SECS=8

# GNU coreutils' `timeout` isn't shipped with stock macOS or Git Bash on Windows.
# Fall back to running without a timeout in that case so the network operations
# still happen — better to occasionally hang briefly than to silently never run.
run_with_timeout() {
  local secs="$1"
  shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
  else
    "$@"
  fi
}

main() {
  local input
  input="$(cat)"

  local session_id cwd
  session_id="$(parse_json_field "$input" '.session_id')"
  cwd="$(parse_json_field "$input" '.cwd')"

  if [[ -z "$cwd" ]]; then
    exit 0
  fi

  # Bypass active for this session? → no-op
  if [[ -n "$session_id" ]] && is_bypass_active "$session_id"; then
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

  # No remote configured? → no-op (local-only repo, no PR workflow)
  if ! has_remote "$cwd"; then
    exit 0
  fi

  # Already inside a worktree? → no-op
  if is_inside_worktree "$cwd"; then
    exit 0
  fi

  # Determine current and default branch once (avoids duplicate git calls)
  local current_branch default_branch
  current_branch="$(git -C "$cwd" branch --show-current 2>/dev/null)"
  default_branch="$(get_default_branch "$cwd" 2>/dev/null)" || default_branch=""

  # Cannot determine default branch (orphan repo, no main/master, no origin/HEAD) → no-op
  if [[ -z "$default_branch" ]]; then
    exit 0
  fi

  # Not on the default branch?
  if [[ "$current_branch" != "$default_branch" ]]; then
    local clean=false
    if git -C "$cwd" diff --quiet 2>/dev/null && git -C "$cwd" diff --cached --quiet 2>/dev/null; then
      clean=true
    fi

    if is_auto_return_enabled && $clean; then
      # Safe to switch back to default branch
      git -C "$cwd" checkout "$default_branch" --quiet 2>/dev/null || {
        echo "[auto-worktree] Warning: failed to switch from '${current_branch}' to '${default_branch}'. Staying on current branch." >&2
        exit 0
      }
      echo "[auto-worktree] Switched from '${current_branch}' to '${default_branch}' automatically."
      # Fall through to pull + EnterWorktree instruction
    else
      # Not switching, either because auto-return is disabled or the working
      # tree is dirty. Still try to advance the local default branch ref so
      # it stays as fresh as possible without disturbing the working tree.
      # The refspec form fast-forwards the local ref directly; non-FF is
      # rejected, and it's safe here because the default branch is not
      # currently checked out. Gated by `pull_default_branch` (same toggle
      # that governs network activity for the on-default-branch path).
      if is_pull_enabled; then
        local default_before default_after
        default_before="$(git -C "$cwd" rev-parse "$default_branch" 2>/dev/null || echo "")"
        if run_with_timeout "$NETWORK_TIMEOUT_SECS" git -C "$cwd" fetch origin "${default_branch}:${default_branch}" --quiet 2>/dev/null; then
          default_after="$(git -C "$cwd" rev-parse "$default_branch" 2>/dev/null || echo "")"
          if [[ -n "$default_before" && -n "$default_after" && "$default_before" != "$default_after" ]]; then
            echo "[auto-worktree] Updated local '${default_branch}' to origin/${default_branch} in the background (no branch switch)."
          fi
        fi
      fi
      # When auto-return is enabled but blocked by a dirty working tree, tell
      # the user why we didn't switch. When auto-return is disabled, stay quiet.
      if is_auto_return_enabled && ! $clean; then
        echo "[auto-worktree] Warning: You have unsaved work on '${current_branch}'. Commit and push before starting a new task, then switch to '${default_branch}'."
      fi
      exit 0
    fi
  fi

  # Pull the latest default branch from origin if enabled
  if is_pull_enabled; then
    if ! run_with_timeout "$NETWORK_TIMEOUT_SECS" git -C "$cwd" pull --ff-only --quiet 2>/dev/null; then
      echo "[auto-worktree] Warning: failed to pull from origin (offline, timeout, or diverged). Continuing with local state." >&2
    fi
  fi

  # Note any leftover working tree state from a previous session
  if [[ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]]; then
    echo "[auto-worktree] Note: There are uncommitted changes or untracked files from a previous session."
  fi

  # On the default branch in main repo → instruct Claude proactively
  # stdout output is added as context for Claude
  local bypass_file
  bypass_file="$(get_bypass_file "$session_id")"

  cat <<MSG
[auto-worktree] You are currently on the default branch in the main repository.
IMPORTANT: Before modifying any files, you MUST call the EnterWorktree tool first to create an isolated worktree.
Do NOT attempt to Write, Edit, or run mutating Bash commands before entering a worktree.
TIP: Skills and files created after EnterWorktree are immediately testable in the worktree — no merge required.
BYPASS: If the user explicitly asks to skip or disable worktree creation (in any language or phrasing), run: touch ${bypass_file}
This disables worktree enforcement for the rest of this session. Only do this when the user clearly requests it.
MSG

  exit 0
}

main
