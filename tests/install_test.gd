extends SceneTree

## Sound installation: the rules that protect the user's project. Runs in a test project
## (tests/run.sh), with a fake "site" that serves local WAVs. Each case states what it guarantees.

const InstallApplier := preload("res://addons/gomo_sounds/core/install_applier.gd")
const InstallCatalog := preload("res://addons/gomo_sounds/core/install_catalog.gd")
const InstallPlanner := preload("res://addons/gomo_sounds/core/install_planner.gd")
const InstallSummary := preload("res://addons/gomo_sounds/core/install_summary.gd")
const SafeFileName := preload("res://addons/gomo_sounds/core/safe_file_name.gd")
const SceneRegistrar := preload("res://addons/gomo_sounds/core/scene_registrar.gd")
const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SoundLayout := preload("res://addons/gomo_sounds/core/sound_layout.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
## The SfxLibrary autoload via its script (under -s the autoload doesn't exist yet when the test compiles).
const SfxLibraryScript := preload("res://addons/gomo_sounds/runtime/sfx_library.gd")
## The public API belongs to the autoload (instance methods); the test uses a standalone instance. The state
## (loaded catalog) is static, so it's the same one the autoload would see.
var SfxLibrary = SfxLibraryScript.new()

const ROOT := "res://gomosounds"
const CUSTOM := "res://audio/my_sounds"
const SCENE := "res://units/spider/spider.tscn"
const URLS := {"u_fire": "res://samples/fire.wav", "u_rain": "res://samples/rain.wav", "u_forest": "res://samples/forest.wav", "u_rain2": "res://samples/rain.wav"}

var _fails := 0
var _checks := 0
var _fail_url := ""
var _downloads := 0


## The "site": returns the local file for the URL; `_fail_url` simulates the network going down.
func get_bytes(url: String) -> SfxApi.Result:
	var r := SfxApi.Result.new()
	_downloads += 1
	if url == _fail_url:
		r.error = "rede"
		return r
	r.ok = true
	r.bytes = FileAccess.get_file_as_bytes(URLS[url])
	if url == "u_rain2":
		r.bytes.append(7)
	return r


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset()
	_test_safe_names()
	_test_sync_summary()
	_test_legacy_settings_migrate()
	await _test_first_install()
	await _test_user_edit_is_kept()
	await _test_update_in_place()
	await _test_scene_folder_never_overwrites()
	await _test_removal_only_intact()
	await _test_network_failure_writes_nothing()
	await _test_custom_location()
	_test_legacy_manifest()
	await _test_inherited_is_one_file()
	await _test_old_slots_migrate()
	await _test_second_variation_keeps_first()
	await _test_scene_renamed_stays()
	await _test_edited_can_take_site_version()
	_test_prune_empty_dirs()
	_test_version_survives_missing_cfg()
	await _test_music_bpm()
	print("\n%d checks, %d failures" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


## Project from the old plugin (settings under sfx_studio/...): moves to the new name without losing anything.
func _test_legacy_settings_migrate() -> void:
	ProjectSettings.set_setting("sfx_studio/game_id", "old-game")
	ProjectSettings.set_setting("gomo_sounds/layout", "custom")
	ProjectSettings.set_setting("sfx_studio/layout", "gomo")
	SfxSettings.migrate_legacy()
	_eq(SfxSettings.game_id(), "old-game", "the game linked in the old plugin stays linked")
	_eq(SfxSettings.layout(), "custom", "the new name, if it already exists, wins over the old one")
	_ok(not ProjectSettings.has_setting("sfx_studio/game_id"), "the old setting is removed")
	ProjectSettings.set_setting("gomo_sounds/game_id", null)
	ProjectSettings.set_setting("gomo_sounds/layout", null)


func _test_sync_summary() -> void:
	var ok := SceneRegistrar.summary({"created": 2, "updated": 1, "skipped": 0, "inbox_max": 2000})
	_ok(not ok.contains("2000"), "a normal sync does not mention a full Inbox")
	var full := SceneRegistrar.summary({"created": 1, "updated": 3, "skipped": 5, "inbox_max": 2000})
	_ok(full.contains("2000") and full.contains("5"), "a full Inbox states the limit and how many were left out")


func _test_safe_names() -> void:
	_eq(SafeFileName.slug("Construção Concluída!"), "construcao_concluida", "no accents, lowercase")
	_eq(SafeFileName.slug("CON"), "con_", "reserved Windows name")
	_eq(SafeFileName.slug("   "), "sound", "empty falls back to the default")
	_ok(SafeFileName.slug("剣士") != SafeFileName.slug("魔法使い") and SafeFileName.slug("剣士").begins_with("sound_"), "names without Latin letters do not collide")
	_ok(SafeFileName.slug("a".repeat(200)).length() <= SafeFileName.MAX_LEN, "short name")


func _test_first_install() -> void:
	var plan := await _install(_manifest(), SoundLayout.Mode.GOMO)
	_eq(InstallPlanner.counts(plan).get("new", 0), 4, "1st install: 4 new")
	_ok(InstallPlanner.needs_confirmation(plan), "1st install asks for confirmation")
	_ok(FileAccess.file_exists(ROOT + "/spider/attack.wav"), "Gomo folder: by entity")
	_ok(FileAccess.file_exists(ROOT + "/ambience/wind.wav"), "folder sound at the root")
	_ok(FileAccess.file_exists(ROOT + "/con_/death.wav"), "folder with a reserved name becomes con_")
	_ok(FileAccess.file_exists(ROOT + "/gomo_sounds.tres"), "catalog written")
	var again := InstallPlanner.plan(_manifest(), InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT, true)
	_ok(not InstallSummary.has_changes(again), "running again: nothing changes")
	SfxLibrary.reload_catalog()
	_ok(SfxLibrary.has_sound("spider.attack"), "the game finds the sound by key")
	_eq(SfxLibraryScript._by_scene_event.get(SCENE + "|attack", []).size(), 2, "the game finds it by scene + event")
	_ok(SfxLibraryScript._norm("Seleção ") == SfxLibraryScript._norm("Selecao"), "an event with or without accents is the same")
	var copy := Node.new()
	copy.scene_file_path = "res://arena/arena_spider.tscn"
	_ok(not SfxLibrary.has_event(copy, "Attack"), "a copy of the scene has no sounds of its own")
	SfxLibrary.alias_scene(copy.scene_file_path, SCENE)
	SfxLibrary.reload_catalog()
	_ok(SfxLibrary.has_event(copy, "Attack"), "alias_scene: the copy plays the original's sounds (survives reload)")
	SfxLibrary.alias_scene(copy.scene_file_path, "")
	_ok(not SfxLibrary.has_event(copy, "Attack"), "alias_scene with an empty target removes the alias")
	copy.free()
	var wav := AudioStreamWAV.new()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var once := wav.duplicate() as AudioStreamWAV
	SfxLibraryScript._make_one_shot(once)
	_ok(not SfxLibraryScript._is_looping(once), "a one-shot sound (play/play_event) never loops")
	_ok(SfxLibraryScript._is_looping(wav), "and the shared resource stays as it was")


func _test_user_edit_is_kept() -> void:
	var path := ROOT + "/spider/attack.wav"
	_append_byte(path)
	var sha := FileAccess.get_sha256(path)
	var plan := await _install(_manifest({"f1": "f1b"}), SoundLayout.Mode.GOMO)
	_eq(_op(plan, "spider.attack#0"), "edited", "file edited by the user: marked as theirs")
	_eq(FileAccess.get_sha256(path), sha, "a new version from the site does NOT overwrite the edited one")


func _test_update_in_place() -> void:
	var path := ROOT + "/spider/attack_2.wav"
	var before := FileAccess.get_sha256(path)
	var plan := await _install(_manifest({"f1": "f1b", "f2": "f2b"}, {"u_rain": "u_rain2"}), SoundLayout.Mode.GOMO)
	_eq(_op(plan, "spider.attack#1"), "update", "audio edited on the site: updates in the same place")
	_ok(FileAccess.get_sha256(path) != before, "new content written")
	_ok(not FileAccess.file_exists(path + InstallApplier.TMP_SUFFIX), "no leftover temp file")


func _test_scene_folder_never_overwrites() -> void:
	# A file OF THE USER exactly where the new mode wants to put the sound (different case on purpose).
	var theirs := "res://units/spider/sounds/Spider_Attack_2.wav"
	_write(theirs, PackedByteArray([1, 2, 3]))
	var plan := await _install(_manifest({"f1": "f1b", "f2": "f2b"}, {"u_rain": "u_rain2"}), SoundLayout.Mode.SCENE_FOLDER)
	_eq(FileAccess.get_file_as_bytes(theirs), PackedByteArray([1, 2, 3]), "the user's file is intact")
	var moved := _action(plan, "spider.attack#1")
	_eq(moved.get("op"), "move", "mode changed: the plugin's file moves")
	_eq(moved.get("path"), "res://units/spider/sounds/spider_attack_2_2.wav", "name taken: becomes _2")
	_ok(FileAccess.file_exists(moved.get("path", "")), "actually moved")
	_eq(_op(plan, "spider.attack#0"), "edited", "an edited file stays put")
	_ok(FileAccess.file_exists(ROOT + "/ambience/wind.wav"), "a sound without a scene stays at the root")
	_ok(InstallPlanner.needs_confirmation(plan), "moving asks for confirmation")


func _test_removal_only_intact() -> void:
	var m := _manifest({"f1": "f1b", "f2": "f2b"}, {"u_rain": "u_rain2"})
	m["sounds"] = (m["sounds"] as Array).filter(func(s: Dictionary) -> bool: return s["key"] not in ["con.death", "spider.attack"])
	var plan := await _install(m, SoundLayout.Mode.SCENE_FOLDER)
	_eq(_op(plan, "con.death#0"), "remove", "removed from the site and untouched: deleted")
	_ok(not FileAccess.file_exists(ROOT + "/con_/death.wav"), "deleted")
	_eq(_op(plan, "spider.attack#0"), "left_edited", "removed from the site but edited: kept")
	_ok(FileAccess.file_exists(ROOT + "/spider/attack.wav"), "the edited file stays in the project")


func _test_network_failure_writes_nothing() -> void:
	var m := _manifest()
	m["sounds"] = [_sound("new.steps", "New", "", "Steps", ["u_fire", "u_forest"], ["n1", "n2"])]
	_fail_url = "u_forest"
	var catalog := InstallCatalog.load_catalog(ROOT)
	var plan := InstallPlanner.plan(m, catalog, SoundLayout.Mode.GOMO, ROOT, false)
	var r: Dictionary = await InstallApplier.apply(self, plan, "g", ROOT)
	_fail_url = ""
	_ok(r["error"] != "", "network down: error")
	_ok(not FileAccess.file_exists(ROOT + "/new/steps.wav"), "nothing half-written")


## Custom location: the folder comes from the project; changing it moves the sounds AND the catalog there, and the
## old folder is left without a catalog (a single source of truth). Stale settings (the command line doesn't write
## project.godot) must not make the plugin forget its own sounds.
func _test_custom_location() -> void:
	_eq(SfxSettings.target_root(), ROOT, "default: Gomo folder")
	ProjectSettings.set_setting(SfxSettings.KEY_LAYOUT, "custom")
	ProjectSettings.set_setting(SfxSettings.KEY_CUSTOM_DIR, "res://addons/x")
	_eq(SfxSettings.target_root(), ROOT, "forbidden folder: stays in the Gomo one")
	ProjectSettings.set_setting(SfxSettings.KEY_CUSTOM_DIR, CUSTOM + "/")
	_eq(SfxSettings.target_root(), CUSTOM, "custom location applies")
	ProjectSettings.set_setting(SfxSettings.KEY_INSTALL_DIR, ROOT)
	var m := _manifest()
	m["sounds"] = [(m["sounds"] as Array)[1]]
	var plan := InstallPlanner.plan(m, InstallCatalog.load_catalog(SfxSettings.install_dir()), SoundLayout.Mode.CUSTOM, CUSTOM, false)
	_eq(_op(plan, "@ambience.wind#0"), "move", "folder changed: the sound goes along")
	var r: Dictionary = await InstallApplier.apply(self, plan, "g", CUSTOM)
	InstallCatalog.retire(ROOT)
	_ok(r["saved"] and FileAccess.file_exists(CUSTOM + "/ambience/wind.wav"), "sound in the new folder")
	_ok(FileAccess.file_exists(CUSTOM + "/gomo_sounds.tres") and not FileAccess.file_exists(ROOT + "/gomo_sounds.tres"), "catalog moved folders")
	_eq(SfxSettings.install_dir(), CUSTOM, "stale setting: finds the catalog where it is")
	var again := InstallPlanner.plan(m, InstallCatalog.load_catalog(SfxSettings.install_dir()), SoundLayout.Mode.CUSTOM, CUSTOM, false)
	_eq(_op(again, "@ambience.wind#0"), "keep", "and duplicates nothing")
	for k: String in [SfxSettings.KEY_LAYOUT, SfxSettings.KEY_CUSTOM_DIR, SfxSettings.KEY_INSTALL_DIR]:
		ProjectSettings.set_setting(k, null)


func _test_legacy_manifest() -> void:
	var dir := "res://audio/sfx_studio"
	_write(dir + "/sounds/old/jump.wav", FileAccess.get_file_as_bytes(URLS["u_fire"]))
	var f := FileAccess.open(dir + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"sounds": [{"key": "old.jump", "files": ["sounds/old/jump.wav"], "fileIds": ["v1"]}]}))
	f.close()
	var catalog := InstallCatalog.load_catalog(dir)
	_eq(catalog.files.size(), 1, "an old install becomes a catalog")
	_eq(catalog.files[0]["slot"], "old.jump#0", "with the same identity")


