#!/usr/bin/env bash
# Tests for .claude-plugin/plugin.json manifest validation.
# Ensures the manifest meets Claude Code's plugin schema requirements.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFEST="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

source "${PLUGIN_ROOT}/lib/json.sh"

PASS=0
FAIL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local desc="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: expected '${expected}', got '${actual}'" >&2
  fi
}

assert_neq() {
  local unexpected="$1"
  local actual="$2"
  local desc="$3"
  if [[ "$actual" != "$unexpected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${desc}: got unexpected '${actual}'" >&2
  fi
}

VALID_TYPES="string number boolean directory file"

manifest="$(cat "$MANIFEST")"

# Extract userConfig keys
config_keys="$(parse_json_field "$manifest" '.userConfig | keys[]')"

for key in $config_keys; do
  # --- title must be a non-empty string ---
  title="$(parse_json_field "$manifest" ".userConfig.${key}.title")"
  assert_neq "null" "$title" "userConfig.${key} has title"

  # --- type must be one of the valid options ---
  type_val="$(parse_json_field "$manifest" ".userConfig.${key}.type")"
  found=false
  for vt in $VALID_TYPES; do
    if [[ "$type_val" == "$vt" ]]; then
      found=true
      break
    fi
  done
  if $found; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: userConfig.${key}.type: '${type_val}' is not one of: ${VALID_TYPES}" >&2
  fi
done

echo "${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
