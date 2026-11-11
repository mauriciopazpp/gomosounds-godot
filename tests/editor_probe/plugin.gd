@tool
extends EditorPlugin

## Test INSIDE the editor (tests/run.sh, phase 2): installs with the fake "site" and checks what only
## exists in the editor: import, loop enabled in the .import, uid in the catalog and the panel with the icon.

const InstallApplier := preload("res://addons/gomo_sounds/core/install_applier.gd")
const InstallCatalog := preload("res://addons/gomo_sounds/core/install_catalog.gd")
const InstallImport := preload("res://addons/gomo_sounds/core/install_import.gd")
const InstallPlanner := preload("res://addons/gomo_sounds/core/install_planner.gd")
const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxBrand := preload("res://addons/gomo_sounds/ui/brand.gd")
const SoundLayout := preload("res://addons/gomo_sounds/core/sound_layout.gd")

const ROOT := "res://gomo_editor"
const ROOT2 := "res://gomo_editor2"
const MINE := "res://gomo_mine"
var _lines := PackedStringArray()
var _fails := 0


func get_bytes(url: String) -> SfxApi.Result:
	var r := SfxApi.Result.new()
	r.ok = true
	r.bytes = FileAccess.get_file_as_bytes(url)
	return r


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	var efs := EditorInterface.get_resource_filesystem()
	while efs.is_scanning():
		await get_tree().process_frame
	for d: String in [ROOT, ROOT2, MINE]:
		_remove_tree(d)
	var m := {"sounds": [
		{"key": "rain.loop", "entity": "Rain", "externalId": null, "event": "Loop", "inheritedFrom": null,
			"files": ["res://samples/rain.wav"], "paths": ["sounds/rain/loop.wav"], "fileIds": ["r1"], "loops": [true]},
		{"key": "click.sound", "entity": "Click", "externalId": null, "event": "Sound", "inheritedFrom": null,
			"files": ["res://samples/click.mp3"], "paths": ["sounds/click/sound.mp3"], "fileIds": ["c1"], "loops": [false]},
	]}
	var plan := InstallPlanner.plan(m, InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT, true)
	var r: Dictionary = await InstallApplier.apply(self, plan, "g", ROOT)
	_ok(r["error"] == "", "installed in the editor")
	var cfg := ConfigFile.new()
	_ok(cfg.load(ROOT + "/rain/loop.wav.import") == OK, "Godot imported the sound")
	_ok(cfg.get_value("params", "edit/loop_mode", -1) == 2, "loop on in the import")
	var catalog := InstallCatalog.load_catalog(ROOT)
	var uids := 0
	for e: Dictionary in catalog.files:
		uids += 1 if str(e["uid"]).begins_with("uid://") else 0
	_ok(uids == 2, "uid recorded in the catalog (%d of 2)" % uids)
	var stream := load(ROOT + "/rain/loop.wav") as AudioStreamWAV
	_ok(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the sound loads looping")
	await _test_repair(catalog)
	await _test_moves(m, efs)
	var icon := SfxBrand.icon(64)
	var orange := 0
	if icon != null:
		var img := icon.get_image()
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				orange += 1 if c.a > 0.9 and c.r > 0.85 and c.g > 0.35 and c.g < 0.75 and c.b < 0.35 else 0
	_ok(icon != null and icon.get_width() == 64 and orange > 300, "tangerine icon drawn (%d orange px)" % orange)
	var dock: Control = load("res://addons/gomo_sounds/ui/sfx_dock.gd").new()
	EditorInterface.get_base_control().add_child(dock)
	await get_tree().process_frame
	_ok(dock.is_inside_tree(), "dock opens")
	dock.queue_free()
	_lines.append("%d failures" % _fails)
	var f := FileAccess.open("res://editor_probe_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	get_tree().quit()


## An install that stopped halfway (no uid in the catalog, loop off in the .import): clicking Install with
## nothing new fixes both.
func _test_repair(catalog: Resource) -> void:
	for e: Dictionary in catalog.get("files"):
		e["uid"] = ""
	var cfg := ConfigFile.new()
	cfg.load(ROOT + "/rain/loop.wav.import")
	cfg.set_value("params", "edit/loop_mode", 0)
	cfg.save(ROOT + "/rain/loop.wav.import")
	var fixed: bool = await InstallImport.repair(catalog)
	var uids := 0
	for e: Dictionary in catalog.get("files"):
		uids += 1 if str(e["uid"]).begins_with("uid://") else 0
	cfg.load(ROOT + "/rain/loop.wav.import")
	_ok(fixed and uids == 2 and cfg.get_value("params", "edit/loop_mode", -1) == 2, "repair: uid and loop back (%d of 2)" % uids)


## (a) the plugin changes the folder: the uid (and the scenes using the sound) survives; (b) the user moves a
## sound in Godot: on the next install it stays where they put it.
func _test_moves(m: Dictionary, efs: EditorFileSystem) -> void:
	var uid_before := ResourceLoader.get_resource_uid(ROOT + "/rain/loop.wav")
	var plan := InstallPlanner.plan(m, InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT2, true)
	await InstallApplier.apply(self, plan, "g", ROOT2)
	_ok(FileAccess.file_exists(ROOT2 + "/rain/loop.wav") and not FileAccess.file_exists(ROOT + "/rain/loop.wav"), "new folder: the sound moved")
	_ok(ResourceLoader.get_resource_uid(ROOT2 + "/rain/loop.wav") == uid_before, "moved with the same uid")
	DirAccess.make_dir_recursive_absolute(MINE)
	DirAccess.rename_absolute(ROOT2 + "/click/sound.mp3", MINE + "/sound.mp3")
	DirAccess.rename_absolute(ROOT2 + "/click/sound.mp3.import", MINE + "/sound.mp3.import")
	efs.scan()
	await get_tree().process_frame
	while efs.is_scanning():
		await get_tree().process_frame
	var uid := ResourceLoader.get_resource_uid(MINE + "/sound.mp3")
	for i in 600:
		await get_tree().process_frame
		if ResourceUID.has_id(uid) and ResourceUID.get_id_path(uid) == MINE + "/sound.mp3":
			break
	var again := InstallPlanner.plan(m, InstallCatalog.load_catalog(ROOT2), SoundLayout.Mode.GOMO, ROOT2, true)
	var a: Dictionary = {}
	for x: Dictionary in again["actions"]:
		if x["slot"] == "click.sound#0":
			a = x
	_ok(a.get("op") == "keep" and a.get("path") == MINE + "/sound.mp3", "a sound the user moved stays there (%s %s)" % [a.get("op"), a.get("path")])
	await InstallApplier.apply(self, again, "g", ROOT2)
	var third := InstallPlanner.plan(m, InstallCatalog.load_catalog(ROOT2), SoundLayout.Mode.SCENE_FOLDER, ROOT, true)
	var moved := false
	for x: Dictionary in third["actions"]:
		moved = moved or (x["slot"] == "click.sound#0" and x["op"] != "keep")
	_ok(not moved, "not even changing the mode and folder moves it")


## Only the fixed test folder, inside the test project.
func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir + "/" + d)
	DirAccess.remove_absolute(dir)


func _ok(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
	_lines.append(("ok   " if cond else "FALHA ") + what)
