#!/usr/bin/env bash
# Configuration helpers for auto-worktree plugin.
# Reads user config from CLAUDE_PLUGIN_OPTION_* environment variables.

# Check if the given directory should be skipped by auto-worktree.
# Resolves the git repository root and matches against CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES.
# Arguments: $1 = directory path (cwd)
# Returns: 0 if the repository should be skipped, 1 otherwise.
is_skipped_directory() {
  local dir="$1"
  local skip_dirs="${CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES:-}"

  if [[ -z "$skip_dirs" ]]; then
    return 1
  fi

  # Resolve to the git repository root for consistent matching
  local repo_root
  repo_root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
  if command -v realpath &>/dev/null; then
    repo_root="$(realpath "$repo_root" 2>/dev/null)" || true
  fi

  local IFS=','
  for skip_dir in $skip_dirs; do
    # Trim whitespace
    skip_dir="$(echo "$skip_dir" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$skip_dir" ]] && continue

    # Expand ~ to $HOME
    if [[ "$skip_dir" == "~/"* ]]; then
      skip_dir="${HOME}${skip_dir#"~"}"
    elif [[ "$skip_dir" == "~" ]]; then
      skip_dir="$HOME"
    fi

    # Resolve the skip dir too
    local resolved_skip="$skip_dir"
    if command -v realpath &>/dev/null; then
      resolved_skip="$(realpath "$skip_dir" 2>/dev/null)" || resolved_skip="$skip_dir"
    fi

    # Match if the repo root equals the skip dir
    if [[ "$repo_root" == "$resolved_skip" ]]; then
      return 0
    fi
  done

  return 1
}

# Check if pull_default_branch is enabled.
# Reads CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH.
# Returns: 0 if enabled (default), 1 if explicitly disabled.
is_pull_enabled() {
  local val="${CLAUDE_PLUGIN_OPTION_PULL_DEFAULT_BRANCH:-true}"
  # Treat "false", "0", "no", "off" as disabled
  case "${val,,}" in
    false|0|no|off) return 1 ;;
    *) return 0 ;;
  esac
}

# Check if sync_gitignored_writes is enabled.
# Reads CLAUDE_PLUGIN_OPTION_SYNC_GITIGNORED_WRITES.
# Returns: 0 if enabled (default), 1 if explicitly disabled.
is_sync_gitignored_enabled() {
  local val="${CLAUDE_PLUGIN_OPTION_SYNC_GITIGNORED_WRITES:-true}"
  case "${val,,}" in
    false|0|no|off) return 1 ;;
    *) return 0 ;;
  esac
}