## Folder sound inherited by several entities (+ the folder's own entry): ONE file, and every
## key plays it.
func _test_inherited_is_one_file() -> void:
	_reset()
	var m := {"sounds": [
		_shared("@buildings.ready", "Buildings", ""), _shared("house.ready", "House", "Buildings"), _shared("tower.ready", "Tower", "Buildings"),
	]}
	var plan := await _install(m, SoundLayout.Mode.GOMO)
	_eq(InstallPlanner.counts(plan).get("new", 0), 1, "inherited: 1 file, not 3")
	_ok(not FileAccess.file_exists(ROOT + "/buildings/ready_2.wav"), "no _2 copy")
	SfxLibrary.reload_catalog()
	_ok(SfxLibrary.has_sound("house.ready") and SfxLibrary.has_sound("tower.ready"), "every key plays")


## Install made with the old identity (key#n) and with COPIES of the inherited sound: migrates without downloading
## again and deletes the copies.
func _test_old_slots_migrate() -> void:
	var catalog := InstallCatalog.load_catalog(ROOT)
	for e: Dictionary in catalog.files:
		e["slot"] = "house.ready#0"
	var copy := ROOT + "/buildings/ready_2.wav"
	_write(copy, FileAccess.get_file_as_bytes(ROOT + "/buildings/ready.wav"))
	catalog.files.append({"slot": "tower.ready#0", "path": copy, "uid": "", "pinned": false, "sha256": FileAccess.get_sha256(copy), "version": "fp", "loop": false})
	InstallCatalog.save(catalog, ROOT)
	var m := {"sounds": [_shared("@buildings.ready", "Buildings", ""), _shared("house.ready", "House", "Buildings"), _shared("tower.ready", "Tower", "Buildings")]}
	var plan := await _install(m, SoundLayout.Mode.GOMO)
	_eq(InstallPlanner.counts(plan).get("keep", 0), 1, "the original stays (no new download)")
	_eq(InstallPlanner.counts(plan).get("remove", 0), 1, "the copy is removed")
	_ok(not FileAccess.file_exists(copy), "copy deleted")


