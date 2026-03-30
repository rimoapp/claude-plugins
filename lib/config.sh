#!/usr/bin/env bash
# Configuration helpers for auto-worktree plugin.
# Reads user config from CLAUDE_PLUGIN_OPTION_* environment variables.

# Check if the given directory should be skipped by auto-worktree.
# Reads CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES (comma-separated absolute paths).
# Arguments: $1 = directory path (cwd)
# Returns: 0 if the directory should be skipped, 1 otherwise.
is_skipped_directory() {
  local dir="$1"
  local skip_dirs="${CLAUDE_PLUGIN_OPTION_SKIP_DIRECTORIES:-}"

  if [[ -z "$skip_dirs" ]]; then
    return 1
  fi

  # Resolve the directory to a real path for consistent comparison
  local resolved_dir="$dir"
  if command -v realpath &>/dev/null; then
    resolved_dir="$(realpath "$dir" 2>/dev/null)" || resolved_dir="$dir"
  fi

  local IFS=','
  for skip_dir in $skip_dirs; do
    # Trim whitespace
    skip_dir="$(echo "$skip_dir" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$skip_dir" ]] && continue

    # Resolve the skip dir too
    local resolved_skip="$skip_dir"
    if command -v realpath &>/dev/null; then
      resolved_skip="$(realpath "$skip_dir" 2>/dev/null)" || resolved_skip="$skip_dir"
    fi

    # Match if cwd is the skip dir or a subdirectory of it
    if [[ "$resolved_dir" == "$resolved_skip" || "$resolved_dir" == "$resolved_skip/"* ]]; then
      return 0
    fi
  done

  return 1
}

# Check if fetch_default_branch is enabled.
# Reads CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH.
# Returns: 0 if enabled (default), 1 if explicitly disabled.
is_fetch_enabled() {
  local val="${CLAUDE_PLUGIN_OPTION_FETCH_DEFAULT_BRANCH:-true}"
  # Treat "false", "0", "no", "off" as disabled
  case "${val,,}" in
    false|0|no|off) return 1 ;;
    *) return 0 ;;
  esac
}
