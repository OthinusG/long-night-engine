#!/usr/bin/env bash
# Runs the whole automated regression suite: content pipeline, Python tests and
# every headless Godot test script. Non-zero exit on the first failure.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_godot

info "check-all (content, cross-references, assets)"
"$PYTHON_BIN" -m tools.story_compiler check-all

info "pytest"
"$PYTHON_BIN" -m pytest tests/ -q

info "Godot headless tests"
for script in "${GODOT_TESTS[@]}"; do
  note "$script"
  run_godot_script "tests/godot/$script"
done

info "Godot runtime demos"
for script in "${GODOT_DEMOS[@]}"; do
  note "$script"
  run_godot_script "tests/godot/$script"
done

info "project boot"
boot_log="$(mktemp)"
if ! "$GODOT_BIN" --headless --path "$ROOT" --quit-after 60 >"$boot_log" 2>&1; then
  cat "$boot_log" >&2
  fail "project boot"
fi
assert_clean_log "$boot_log"
rm -f "$boot_log"

printf '\n\033[32mAll checks passed.\033[0m\n'