## Choosing a 2nd variation on the site doesn't rename the 1st (scenes that use attack.wav don't break).
func _test_second_variation_keeps_first() -> void:
	_reset()
	var one := {"sounds": [_sound("spider.attack", "Spider", SCENE, "Attack", ["u_fire"], ["f1"])]}
	await _install(one, SoundLayout.Mode.GOMO)
	var plan := await _install(_manifest(), SoundLayout.Mode.GOMO)
	_eq(_op(plan, "spider.attack#0"), "keep", "the 1st stays where it was")
	_ok(FileAccess.file_exists(ROOT + "/spider/attack_2.wav"), "the 2nd arrives as _2")


## Scene mode, the scene was renamed in Godot and the site still has the old path: the sound stays
## next to it.
func _test_scene_renamed_stays() -> void:
	_reset()
	var plan := await _install(_manifest(), SoundLayout.Mode.SCENE_FOLDER)
	var path: String = _action(plan, "spider.attack#0")["path"]
	DirAccess.rename_absolute(SCENE, "res://units/spider/spider_new.tscn")
	var again := await _install(_manifest(), SoundLayout.Mode.SCENE_FOLDER)
	_eq(_action(again, "spider.attack#0").get("path"), path, "scene renamed: the sound stays")
	_eq(_op(again, "spider.attack#0"), "keep", "and nothing changes")


