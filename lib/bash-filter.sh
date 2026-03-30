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

# Check if a command is likely to modify tracked files via output redirect.
# Arguments: $1 = command string, $2 = cwd (for repo-relative path checks)
# Returns: 0 if mutating, 1 if read-only.
is_mutating_command() {
  local cmd="$1"
  local cwd="${2:-}"

  # Strip leading whitespace
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"

  # Remove /dev/null redirects and stderr redirects before checking
  local sanitized
  sanitized="$(printf '%s' "$cmd" | sed -E 's/[0-9]*>[[:space:]]*\/dev\/null//g; s/[0-9]*>&[0-9]+//g')"

  # Remove here-document bodies so their contents don't trigger false positives
  sanitized="$(_strip_heredoc_bodies "$sanitized")"

  # Check for output redirects (> or >>, not preceded by digit, &, or >)
  if ! printf '%s\n' "$sanitized" | grep -qE '(^|[^0-9&>])[[:space:]]*>{1,2}[[:space:]]'; then
    # No redirect found → read-only
    return 1
  fi

  # Extract redirect target paths using sed (no perl).
  # Handles bare paths, double-quoted paths, and single-quoted paths.
  local targets
  targets="$(printf '%s\n' "$sanitized" | sed -nE \
    -e "s/.*[^0-9&>][[:space:]]*>{1,2}[[:space:]]*\"([^\"]+)\".*/\1/p" \
    -e "s/.*[^0-9&>][[:space:]]*>{1,2}[[:space:]]*'([^']+)'.*/\1/p" \
    -e "s/.*[^0-9&>][[:space:]]*>{1,2}[[:space:]]*([^[:space:]\"'|;&]+).*/\1/p" \
    | sort -u)"

  # If we couldn't extract any targets, fail open (allow)
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
