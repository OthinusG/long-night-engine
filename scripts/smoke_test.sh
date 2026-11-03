#!/usr/bin/env bash
# Boots the game in --smoke-test mode and fails on runtime errors.
#
#   scripts/smoke_test.sh                 # development build (pinned Godot)
#   scripts/smoke_test.sh dist/macos/...  # exported executable
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

target="${1:-}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

if [ -z "$target" ]; then
  require_godot
  info "smoke test: development build"
  "$GODOT_BIN" --headless --path "$ROOT" -- --smoke-test >"$log" 2>&1 || {
    cat "$log" >&2
    fail "development smoke test"
  }
else
  [ -x "$target" ] || fail "Not an executable file: $target"
  info "smoke test: $target"
  "$target" --headless --smoke-test >"$log" 2>&1 || {
    cat "$log" >&2
    fail "exported smoke test"
  }
fi

grep -E '^\[Smoke\]' "$log" || {
  cat "$log" >&2
  fail "smoke runner produced no result line"
}
assert_clean_log "$log"
printf '\nSmoke test OK.\n'
