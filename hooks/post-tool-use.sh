#!/usr/bin/env bash
# PostToolUse hook for auto-worktree plugin.
# After Write, Edit, or Bash tool calls, checks if any gitignored files
# were written inside a worktree and copies them back to the main repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PLUGIN_ROOT}/lib/json.sh"
source "${PLUGIN_ROOT}/lib/worktree.sh"
source "${PLUGIN_ROOT}/lib/bash-filter.sh"
source "${PLUGIN_ROOT}/lib/config.sh"

main() {
  local input
  input="$(cat)"

  local tool_name cwd
  tool_name="$(parse_json_field "$input" '.tool_name')"
  cwd="$(parse_json_field "$input" '.cwd')"

  # Early exits
  if [[ -z "$tool_name" || -z "$cwd" ]]; then
    exit 0
  fi

  if ! is_sync_gitignored_enabled; then
    exit 0
  fi

  if ! is_inside_worktree "$cwd"; then
    exit 0
  fi

  local worktree_root main_repo_root
  worktree_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
  main_repo_root="$(get_main_repo_root "$cwd")" || exit 0

  # Resolve symlinks for consistent path comparison (macOS: /var → /private/var)
  if command -v realpath &>/dev/null; then
    worktree_root="$(realpath "$worktree_root" 2>/dev/null)" || true
    main_repo_root="$(realpath "$main_repo_root" 2>/dev/null)" || true
  fi

  # Don't sync to self
  if [[ "$worktree_root" == "$main_repo_root" ]]; then
    exit 0
  fi

  # Collect gitignored file paths to sync
  local files_to_sync=()

  if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" ]]; then
    local file_path
    file_path="$(parse_json_field "$input" '.tool_input.file_path')"
    if [[ -n "$file_path" ]]; then
      # Resolve relative paths against cwd
      if [[ "$file_path" != /* ]]; then
        file_path="${cwd}/${file_path}"
      fi
      if is_gitignored_in_repo "$cwd" "$file_path"; then
        files_to_sync+=("$file_path")
      fi
    fi
  elif [[ "$tool_name" == "Bash" ]]; then
    local command
    command="$(parse_json_field "$input" '.tool_input.command')"
    if [[ -n "$command" ]]; then
      local targets
      targets="$(get_ignored_redirect_targets "$command" "$cwd")"
      if [[ -n "$targets" ]]; then
        while IFS= read -r target; do
          [[ -n "$target" ]] && files_to_sync+=("$target")
        done <<< "$targets"
      fi
    fi
  fi

  # Nothing to sync
  if [[ ${#files_to_sync[@]} -eq 0 ]]; then
    exit 0
  fi

  # Copy each file to main repo
  local synced=0
  for file_path in "${files_to_sync[@]}"; do
    [[ -f "$file_path" ]] || continue
    # Resolve symlinks for consistent prefix stripping
    if command -v realpath &>/dev/null; then
      file_path="$(realpath "$file_path" 2>/dev/null)" || true
    fi
    local rel_path="${file_path#"$worktree_root/"}"
    local dest="${main_repo_root}/${rel_path}"
    mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    if cp -p "$file_path" "$dest" 2>/dev/null; then
      ((synced++)) || true
    fi
  done

  if ((synced > 0)); then
    echo "[auto-worktree] Synced $synced gitignored file(s) to main repo." >&2
  fi

  exit 0
}

main
