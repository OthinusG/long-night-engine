#!/usr/bin/env bash
# Exports the macOS release build and smoke-tests the exported executable.
#
# Signing and notarization are NOT configured: the exported app is unsigned and
# only runs locally (Gatekeeper will refuse it on another machine).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PRESET="macOS"
OUTPUT="dist/macos/Long Night.app"
BINARY="$OUTPUT/Contents/MacOS/Long Night"
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"

require_godot
[ -f "$TEMPLATES_DIR/macos.zip" ] || fail "macOS export templates missing: $TEMPLATES_DIR/macos.zip
Install them with: Godot editor -> Editor -> Manage Export Templates, or unpack
Godot_v${GODOT_VERSION}-stable_export_templates.tpz into
'$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable'."

info "check-all"
"$PYTHON_BIN" -m tools.story_compiler check-all

info "release pack contents"
"$GODOT_BIN" --headless --path "$ROOT" --export-pack "$PRESET" "$ROOT/dist/long_night.pck" >/dev/null
verify_pack_contents "$ROOT/dist/long_night.pck"
rm -f "$ROOT/dist/long_night.pck"

info "export $PRESET -> $OUTPUT"
mkdir -p dist/macos
rm -rf "$OUTPUT"
"$GODOT_BIN" --headless --path "$ROOT" --export-release "$PRESET" "$ROOT/$OUTPUT"
[ -x "$BINARY" ] || fail "export produced no executable at $BINARY"

info "exported contents"
du -sh "$OUTPUT"
cd "$OUTPUT/Contents/Resources" && ls -1

"$ROOT/scripts/smoke_test.sh" "$ROOT/$BINARY"
printf '\nmacOS export OK: %s\n' "$OUTPUT"
