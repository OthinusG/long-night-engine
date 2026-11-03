#!/usr/bin/env bash
# Exports the Windows release build. Running it requires a Windows machine; on
# macOS only the export (and its asset inclusion) can be verified.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PRESET="Windows"
OUTPUT="dist/windows/AceAttorneyEngine.exe"
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"

require_godot
[ -f "$TEMPLATES_DIR/windows_release_x86_64.exe" ] || fail "Windows export templates missing: $TEMPLATES_DIR/windows_release_x86_64.exe
Install them with: Godot editor -> Editor -> Manage Export Templates, or unpack
Godot_v${GODOT_VERSION}-stable_export_templates.tpz into
'$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable'."

info "check-all"
"$PYTHON_BIN" -m tools.story_compiler check-all

info "release pack contents"
mkdir -p "$ROOT/dist"
"$GODOT_BIN" --headless --path "$ROOT" --export-pack "$PRESET" "$ROOT/dist/ace_attorney_engine.pck" >/dev/null
verify_pack_contents "$ROOT/dist/ace_attorney_engine.pck"
rm -f "$ROOT/dist/ace_attorney_engine.pck"

info "export $PRESET -> $OUTPUT"
mkdir -p dist/windows
rm -f "$OUTPUT" "$OUTPUT.pck"
"$GODOT_BIN" --headless --path "$ROOT" --export-release "$PRESET" "$ROOT/$OUTPUT"
[ -f "$OUTPUT" ] || fail "export produced no executable at $OUTPUT"

if [ -f "$ROOT/icon.ico" ]; then
  info "inject app icon into $OUTPUT"
  "$PYTHON_BIN" "$ROOT/scripts/inject_icon.py" "$ROOT/$OUTPUT" "$ROOT/icon.ico"
fi

ZIP_OUT="dist/windows/AceAttorneyEngine-windows-x86_64.zip"
info "package $ZIP_OUT"
(cd "$ROOT/dist/windows" && rm -f "AceAttorneyEngine-windows-x86_64.zip" && zip -9 "AceAttorneyEngine-windows-x86_64.zip" AceAttorneyEngine.exe AceAttorneyEngine.pck)

ls -lh "$ROOT/dist/windows/"
printf '\nWindows export OK: %s\nPackage ready: %s\n' "$OUTPUT" "$ZIP_OUT"
