@tool
extends RefCounted

## Where the plugin stores what it needs to remember.
## The KEY lives in EditorSettings (per machine, outside the repository);
## the linked GAME lives in project.godot (it belongs to the project, can go to git).

const KEY_API_KEY := "gomo_sounds/api_key"
const KEY_API_URL := "gomo_sounds/api_url"
const KEY_GAME_ID := "gomo_sounds/game_id"
const KEY_SCAN_FOLDERS := "gomo_sounds/scan_folders"
const KEY_INSTALL_DIR := "gomo_sounds/install_dir"
const KEY_SKIP_WITH_SOUND := "gomo_sounds/skip_scenes_with_sound"
const KEY_LAYOUT := "gomo_sounds/layout"
const KEY_CUSTOM_DIR := "gomo_sounds/custom_dir"
const KEY_REMOVE_MISSING := "gomo_sounds/remove_missing"
## Prefix of old plugin versions (before the Gomo brand). `migrate_legacy` copies to the new one.
const LEGACY_PREFIX := "sfx_studio/"
const PREFIX := "gomo_sounds/"

const DEFAULT_API_URL := "https://gomosounds.com"
## The Gomo folder ("Gomo folder" and "beside the scene" modes, for sounds without a scene).
const DEFAULT_INSTALL_DIR := "res://gomosounds"
## Where old plugin versions installed (with manifest.json). Whoever already had sounds there
## keeps them there: changing the folder on its own would break scenes already pointing at the files.
const LEGACY_INSTALL_DIR := "res://audio/sfx_studio"
const CATALOG_FILE := "gomo_sounds.tres"
## Folders that usually hold units/mobs/buildings; the ones that exist become the default.
const GUESS_FOLDERS := [
	"res://units", "res://characters", "res://enemies", "res://mobs", "res://npcs",
	"res://creatures", "res://buildings", "res://structures",
	"res://actors", "res://entities", "res://scenes/units", "res://scenes/characters",
]


## Outside the editor (command line / CI) there are no EditorSettings: the key and URL
## come from the GOMO_API_KEY and GOMO_API_URL environment variables (the old SFX_* still work).
static func _editor() -> EditorSettings:
	return EditorInterface.get_editor_settings() if Engine.is_editor_hint() else null


## Environment variable GOMO_<name>, or the old SFX_<name>.
static func env(name: String) -> String:
	var v := OS.get_environment("GOMO_" + name)
	return v if v != "" else OS.get_environment("SFX_" + name)


## Whoever upgraded from the old plugin (settings under sfx_studio/...) keeps the key, the linked
## game and the folders: copies to the new name and deletes the old one. Writes project.godot only in the editor
## (the command line reads from memory and doesn't touch the project).
static func migrate_legacy() -> void:
	var moved := false
	for prop: Dictionary in ProjectSettings.get_property_list():
		var old := str(prop.name)
		if not old.begins_with(LEGACY_PREFIX):
			continue
		var key := PREFIX + old.trim_prefix(LEGACY_PREFIX)
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, ProjectSettings.get_setting(old))
		ProjectSettings.set_setting(old, null)
		moved = true
	if moved and Engine.is_editor_hint():
		ProjectSettings.save()
	var es := _editor()
	if es == null:
		return
	for prop: Dictionary in es.get_property_list():
		var old := str(prop.name)
		if not old.begins_with(LEGACY_PREFIX):
			continue
		var key := PREFIX + old.trim_prefix(LEGACY_PREFIX)
		if not es.has_setting(key):
			es.set_setting(key, es.get_setting(old))
		es.erase(old)


## This plugin's version (plugin.cfg): sent on every call, so the site can warn about new or too-old versions.
## Read once and cached: the running code IS this version, even if the file disappears later (a
## tool deleting and recopying the addons folder with the editor open made the site see "0.0.0").
static var _version := ""


static func plugin_version() -> String:
	if _version != "":
		return _version
	var cfg := ConfigFile.new()
	if cfg.load("res://addons/gomo_sounds/plugin.cfg") != OK:
		return "0.0.0"
	_version = str(cfg.get_value("plugin", "version", "0.0.0"))
	return _version


static func api_key() -> String:
	var es := _editor()
	if es == null:
		return env("API_KEY")
	return str(es.get_setting(KEY_API_KEY)) if es.has_setting(KEY_API_KEY) else ""


static func set_api_key(value: String) -> void:
	if _editor():
		_editor().set_setting(KEY_API_KEY, value)


static func api_url() -> String:
	var es := _editor()
	var v := ""
	if es == null:
		v = env("API_URL")
	elif es.has_setting(KEY_API_URL):
		v = str(es.get_setting(KEY_API_URL))
	return (v if v != "" else DEFAULT_API_URL).trim_suffix("/")


static func set_api_url(value: String) -> void:
	if _editor():
		_editor().set_setting(KEY_API_URL, value.strip_edges().trim_suffix("/"))


static func game_id() -> String:
	var env := env("GAME_ID")
	return env if env != "" else str(ProjectSettings.get_setting(KEY_GAME_ID, ""))