## Edited by the user + new version on the site: ask, and only replace if they opt in.
func _test_edited_can_take_site_version() -> void:
	_reset()
	await _install(_manifest(), SoundLayout.Mode.GOMO)
	var path := ROOT + "/spider/attack.wav"
	_append_byte(path)
	var plan := InstallPlanner.plan(_manifest({"f1": "f1-novo"}), InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT, true)
	_eq(InstallPlanner.outdated_edits(plan), 1, "edited with a new version available: offers to replace")
	_ok(InstallPlanner.needs_confirmation(plan), "and asks")
	InstallPlanner.accept_site_versions(plan)
	await InstallApplier.apply(self, plan, "g", ROOT)
	_eq(FileAccess.get_file_as_bytes(path), FileAccess.get_file_as_bytes(URLS["u_fire"]), "ticked: now it is the site's version")
	var after := InstallPlanner.plan(_manifest({"f1": "f1-novo"}), InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT, true)
	_eq(_op(after, "spider.attack#0"), "keep", "and it belongs to the plugin again")


func _test_prune_empty_dirs() -> void:
	_write("res://units/empty/sub/x.wav", PackedByteArray([1]))
	_write("res://units/empty/outro.txt", PackedByteArray([1]))
	DirAccess.remove_absolute("res://units/empty/sub/x.wav")
	InstallApplier._prune_empty_dirs("res://units/empty/sub")
	_ok(not DirAccess.dir_exists_absolute("res://units/empty/sub"), "empty folder is removed")
	_ok(DirAccess.dir_exists_absolute("res://units/empty"), "folder with things inside stays")


