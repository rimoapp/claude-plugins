#!/usr/bin/env bash
# Git worktree detection helpers for auto-worktree plugin.

# Check if the given directory is inside a non-main git worktree.
# Arguments: $1 = directory path
# Returns: 0 if inside a linked worktree, 1 if in main repo or not a git repo.
is_inside_worktree() {
  local dir="$1"
  local git_dir
  git_dir="$(git -C "$dir" rev-parse --git-dir 2>/dev/null)" || return 1

  # Linked worktrees have a git-dir path containing "/worktrees/"
  if [[ "$git_dir" == *"/worktrees/"* ]]; then
    return 0
  fi

  # Also check if .git is a gitfile (file pointing to actual git dir)
  local dot_git="${dir}/.git"
  if [[ -f "$dot_git" ]]; then
    return 0
  fi

  return 1
}

# Check if the given directory is inside any git repository.
# Arguments: $1 = directory path
# Returns: 0 if inside a git repo, 1 otherwise.
is_git_repo() {
  local dir="$1"
  git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null
}

# Check if a file path is outside the git repo or gitignored.
# Arguments: $1 = repo directory, $2 = file path
# Returns: 0 if the file is outside the repo root or gitignored, 1 otherwise.
# Check if the current branch is the default branch (main/master or configured default).
# Arguments: $1 = directory path
# Returns: 0 if on the default branch, 1 otherwise.
is_on_default_branch() {
  local dir="$1"
  local current_branch default_branch

  current_branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1

  # Try to detect the default branch from the remote
  default_branch="$(git -C "$dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')" || true

  # Fallback: check common default branch names
  if [[ -z "$default_branch" ]]; then
    if git -C "$dir" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
      default_branch="main"
    elif git -C "$dir" show-ref --verify --quiet refs/heads/master 2>/dev/null; then
      default_branch="master"
    else
      # If we can't determine the default branch, assume current is not default
      return 1
    fi
  fi

  [[ "$current_branch" == "$default_branch" ]]
}

is_outside_repo_or_ignored() {
  local dir="$1"
  local file_path="$2"

  local repo_root
  repo_root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1

  # If file_path is relative, treat it as relative to dir
  if [[ "$file_path" != /* ]]; then
    file_path="${dir}/${file_path}"
  fi

  # Resolve symlinks for consistent comparison (macOS: /var → /private/var)
  if command -v realpath &>/dev/null; then
    repo_root="$(realpath "$repo_root")"
    # Walk up to find the nearest existing ancestor to resolve symlinks
    local resolve_path="$file_path"
    local suffix=""
    while [[ ! -e "$resolve_path" ]] && [[ "$resolve_path" != "/" ]]; do
      suffix="/$(basename "$resolve_path")${suffix}"
      resolve_path="$(dirname "$resolve_path")"
    done
    if [[ -e "$resolve_path" ]]; then
      file_path="$(realpath "$resolve_path")${suffix}"
    fi
  fi

  # Check if file is outside the repo root
  case "$file_path" in
    "${repo_root}/"*) ;;  # inside repo, continue checks
    "${repo_root}")   return 1 ;;  # the repo root itself
    *)                return 0 ;;  # outside repo
  esac

  # Check if file is gitignored (low-cost: single git command)
  if git -C "$repo_root" check-ignore -q "$file_path" 2>/dev/null; then
    return 0
  fi

  return 1
}
