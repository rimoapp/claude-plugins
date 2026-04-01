#!/usr/bin/env bash
# JSON parsing helpers for auto-worktree plugin.

# Extract a field from a JSON string.
# Arguments: $1 = JSON string, $2 = jq-style field path (e.g. '.tool_name')
# Outputs the field value to stdout. Returns empty string on failure.
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
