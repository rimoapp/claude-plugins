#!/usr/bin/env bash
# Heuristic to detect whether a Bash command is file-modifying (mutating).
# Used to decide whether the PreToolUse hook should intercept a Bash tool call.
#
# Only output redirects (> and >>) to tracked repo files are considered mutating.
# All other commands (git, package managers, file utilities, etc.) are allowed,
# since Write/Edit tools are the primary guard for file modifications.
#
# Pure bash/sed/grep only — no perl or python dependency.

# Strip here-document bodies from a command string, keeping only the command
# lines themselves. This prevents content inside heredocs (e.g. XML tags with >)
# from being misdetected as output redirects.
_strip_heredoc_bodies() {
  local input="$1"
  local delim=""
  local output=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "$delim" ]]; then
      # Inside heredoc body — skip until closing delimiter.
      # For <<- heredocs, the delimiter may be preceded by tabs.
      local stripped="${line%%[^	]*}"  # count leading tabs only
      stripped="${line#"$stripped"}"     # remove leading tabs
      if [[ "$stripped" == "$delim" ]]; then
        delim=""
      fi
      continue
    fi

    # Detect heredoc start: <<'DELIM', <<"DELIM", <<DELIM, <<-DELIM, etc.
    if [[ "$line" =~ \<\<-?[[:space:]]*\'([^\']+)\' ]]; then
      delim="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ \<\<-?[[:space:]]*\"([^\"]+)\" ]]; then
      delim="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ \<\<-?[[:space:]]*\\?([A-Za-z_][A-Za-z0-9_]*) ]]; then
      delim="${BASH_REMATCH[1]}"
    fi

    output+="$line"$'\n'
  done <<< "$input"

  printf '%s' "$output"
}

# Sanitize a command string for redirect analysis.
# Strips /dev/null redirects, stderr redirects, and heredoc bodies.
# Arguments: $1 = command string
# Outputs: sanitized command string.
_sanitize_command() {
  local cmd="$1"

  # Strip leading whitespace
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"

  # Remove /dev/null redirects and stderr redirects before checking
  local sanitized
  sanitized="$(printf '%s' "$cmd" | sed -E 's/[0-9]*>[[:space:]]*\/dev\/null//g; s/[0-9]*>&[0-9]+//g')"

  # Remove here-document bodies so their contents don't trigger false positives
  sanitized="$(_strip_heredoc_bodies "$sanitized")"

  printf '%s' "$sanitized"
}

# Extract redirect target paths from a sanitized command string.
# Outputs newline-separated list of unique target paths (may be relative).
# Arguments: $1 = sanitized command string
_extract_redirect_targets() {
  local sanitized="$1"

  # Check for output redirects (> or >>, not preceded by digit, &, or >)
  if ! printf '%s\n' "$sanitized" | grep -qE '(^|[^0-9&>])[[:space:]]*>{1,2}[[:space:]]'; then
    return
  fi

  # Extract redirect target paths.
  # Uses grep -oE to find ALL redirect expressions (not just the last per line),
  # then sed to extract the target path from each match.
  # Handles bare paths, double-quoted paths, and single-quoted paths.
  printf '%s\n' "$sanitized" \
    | grep -oE '[^0-9&>[:space:]]?[[:space:]]*>{1,2}[[:space:]]*(\"[^\"]+\"|'\''[^'\'']+'\''|[^[:space:]"'\''|;&]+)' \
    | sed -E \
      -e 's/.*>[[:space:]]*//' \
      -e 's/^"(.*)"$/\1/' \
      -e "s/^'(.*)'$/\1/" \
    | sort -u
}

# Check if a command is likely to modify tracked files via output redirect.
# Arguments: $1 = command string, $2 = cwd (for repo-relative path checks)
# Returns: 0 if mutating, 1 if read-only.
is_mutating_command() {
  local cmd="$1"
  local cwd="${2:-}"

  local sanitized
  sanitized="$(_sanitize_command "$cmd")"

  local targets
  targets="$(_extract_redirect_targets "$sanitized")"

  # If no targets found, fail open (allow)
  if [[ -z "$targets" ]]; then
    return 1
  fi

  # Check each redirect target
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue

    # Allow redirects to /tmp, /var/tmp, /dev/
    if [[ "$target" == /tmp/* || "$target" == /var/tmp/* || "$target" == /dev/* ]]; then
      continue
    fi

    # If we have cwd context, check if target is outside repo or gitignored
    if [[ -n "$cwd" ]] && type -t is_outside_repo_or_ignored &>/dev/null; then
      local resolved="$target"
      if [[ "$target" != /* ]]; then
        resolved="${cwd}/${target}"
      fi

      if is_outside_repo_or_ignored "$cwd" "$resolved"; then
        continue
      fi
    fi

    # This redirect target is inside the repo and not ignored → mutating
    return 0
  done <<< "$targets"

  # All redirect targets are safe
  return 1
}

# Get redirect targets from a command that point to gitignored files inside the repo.
# Arguments: $1 = command string, $2 = cwd
# Outputs: newline-separated list of absolute paths that are gitignored in the repo.
get_ignored_redirect_targets() {
  local cmd="$1"
  local cwd="${2:-}"

  [[ -z "$cwd" ]] && return

  local sanitized
  sanitized="$(_sanitize_command "$cmd")"

  local targets
  targets="$(_extract_redirect_targets "$sanitized")"

  [[ -z "$targets" ]] && return

  while IFS= read -r target; do
    [[ -z "$target" ]] && continue

    # Skip /tmp, /var/tmp, /dev/
    if [[ "$target" == /tmp/* || "$target" == /var/tmp/* || "$target" == /dev/* ]]; then
      continue
    fi

    # Resolve to absolute path
    local resolved="$target"
    if [[ "$target" != /* ]]; then
      resolved="${cwd}/${target}"
    fi

    # Output only if inside repo and gitignored
    if type -t is_gitignored_in_repo &>/dev/null && is_gitignored_in_repo "$cwd" "$resolved"; then
      echo "$resolved"
    fi
  done <<< "$targets"
}