## A folder sound (same eventId and same path for everyone that inherits it).
func _shared(key: String, entity: String, inherited: String) -> Dictionary:
	var s := _sound(key, entity, "", "Pronto", ["u_fire"], ["fp"], "sounds/_pastas/buildings")
	s["eventId"] = "folder-event"
	s["inheritedFrom"] = inherited if inherited != "" else null
	return s


## The version is kept in memory: deleting plugin.cfg (reinstall with the editor open) doesn't turn into "0.0.0".
func _test_version_survives_missing_cfg() -> void:
	var version := SfxSettings.plugin_version()
	_ok(version != "0.0.0" and version != "", "version read from plugin.cfg")
	var real := ProjectSettings.globalize_path("res://addons/gomo_sounds/plugin.cfg")
	var backup := real + ".bak"
	DirAccess.rename_absolute(real, backup)
	_eq(SfxSettings.plugin_version(), version, "without plugin.cfg on disk, the version stays the same")
	DirAccess.rename_absolute(backup, real)


## The tempo of each music file reaches the catalog (games sync visuals to the beat); a catalog from before
## the field gets it on the next Install without downloading anything.
func _test_music_bpm() -> void:
	var dir := "res://musica_bpm"
	var theme := _sound("@music.theme", "Music", "", "Theme", ["u_fire", "u_rain"], ["m1", "m2"], "sounds/_pastas/music")
	theme["bpms"] = [128, null]
	var site := {"sounds": [theme, _sound("step.step", "Step", "", "Step", ["u_forest"], ["p1"], "sounds/step")]}
	var plan := InstallPlanner.plan(site, InstallCatalog.load_catalog(dir), SoundLayout.Mode.GOMO, dir, true)
	await InstallApplier.apply(self, plan, "g", dir)
	var bpm := _bpms(dir)
	_eq(bpm.get("m1"), 128.0, "music: the site's bpm goes to the catalog (float)")
	_ok(bpm.has("m2") and bpm["m2"] == null, "music without a tempo: bpm null")
	_ok(bpm.has("p1") and bpm["p1"] == null, "a sound that is not music (site without bpms): bpm null")
	_ok(not InstallSummary.has_changes(InstallPlanner.plan(site, InstallCatalog.load_catalog(dir), SoundLayout.Mode.GOMO, dir, true)), "same bpm: running again changes nothing")

	# Catalog written by 0.6.x: no bpm field. Reads as unknown, and the next Install fills it in, writing no audio.
	var old := InstallCatalog.load_catalog(dir)
	for e: Dictionary in old.files:
		e.erase("bpm")
	InstallCatalog.save(old, dir)
	var again := InstallPlanner.plan(site, InstallCatalog.load_catalog(dir), SoundLayout.Mode.GOMO, dir, true)
	_eq(_op(again, InstallCatalog.slot_for(theme, 0)), "keep", "old catalog: the file stays")
	_ok(InstallSummary.has_changes(again), "old catalog without bpm: Install has something to write")
	var downloads := _downloads
	await InstallApplier.apply(self, again, "g", dir)
	_eq(_bpms(dir).get("m1"), 128.0, "old catalog gets the bpm")
	_eq(_downloads, downloads, "without downloading the audio again")
	_remove_tree(dir)


