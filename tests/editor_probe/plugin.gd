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
		{"key": "chuva.loop", "entity": "Chuva", "externalId": null, "event": "Loop", "inheritedFrom": null,
			"files": ["res://samples/rain.wav"], "paths": ["sounds/chuva/loop.wav"], "fileIds": ["r1"], "loops": [true]},
		{"key": "clique.som", "entity": "Clique", "externalId": null, "event": "Som", "inheritedFrom": null,
			"files": ["res://samples/click.mp3"], "paths": ["sounds/clique/som.mp3"], "fileIds": ["c1"], "loops": [false]},
	]}
	var plan := InstallPlanner.plan(m, InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT, true)
	var r: Dictionary = await InstallApplier.apply(self, plan, "g", ROOT)
	_ok(r["error"] == "", "instalou no editor")
	var cfg := ConfigFile.new()
	_ok(cfg.load(ROOT + "/chuva/loop.wav.import") == OK, "Godot importou o som")
	_ok(cfg.get_value("params", "edit/loop_mode", -1) == 2, "loop ligado na importação")
	var catalog := InstallCatalog.load_catalog(ROOT)
	var uids := 0
	for e: Dictionary in catalog.files:
		uids += 1 if str(e["uid"]).begins_with("uid://") else 0
	_ok(uids == 2, "uid anotado no catálogo (%d de 2)" % uids)
	var stream := load(ROOT + "/chuva/loop.wav") as AudioStreamWAV
	_ok(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "o som carrega em loop")
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
	_ok(icon != null and icon.get_width() == 64 and orange > 300, "ícone da tangerina desenhado (%d px laranja)" % orange)
	var dock: Control = load("res://addons/gomo_sounds/ui/sfx_dock.gd").new()
	EditorInterface.get_base_control().add_child(dock)
	await get_tree().process_frame
	_ok(dock.is_inside_tree(), "painel abre")
	dock.queue_free()
	_lines.append("%d falhas" % _fails)
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
	cfg.load(ROOT + "/chuva/loop.wav.import")
	cfg.set_value("params", "edit/loop_mode", 0)
	cfg.save(ROOT + "/chuva/loop.wav.import")
	var fixed: bool = await InstallImport.repair(catalog)
	var uids := 0
	for e: Dictionary in catalog.get("files"):
		uids += 1 if str(e["uid"]).begins_with("uid://") else 0
	cfg.load(ROOT + "/chuva/loop.wav.import")
	_ok(fixed and uids == 2 and cfg.get_value("params", "edit/loop_mode", -1) == 2, "reparo: uid e loop de volta (%d de 2)" % uids)


## (a) the plugin changes the folder: the uid (and the scenes using the sound) survives; (b) the user moves a
## sound in Godot: on the next install it stays where they put it.
func _test_moves(m: Dictionary, efs: EditorFileSystem) -> void:
	var uid_before := ResourceLoader.get_resource_uid(ROOT + "/chuva/loop.wav")
	var plan := InstallPlanner.plan(m, InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT2, true)
	await InstallApplier.apply(self, plan, "g", ROOT2)
	_ok(FileAccess.file_exists(ROOT2 + "/chuva/loop.wav") and not FileAccess.file_exists(ROOT + "/chuva/loop.wav"), "pasta nova: o som mudou de lugar")
	_ok(ResourceLoader.get_resource_uid(ROOT2 + "/chuva/loop.wav") == uid_before, "mudou de lugar com o mesmo uid")
	DirAccess.make_dir_recursive_absolute(MINE)
	DirAccess.rename_absolute(ROOT2 + "/clique/som.mp3", MINE + "/som.mp3")
	DirAccess.rename_absolute(ROOT2 + "/clique/som.mp3.import", MINE + "/som.mp3.import")
	efs.scan()
	await get_tree().process_frame
	while efs.is_scanning():
		await get_tree().process_frame
	var uid := ResourceLoader.get_resource_uid(MINE + "/som.mp3")
	for i in 600:
		await get_tree().process_frame
		if ResourceUID.has_id(uid) and ResourceUID.get_id_path(uid) == MINE + "/som.mp3":
			break
	var again := InstallPlanner.plan(m, InstallCatalog.load_catalog(ROOT2), SoundLayout.Mode.GOMO, ROOT2, true)
	var a: Dictionary = {}
	for x: Dictionary in again["actions"]:
		if x["slot"] == "clique.som#0":
			a = x
	_ok(a.get("op") == "keep" and a.get("path") == MINE + "/som.mp3", "som que a pessoa moveu fica lá (%s %s)" % [a.get("op"), a.get("path")])
	await InstallApplier.apply(self, again, "g", ROOT2)
	var third := InstallPlanner.plan(m, InstallCatalog.load_catalog(ROOT2), SoundLayout.Mode.SCENE_FOLDER, ROOT, true)
	var moved := false
	for x: Dictionary in third["actions"]:
		moved = moved or (x["slot"] == "clique.som#0" and x["op"] != "keep")
	_ok(not moved, "nem trocando o modo e a pasta ele sai de lá")


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
