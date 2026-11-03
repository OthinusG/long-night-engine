#!/usr/bin/env bash
# Shared helpers for the engine pipeline scripts. Sourced, never executed.
#
# The pinned engine and the CLI discovery rule live here only, so no other
# script hard-codes a Godot path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The pinned engine. Override GODOT_BIN when Godot lives somewhere else; the
# version check below still refuses to run a different engine.
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# Every automated Godot test script, in dependency order.
GODOT_TESTS=(
  test_bootstrap.gd
  test_core_interfaces.gd
  test_story_program_loader.gd
  test_story_runtime_models.gd
  test_story_commands.gd
  test_story_vm.gd
  test_court_runtime.gd
  test_investigation_runtime.gd
  test_procedure_runtime.gd
  test_evidence_inspection.gd
  test_input_router.gd
  test_settings.gd
)

# Headless runtime demos that must end in PASS.
GODOT_DEMOS=(
  run_story_vm_demo.gd
  run_court_demo.gd
)

# Errors that are expected on some machines and never indicate a code problem.
ALLOWED_ERROR_PATTERN='user://logs|log file for writing|editor_doc_cache|ObjectDB instances were leaked|resources still in use at exit|Cannot create file'

info() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
note() { printf '    %s\n' "$1"; }

fail() {
  printf '\n\033[31mFAIL\033[0m: %s\n' "$1" >&2
  exit 1
}

require_godot() {
  [ -x "$GODOT_BIN" ] || fail "Godot executable not found at '$GODOT_BIN'. Set GODOT_BIN=/path/to/Godot."
  local found
  found="$("$GODOT_BIN" --version 2>/dev/null | head -1)"
  case "$found" in
    "$GODOT_VERSION"*) ;;
    *) fail "Pinned engine is Godot $GODOT_VERSION but '$GODOT_BIN' reports '$found'." ;;
  esac
  note "engine: $found"
}

# run_godot_script <tests/godot/x.gd> ; fails when the script exits non-zero or
# never actually ran. Godot exits 0 even when the --script file fails to parse
# or load, so the log is the only proof the test executed.
run_godot_script() {
  local script_path="$1"
  shift
  local log
  log="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path "$ROOT" --script "$script_path" "$@" 2>&1 | tee "$log"; then
    rm -f "$log"
    fail "$script_path"
  fi
  assert_script_ran "$log" "$script_path"
  rm -f "$log"
}

# assert_script_ran <logfile> <label> ; catches the "silently skipped test" hole.
assert_script_ran() {
  local log="$1" label="$2"
  if grep -Eq 'SCRIPT ERROR|Parse Error|Parser Error|Invalid call|Missing resource' "$log"; then
    grep -E 'SCRIPT ERROR|Parse Error|Parser Error|Invalid call|Missing resource' "$log" >&2
    fail "$label did not run"
  fi
}

# verify_pack_contents <pck> ; the release pack must carry the story build and
# must not carry developer content (spec 14.10).
verify_pack_contents() {
  local pack="$1"
  local required=(
    "story_build/story.json"
    "story_build/manifest.json"
    "data/evidence.json"
    "data/bgm.json"
    "data/sfx.json"
  )
  local forbidden=(
    "story_src/"
    "tests/"
    "tools/"
    "docs/"
    "scripts/"
    "debug_presets.json"
  )
  local entry
  for entry in "${required[@]}"; do
    grep -qa -- "$entry" "$pack" || fail "release pack is missing $entry"
  done
  for entry in "${forbidden[@]}"; do
    if grep -qa -- "res://$entry" "$pack"; then
      fail "release pack still contains $entry"
    fi
  done
  note "pack contents verified: ${#required[@]} required entries, ${#forbidden[@]} exclusions"
}

# assert_clean_log <logfile> ; fails on unexpected engine or script errors.
assert_clean_log() {
  local log="$1"
  if grep -Eq 'SCRIPT ERROR|Invalid call|Missing resource|Parser Error|Parse Error' "$log"; then
    grep -E 'SCRIPT ERROR|Invalid call|Missing resource|Parser Error|Parse Error' "$log" >&2
    fail "runtime script errors in $log"
  fi
  local unexpected
  unexpected="$(grep -E '^ERROR:' "$log" | grep -Ev "$ALLOWED_ERROR_PATTERN" || true)"
  if [ -n "$unexpected" ]; then
    printf '%s\n' "$unexpected" >&2
    fail "unexpected engine errors in $log"
  fi
}