## Writes to project.godot only inside the editor: the command line doesn't touch the project.
static func set_game_id(value: String) -> void:
	ProjectSettings.set_setting(KEY_GAME_ID, value)
	if Engine.is_editor_hint():
		ProjectSettings.save()


## Where the sounds WILL live now: the custom folder ("custom" mode, if valid) or the Gomo one.
static func target_root() -> String:
	if layout() == "custom" and is_valid_install_dir(custom_dir()):
		return custom_dir()
	return DEFAULT_INSTALL_DIR


## Where the catalog IS today (the exported game reads it from project.godot). Differs from `target_root` after
## the person changes the mode or folder: the next install moves everything. Looks where it
## actually exists: the command line doesn't write project.godot, so the setting may be
## stale, and finding "no catalog" would make the plugin treat its own sounds as someone else's.
static func install_dir() -> String:
	var candidates: Array = []
	if ProjectSettings.has_setting(KEY_INSTALL_DIR):
		candidates.append(str(ProjectSettings.get_setting(KEY_INSTALL_DIR)).trim_suffix("/"))
	candidates.append_array([target_root(), LEGACY_INSTALL_DIR, DEFAULT_INSTALL_DIR])
	for dir: String in candidates:
		if is_valid_install_dir(dir) and _has_install(dir):
			return dir
	return target_root()


## The "Custom location" mode folder (lives in project.godot, applies to the whole team).
static func custom_dir() -> String:
	return str(ProjectSettings.get_setting(KEY_CUSTOM_DIR, "")).strip_edges().trim_suffix("/")


static func set_custom_dir(dir: String) -> void:
	ProjectSettings.set_setting(KEY_CUSTOM_DIR, dir.strip_edges().trim_suffix("/"))
	if Engine.is_editor_hint():
		ProjectSettings.save()


static func _has_install(dir: String) -> bool:
	return FileAccess.file_exists(dir + "/" + CATALOG_FILE) or FileAccess.file_exists(dir + "/manifest.json")


## Acceptable folder for sounds: inside the project, never the root, never the plugins folder nor
## .godot (Godot deletes/regenerates that one).
static func is_valid_install_dir(dir: String) -> bool:
	var d := dir.trim_suffix("/")
	return d.begins_with("res://") and d != "res:/" and d != "res://" \
		and not d.begins_with("res://addons") and not d.begins_with("res://.godot") and not d.contains("..")


## Writes the folder to project.godot (the exported game reads it from here to find the catalog).
static func set_install_dir(dir: String) -> void:
	ProjectSettings.set_setting(KEY_INSTALL_DIR, dir.trim_suffix("/"))
	if Engine.is_editor_hint():
		ProjectSettings.save()


static func catalog_path(dir := "") -> String:
	return (dir if dir != "" else install_dir()) + "/" + CATALOG_FILE


## Where to put the sounds: "gomo" (Gomo folder, default), "scene_folder", "beside_scene" or "custom".
static func layout() -> String:
	return str(ProjectSettings.get_setting(KEY_LAYOUT, "gomo"))


static func set_layout(id: String) -> void:
	ProjectSettings.set_setting(KEY_LAYOUT, id)
	if Engine.is_editor_hint():
		ProjectSettings.save()


## Sound removed from the list on the site: delete it from the project? Only applies to files the plugin wrote and
## nobody touched. On by default.
static func remove_missing() -> bool:
	return bool(ProjectSettings.get_setting(KEY_REMOVE_MISSING, true))


static func set_remove_missing(value: bool) -> void:
	ProjectSettings.set_setting(KEY_REMOVE_MISSING, value)
	if Engine.is_editor_hint():
		ProjectSettings.save()


## Folders scanned for scenes. Without configuration, guesses from common folders.
static func scan_folders() -> PackedStringArray:
	var saved: Variant = ProjectSettings.get_setting(KEY_SCAN_FOLDERS, null)
	if saved is PackedStringArray and not (saved as PackedStringArray).is_empty():
		return saved
	var found := PackedStringArray()
	for f: String in GUESS_FOLDERS:
		if DirAccess.dir_exists_absolute(f):
			found.append(f)
	return found if not found.is_empty() else PackedStringArray(["res://"])


static func set_scan_folders(folders: PackedStringArray) -> void:
	ProjectSettings.set_setting(KEY_SCAN_FOLDERS, folders)
	ProjectSettings.save()


## Hide (and don't upload) scenes that already have sound. On by default.
static func skip_scenes_with_sound() -> bool:
	return bool(ProjectSettings.get_setting(KEY_SKIP_WITH_SOUND, true))


static func set_skip_scenes_with_sound(value: bool) -> void:
	ProjectSettings.set_setting(KEY_SKIP_WITH_SOUND, value)
	if Engine.is_editor_hint():
		ProjectSettings.save()


static func project_name() -> String:
	var n := str(ProjectSettings.get_setting("application/config/name", ""))
	return n if n != "" else "Projeto Godot"
