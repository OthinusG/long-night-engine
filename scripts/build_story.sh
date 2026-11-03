#!/usr/bin/env bash
# Rebuilds the compiled story from story_src/ and data/, after validating it.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

info "check-all (content, cross-references, assets)"
# The build this script is about to write is older than the sources by
# definition, so the freshness stage is skipped here. Every other caller of
# check-all (including check.sh) does verify that story_build/ is up to date.
"$PYTHON_BIN" -m tools.story_compiler check-all --skip-build-check

info "build story IR"
"$PYTHON_BIN" -m tools.story_compiler build

info "story build"
ls -l story_build/
printf '\nBuild OK.\n'
