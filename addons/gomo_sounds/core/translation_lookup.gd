@tool
extends RefCounted

const SfxSceneScanner := preload("res://addons/gomo_sounds/core/scene_scanner.gd")

## Translates keys (e.g. "UNIT_LADYBUG_DESC") into the editor language, reading the
## project's .translation files straight from disk: works even when the game only
## loads translations via autoload (at runtime), outside the editor.

var _translations: Array[Translation] = []


func _init(locale: String = "") -> void:
	var want := locale if locale != "" else OS.get_locale()
	var lang := want.split("_")[0]
	var exact: Array[Translation] = []
	var by_lang: Array[Translation] = []
	for path in _translation_paths():
		var t := load(path) as Translation
		if t == null:
			continue
		if t.locale == want:
			exact.append(t)
		elif t.locale.split("_")[0] == lang:
			by_lang.append(t)
	_translations = exact if not exact.is_empty() else by_lang


## Translated text, or "" when the key doesn't exist in any file.
func tr_key(key: String) -> String:
	if key == "":
		return ""
	for t in _translations:
		var msg := String(t.get_message(key))
		if msg != "":
			return msg
	return ""


func _translation_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var configured: Variant = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	if configured is PackedStringArray:
		out.append_array(configured)
	if Engine.is_editor_hint():
		_collect(EditorInterface.get_resource_filesystem().get_filesystem(), out)
	else:
		SfxSceneScanner.walk_disk("res://", ".translation", out)
	return out


func _collect(dir: EditorFileSystemDirectory, out: PackedStringArray) -> void:
	if dir == null or dir.get_path().begins_with("res://addons"):
		return
	for i in dir.get_file_count():
		var p := dir.get_file_path(i)
		if p.ends_with(".translation") and not out.has(p):
			out.append(p)
	for i in dir.get_subdir_count():
		_collect(dir.get_subdir(i), out)
