#!/usr/bin/env bash
# Heuristic to detect whether a Bash command is file-modifying (mutating).
# Used to decide whether the PreToolUse hook should intercept a Bash tool call.
#
# Only output redirects (> and >>) to tracked repo files are considered mutating.
# All other commands (git, package managers, file utilities, etc.) are allowed,
# since Write/Edit tools are the primary guard for file modifications.

# Check if a command is likely to modify tracked files via output redirect.
# Arguments: $1 = command string, $2 = cwd (for repo-relative path checks)
# Returns: 0 if mutating, 1 if read-only.
is_mutating_command() {
  local cmd="$1"
  local cwd="${2:-}"

  # Strip leading whitespace
  cmd="$(echo "$cmd" | sed 's/^[[:space:]]*//')"

  # Remove /dev/null redirects and stderr redirects before checking
  local sanitized
  sanitized="$(echo "$cmd" | sed -E 's/[0-9]*>[[:space:]]*\/dev\/null//g; s/[0-9]*>&[0-9]+//g')"

  # Check for output redirects (but not /dev/null or stderr-only redirects)
  if ! echo "$sanitized" | perl -ne 'BEGIN{$f=1} $f=0 if /(?<![0-9&])\s*>{1,2}\s/; END{exit $f}'; then
    # No redirect found → read-only
    return 1
  fi

  # Redirect found — extract the target path(s)
  local targets
  targets="$(echo "$sanitized" | perl -ne '
    while (/(?<![0-9&])\s*>{1,2}\s*"([^"]+)"/g) { print "$1\n"; }
    while (/(?<![0-9&])\s*>{1,2}\s*'\''([^'\'']+)'\''/g) { print "$1\n"; }
    while (/(?<![0-9&])\s*>{1,2}\s*([^\s"'\''|;&]+)/g) { print "$1\n"; }
  ' | sort -u)"

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
