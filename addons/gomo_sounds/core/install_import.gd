@tool
extends RefCounted

## After writing the files, inside the editor: tells Godot what changed, imports, turns on
## loop for sounds marked as loop on the site (at import, so it works even for someone who drags the
## file onto an AudioStreamPlayer by hand) and records each file's uid in the catalog, which is what
## lets the user move the folder within Godot without the game losing the sound.

## Importer → loop option. WAV: 0 = read from file (Godot default), 2 = forward.
const LOOP_OPTION := {"wav": ["edit/loop_mode", 2, 0], "ogg": ["loop", true, false], "mp3": ["loop", true, false]}


## Godot only imports a new file during a scan (reimport_files ignores files it hasn't seen yet):
## scan and wait for the import to FINISH (before that, edits to the .import get overwritten by it).
static func after_install(touched: Array, written: Array, catalog: Resource) -> void:
	var efs := EditorInterface.get_resource_filesystem()
	if touched.is_empty() and written.is_empty():
		# Nothing changed on disk, but missing uids (installed from the command line) get added now.
		_fill_uids(catalog)
		return
	var paths := PackedStringArray()
	for a: Dictionary in written:
		paths.append(a["path"])
	await _scan_and_wait(efs, paths)
	var relooped := PackedStringArray()
	for a: Dictionary in written:
		if _set_loop(a["path"], a["loop"]):
			relooped.append(a["path"])
	if not relooped.is_empty():
		efs.reimport_files(relooped)
	_fill_uids(catalog)


## A limit in TIME, not frames: with the editor unfocused each frame takes ~100 ms and 1200 frames became
## minutes; the first wait had no limit at all and the dock stayed on "Downloading..." forever. When time
## runs out it goes on anyway: loop and uid are set on what was imported, and the next install finishes the rest.
const WAIT_MS := 30000


static func _scan_and_wait(efs: EditorFileSystem, paths: PackedStringArray) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while efs.is_scanning() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	efs.scan()
	deadline = Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if not efs.is_scanning() and not _importing(efs) and _all_imported(paths):
			return


## Install with nothing new to download: files that still lack a uid in the catalog or have the wrong
## loop in the .import (an earlier install that stopped halfway) get fixed now. Returns true if it changed something.
static func repair(catalog: Resource) -> bool:
	var pending: Array = []
	for e: Dictionary in catalog.get("files"):
		var path := str(e.get("path", ""))
		if FileAccess.file_exists(path) and (str(e.get("uid", "")) == "" or _loop_wrong(path, bool(e.get("loop", false)))):
			pending.append({"path": path, "loop": bool(e.get("loop", false))})
	if pending.is_empty():
		return false
	await after_install(pending, pending, catalog)
	return true


static func _loop_wrong(path: String, on: bool) -> bool:
	var opt: Array = LOOP_OPTION.get(path.get_extension().to_lower(), [])
	var cfg := ConfigFile.new()
	if opt.is_empty() or cfg.load(path + ".import") != OK:
		return false
	return cfg.get_value("params", opt[0], null) != (opt[1] if on else opt[2])


static func _importing(efs: EditorFileSystem) -> bool:
	return efs.has_method("is_importing") and bool(efs.call("is_importing"))


static func _all_imported(paths: PackedStringArray) -> bool:
	for p in paths:
		if not FileAccess.file_exists(p + ".import") or ResourceLoader.get_resource_uid(p) == ResourceUID.INVALID_ID:
			return false
	return true


## Sets the loop option in the .import; returns true if it changed (needs reimporting).
static func _set_loop(path: String, on: bool) -> bool:
	var opt: Array = LOOP_OPTION.get(path.get_extension().to_lower(), [])
	var cfg := ConfigFile.new()
	if opt.is_empty() or cfg.load(path + ".import") != OK:
		return false
	var value: Variant = opt[1] if on else opt[2]
	if cfg.get_value("params", opt[0], null) == value:
		return false
	cfg.set_value("params", opt[0], value)
	return cfg.save(path + ".import") == OK


static func _fill_uids(catalog: Resource) -> void:
	var uid_of := {}
	for e: Dictionary in catalog.get("files"):
		var id := ResourceLoader.get_resource_uid(e["path"])
		if id != ResourceUID.INVALID_ID:
			e["uid"] = ResourceUID.id_to_text(id)
		uid_of[e["path"]] = e["uid"]
	for s: Dictionary in catalog.get("sounds"):
		var uids: Array = []
		for p: String in s["files"]:
			uids.append(uid_of.get(p, ""))
		s["uids"] = uids