## version (fileId) → bpm, from the catalog on disk.
func _bpms(dir: String) -> Dictionary:
	var out := {}
	for e: Dictionary in InstallCatalog.load_catalog(dir).files:
		out[str(e.get("version", ""))] = e.get("bpm")
	return out


# --- helpers ---

func _install(manifest: Dictionary, mode: SoundLayout.Mode) -> Dictionary:
	var plan := InstallPlanner.plan(manifest, InstallCatalog.load_catalog(ROOT), mode, ROOT, true)
	var r: Dictionary = await InstallApplier.apply(self, plan, "g", ROOT)
	_eq(r["error"], "", "installed without errors")
	return plan


func _manifest(versions := {}, urls := {}) -> Dictionary:
	var v := func(id: String) -> String: return versions.get(id, id)
	var u := func(id: String) -> String: return urls.get(id, id)
	return {"sounds": [
		_sound("spider.attack", "Spider", SCENE, "Attack", [u.call("u_fire"), u.call("u_rain")], [v.call("f1"), v.call("f2")]),
		_sound("@ambience.wind", "Ambience", "", "Wind", [u.call("u_forest")], [v.call("f3")], "sounds/_pastas/ambience", [true]),
		_sound("con.death", "CON", "", "Death", [u.call("u_fire")], [v.call("f4")], "sounds/con"),
	]}


func _sound(key: String, entity: String, ext_id: String, event: String, files: Array, ids: Array, dir := "", loops: Array = []) -> Dictionary:
	var base := dir if dir != "" else "sounds/" + entity.to_lower()
	var paths: Array = []
	for i in files.size():
		paths.append("%s/%s%s.wav" % [base, event.to_lower(), "_%d" % (i + 1) if files.size() > 1 else ""])
	return {"key": key, "entity": entity, "externalId": ext_id if ext_id != "" else null, "event": event,
		"inheritedFrom": null, "files": files, "paths": paths, "fileIds": ids, "loops": loops}


func _reset() -> void:
	for dir: String in [ROOT, "res://gomo_sounds", "res://units", "res://audio", "res://musica_bpm"]:
		_remove_tree(dir)
	_write(SCENE, "[gd_scene format=3]\n\n[node name=\"Spider\" type=\"Node3D\"]\n".to_utf8_buffer())


## Only inside the test project, and only for the fixed folders above.
func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir + "/" + d)
	DirAccess.remove_absolute(dir)


func _write(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _append_byte(path: String) -> void:
	var data := FileAccess.get_file_as_bytes(path)
	data.append(0)
	_write(path, data)


func _action(plan: Dictionary, slot: String) -> Dictionary:
	for a: Dictionary in plan["actions"]:
		if a["slot"] == slot:
			return a
	return {}


func _op(plan: Dictionary, slot: String) -> String:
	return str(_action(plan, slot).get("op", "(none)"))


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print(("  ok   " if cond else "  FAIL  ") + what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what if got == want else "%s (got %s, expected %s)" % [what, got, want])
