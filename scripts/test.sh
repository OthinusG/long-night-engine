#!/usr/bin/env bash
# Automated tests only (no content validation, no boot check).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_godot

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

printf '\n\033[32mAll tests passed.\033[0m\n'
