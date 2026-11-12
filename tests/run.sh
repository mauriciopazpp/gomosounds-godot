#!/usr/bin/env bash
# Godot plugin tests in an isolated test project (.godot-testbed, outside git): never in a
# real game. Usage: tests/run.sh (from the plugin's folder) or integrations/godot/tests/run.sh
# Phase 1: install rules (no editor). Phase 2: inside the editor, headless (import,
# loop, uid, moving files, panel and icon).
set -euo pipefail
# Runs from the plugin's root (this folder's parent), so it works in this repository and in the public one.
cd "$(dirname "$0")/.."
TB=.godot-testbed
mkdir -p "$TB/addons" "$TB/samples"
[ -e "$TB/addons/gomo_sounds" ] || ln -s ../../addons/gomo_sounds "$TB/addons/gomo_sounds"
[ -e "$TB/addons/gomo_editor_probe" ] || ln -s ../../tests/editor_probe "$TB/addons/gomo_editor_probe"
[ -e "$TB/export_probe" ] || ln -s ../tests/export_probe "$TB/export_probe"
[ -e "$TB/install_test.gd" ] || ln -s ../tests/install_test.gd "$TB/install_test.gd"
# Copies (not links): Godot writes .import files next to them, and those must not end up in the repository.
# The samples are short synthetic sounds made for the tests (tests/samples).
cp tests/samples/fire.wav tests/samples/rain.wav tests/samples/forest.wav tests/samples/click.mp3 "$TB/samples/"
GODOT="${GODOT:-godot-4}"

printf 'config_version=5\n\n[application]\nconfig/name="Gomo Testbed"\nrun/main_scene="res://export_probe/export_main.tscn"\n\n[autoload]\nSfxLibrary="*res://addons/gomo_sounds/runtime/sfx_library.gd"\n' > "$TB/project.godot"
"$GODOT" --headless --path "$TB" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$TB" -s res://install_test.gd

printf '\n[editor_plugins]\n\nenabled=PackedStringArray("res://addons/gomo_sounds/plugin.cfg", "res://addons/gomo_editor_probe/plugin.cfg")\n' >> "$TB/project.godot"
: > "$TB/editor_probe_result.txt"
timeout 180 "$GODOT" --headless --editor --path "$TB" >/dev/null 2>&1 || true
echo "--- editor ---"
cat "$TB/editor_probe_result.txt"
grep -q "^0 failures" "$TB/editor_probe_result.txt"

# Phase 3: EXPORTED game with a preset that ships only one scene (the plugin must include the sounds).
cp tests/export_probe/export_presets.cfg "$TB/export_presets.cfg"
mkdir -p "$TB/out"
# The game from the previous run must not answer for this one.
rm -f "$TB/out/game.x86_64" "$TB/out/game.pck"
timeout 300 "$GODOT" --headless --path "$TB" --export-release "Linux" out/game.x86_64 > "$TB/out/export.log" 2>&1 || true
echo "--- exported ---"
RESULT=$(timeout 60 "$TB/out/game.x86_64" --headless 2>&1 | grep GOMO_EXPORT || true)
echo "${RESULT:-GOMO_EXPORT (did not run: see $TB/out/export.log)}"
echo "$RESULT" | grep -q "has=true played=true loop=true"
