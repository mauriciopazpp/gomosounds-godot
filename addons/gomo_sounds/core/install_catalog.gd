@tool
extends RefCounted

const SfxCatalog := preload("res://addons/gomo_sounds/runtime/sfx_catalog.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")

## Reads and writes the catalog (the registry of what the plugin installed) and answers "is this file mine and
## untouched?". An old install (manifest.json) becomes a catalog on first read.

const LEGACY_MANIFEST := "manifest.json"


## On disk the catalog is a PLAIN Resource with the data in a metadata entry (no script of its own): in the exported
## game it drags no dependency along, and SfxLibrary reads it without needing a plugin class.
const META := "gomo_sounds"


## The install folder's catalog; if there is none, an empty one. Never returns null.
static func load_catalog(dir := "") -> SfxCatalog:
	var base := dir if dir != "" else SfxSettings.install_dir()
	var path := SfxSettings.catalog_path(base)
	if FileAccess.file_exists(path):
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res != null and res.has_meta(META):
			return _from_data(res.get_meta(META))
		# Format from 2026-09-26 (Resource with the SfxCatalog script): read the same, written in the new one.
		if res is SfxCatalog:
			return res
	return _from_legacy(base)


static func save(catalog: SfxCatalog, dir := "") -> Error:
	var base := dir if dir != "" else SfxSettings.install_dir()
	DirAccess.make_dir_recursive_absolute(base)
	var res := Resource.new()
	res.set_meta(META, {"format": catalog.format, "game_id": catalog.game_id, "sounds": catalog.sounds, "files": catalog.files})
	var err := ResourceSaver.save(res, SfxSettings.catalog_path(base))
	# The old manifest.json was ours and is already a catalog: remove it, so there aren't two sources of truth.
	if err == OK and FileAccess.file_exists(base + "/" + LEGACY_MANIFEST):
		DirAccess.remove_absolute(base + "/" + LEGACY_MANIFEST)
	return err


static func _from_data(data: Variant) -> SfxCatalog:
	var catalog := SfxCatalog.new()
	if not data is Dictionary:
		return catalog
	catalog.game_id = str(data.get("game_id", ""))
	for s: Variant in data.get("sounds", []):
		if s is Dictionary:
			catalog.sounds.append(s)
	for f: Variant in data.get("files", []):
		if f is Dictionary:
			catalog.files.append(f)
	return catalog


## The folder is no longer the install folder (the catalog was written elsewhere): removes the catalog and the
## old manifest.json from there. The sounds were already moved by the plan; what wasn't the plugin's stays.
static func retire(dir: String) -> void:
	for f: String in [SfxSettings.CATALOG_FILE, LEGACY_MANIFEST]:
		if FileAccess.file_exists(dir + "/" + f):
			DirAccess.remove_absolute(dir + "/" + f)


## Where the registered file is NOW. Moved via the Godot dock: the uid map already knows.
## Moved outside (file manager, a teammate's git pull): the map only updates when the
## editor restarts, so look up the uid in the project's .import files (only when the saved path is gone).
static func current_path(entry: Dictionary) -> String:
	var path := str(entry.get("path", ""))
	var uid := str(entry.get("uid", ""))
	if not uid.begins_with("uid://"):
		return path
	var id := ResourceUID.text_to_id(uid)
	if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id) and FileAccess.file_exists(ResourceUID.get_id_path(id)):
		return ResourceUID.get_id_path(id)
	if FileAccess.file_exists(path):
		return path
	return str(_uid_index().get(id, path))


static var _index := {}
static var _index_ready := false


## Forgets the uid index (the planner calls it at the start of each plan: the disk may have changed).
static func forget_moves() -> void:
	_index = {}
	_index_ready = false


## uid → path, for every imported file in the project (outside .godot and addons). Built once
## per plan, and only if some plugin file went missing from its place.
static func _uid_index() -> Dictionary:
	if not _index_ready:
		_index_ready = true
		_walk("res://")
	return _index


static func _walk(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".import"):
			var source := dir.path_join(f.trim_suffix(".import"))
			var id := ResourceLoader.get_resource_uid(source)
			if id != ResourceUID.INVALID_ID:
				_index[id] = source
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with(".") and not (dir == "res://" and d == "addons"):
			_walk(dir.path_join(d))


## Is the file as the plugin left it (same content)? Edited, replaced or missing = no.
static func is_intact(entry: Dictionary, path: String) -> bool:
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == str(entry.get("sha256", ""))


## Install from before the catalog: the files listed in manifest.json were written by the
## plugin, so they count as its own, with today's hash (if the user replaced one before this
## version, there's no way to know; it's the only blind spot, and only during migration).
static func _from_legacy(base: String) -> SfxCatalog:
	var catalog := SfxCatalog.new()
	var path := base + "/" + LEGACY_MANIFEST
	if not FileAccess.file_exists(path):
		return catalog
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return catalog
	for s: Dictionary in (parsed as Dictionary).get("sounds", []):
		var rels: Array = s.get("files", [s.get("file", "")])
		var versions: Array = s.get("fileIds", s.get("generationIds", []))
		for i in rels.size():
			var file := base + "/" + str(rels[i])
			if str(rels[i]) == "" or not FileAccess.file_exists(file):
				continue
			catalog.files.append({
				"slot": slot_id(str(s.get("key", "")), i), "path": file, "uid": "",
				"sha256": FileAccess.get_sha256(file), "version": str(versions[i]) if i < versions.size() else "", "loop": false,
			})
	return catalog


## A file's identity: the EVENT on the site (eventId) + the variation's position. Stable when the
## entity or event is renamed, and the same for every entity inheriting the sound from a
## folder (a single file). Old server, no eventId: falls back to the key.
static func slot_for(sound: Dictionary, index: int) -> String:
	var id := str(sound.get("eventId", ""))
	return slot_id(id if id != "" and id != "<null>" else str(sound.get("key", "")), index)


## Old identity format (and the fallback's): the sound key + the variation's position. Stable when the
## audio is edited on the site (the version changes, the place stays), so scenes using the file don't break.
static func slot_id(key: String, index: int) -> String:
	return "%s#%d" % [key, index]
