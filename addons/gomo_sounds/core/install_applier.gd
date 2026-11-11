@tool
extends RefCounted

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const InstallCatalog := preload("res://addons/gomo_sounds/core/install_catalog.gd")
const InstallImport := preload("res://addons/gomo_sounds/core/install_import.gd")
const InstallPlanner := preload("res://addons/gomo_sounds/core/install_planner.gd")
const SfxCatalog := preload("res://addons/gomo_sounds/runtime/sfx_catalog.gd")

## Runs an InstallPlanner plan. Order designed to never leave the project half-done:
##   1. downloads EVERYTHING into memory (network failed: nothing was touched);
##   2. moves plugin files whose location changed (along with the .import, which holds the uid:
##      scenes using the sound still find it);
##   3. deletes the ones removed from the site (only untouched ones, already filtered in the plan);
##   4. writes new ones through a temp file + swap (never a .wav cut in half);
##   5. writes the catalog; in the editor, imports, turns on loop and records the uids.

const TMP_SUFFIX := ".gomo_part"


## Returns {error, written, saved}. `saved` = the new catalog was written (only false when the network
## dropped before touching any file). `api` needs `get_bytes(url)` (the SfxApi, or a fake in tests).
## `progress`: called with the step text (the dock shows "Importing into Godot..." after the download).
static func apply(api: Object, plan_data: Dictionary, game_id: String, dir: String, progress := Callable()) -> Dictionary:
	var bytes := {}
	for a: Dictionary in plan_data["actions"]:
		if a["op"] in InstallPlanner.WRITES:
			var f: Variant = await api.get_bytes(a["url"])
			if not f.ok:
				return {"error": T.t("download_failed", [a["slot"], f.error]), "written": [], "saved": false}
			bytes[a["slot"]] = f.bytes
	var written: Array = []
	var touched: Array = []
	for a: Dictionary in plan_data["actions"]:
		# Couldn't move (file open in another program, destination taken): stays where it is.
		if a["op"] in ["move", "move_update"] and not _move(a["from"], a["path"]):
			a["op"] = "keep" if a["op"] == "move" else "update"
			a["path"] = a["from"]
			a["move_failed"] = true
		if a["op"] in ["move", "move_update"]:
			touched.append_array([a["from"], a["path"]])
			_prune_empty_dirs(str(a["from"]).get_base_dir())
		if a["op"] == "remove":
			_remove(a["path"])
			touched.append(a["path"])
			_prune_empty_dirs(str(a["path"]).get_base_dir())
	for a: Dictionary in plan_data["actions"]:
		if bytes.has(a["slot"]):
			if not _write(a["path"], bytes[a["slot"]]):
				_save(plan_data, game_id, dir, written)
				return {"error": T.t("no_write", a["path"]), "written": written, "saved": true}
			written.append(a)
			touched.append(a["path"])
	var catalog := _save(plan_data, game_id, dir, written)
	if Engine.is_editor_hint():
		if progress.is_valid():
			progress.call(T.t("importing"))
		await InstallImport.after_install(touched, written, catalog)
		InstallCatalog.save(catalog, dir)
	return {"error": "", "written": written, "saved": true}


## The new catalog: the registry (`files`) and what the game plays (`sounds`).
static func _save(plan_data: Dictionary, game_id: String, dir: String, written: Array) -> SfxCatalog:
	var catalog := SfxCatalog.new()
	catalog.game_id = game_id
	var fresh := {}
	for a: Dictionary in written:
		fresh[a["slot"]] = true
	var by_slot := {}
	for a: Dictionary in plan_data["actions"]:
		var entry := _ledger_entry(a, fresh.has(a["slot"]))
		if not entry.is_empty():
			catalog.files.append(entry)
			by_slot[a["slot"]] = entry
	for s: Dictionary in plan_data["sounds"]:
		var files: Array = []
		var uids: Array = []
		var loops: Array = []
		for slot: String in s["slots"]:
			var e: Dictionary = by_slot.get(slot, {})
			if not e.is_empty():
				files.append(e["path"])
				uids.append(e["uid"])
				loops.append(e["loop"])
		if not files.is_empty():
			catalog.sounds.append({"key": s["key"], "event": s["event"], "entity": s["entity"], "externalId": s["externalId"], "section": str(s.get("section", "")), "files": files, "uids": uids, "loops": loops})
	InstallCatalog.save(catalog, dir)
	return catalog


## The registry row after the operation. Empty = the file no longer belongs to the plugin.
static func _ledger_entry(a: Dictionary, fresh: bool) -> Dictionary:
	var old: Dictionary = a.get("entry", {})
	match a["op"]:
		"remove", "left_edited":
			return {}
		"left", "edited", "keep", "move":
			if old.is_empty():
				return {}
			var kept := old.duplicate()
			kept["path"] = a["path"]
			kept["pinned"] = bool(a.get("pinned", old.get("pinned", false)))
			# Same version as the site's: the site's tempo is this file's (fills catalogs from before 0.7.0).
			# Edited or gone from the site: keeps what it had.
			if a["op"] in ["keep", "move"]:
				kept["bpm"] = a.get("bpm")
			return kept
	if not fresh:
		return old.duplicate() if not old.is_empty() else {}
	return {
		"slot": a["slot"], "path": a["path"], "uid": str(old.get("uid", "")), "pinned": bool(a.get("pinned", false)),
		"sha256": FileAccess.get_sha256(a["path"]), "version": a["version"], "loop": a["loop"], "bpm": a.get("bpm"),
	}


static func _write(path: String, data: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	f.close()
	# Windows won't replace an existing file: the old one (ours, untouched) goes first.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


## Moves the file and its .import (which holds the uid). Destination taken = don't move.
static func _move(from: String, to: String) -> bool:
	if from == to:
		return true
	if FileAccess.file_exists(to):
		return false
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	if DirAccess.rename_absolute(from, to) != OK:
		return false
	if FileAccess.file_exists(from + ".import"):
		DirAccess.rename_absolute(from + ".import", to + ".import")
	return true


## Removes folders left empty (walking up while empty; never the project root nor a folder
## with anything inside, not even a hidden file).
static func _prune_empty_dirs(dir: String) -> void:
	var d := dir
	while d.begins_with("res://") and d != "res://" and DirAccess.dir_exists_absolute(d):
		var inside := DirAccess.open(d)
		if inside == null:
			return
		inside.include_hidden = true
		if not inside.get_files().is_empty() or not inside.get_directories().is_empty():
			return
		if DirAccess.remove_absolute(d) != OK:
			return
		d = d.get_base_dir()


static func _remove(path: String) -> void:
	DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".import"):
		DirAccess.remove_absolute(path + ".import")
