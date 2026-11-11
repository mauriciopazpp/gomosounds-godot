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
const CUSTOM := "res://audio/meus_sons"
const SCENE := "res://units/aranha/aranha.tscn"
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
	print("\n%d checagens, %d falhas" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


## Project from the old plugin (settings under sfx_studio/...): moves to the new name without losing anything.
func _test_legacy_settings_migrate() -> void:
	ProjectSettings.set_setting("sfx_studio/game_id", "jogo-antigo")
	ProjectSettings.set_setting("gomo_sounds/layout", "custom")
	ProjectSettings.set_setting("sfx_studio/layout", "gomo")
	SfxSettings.migrate_legacy()
	_eq(SfxSettings.game_id(), "jogo-antigo", "o jogo vinculado no plugin antigo continua vinculado")
	_eq(SfxSettings.layout(), "custom", "o nome novo, se já existe, vence o antigo")
	_ok(not ProjectSettings.has_setting("sfx_studio/game_id"), "a configuração antiga sai")
	ProjectSettings.set_setting("gomo_sounds/game_id", null)
	ProjectSettings.set_setting("gomo_sounds/layout", null)


func _test_sync_summary() -> void:
	var ok := SceneRegistrar.summary({"created": 2, "updated": 1, "skipped": 0, "inbox_max": 2000})
	_ok(not ok.contains("2000"), "envio normal não fala de Entrada cheia")
	var full := SceneRegistrar.summary({"created": 1, "updated": 3, "skipped": 5, "inbox_max": 2000})
	_ok(full.contains("2000") and full.contains("5"), "Entrada cheia diz o teto e quantas ficaram de fora")


func _test_safe_names() -> void:
	_eq(SafeFileName.slug("Construção Concluída!"), "construcao_concluida", "sem acento, minúsculo")
	_eq(SafeFileName.slug("CON"), "con_", "nome reservado do Windows")
	_eq(SafeFileName.slug("   "), "som", "vazio cai no padrão")
	_ok(SafeFileName.slug("剣士") != SafeFileName.slug("魔法使い") and SafeFileName.slug("剣士").begins_with("som_"), "nomes sem letra latina não colidem")
	_ok(SafeFileName.slug("a".repeat(200)).length() <= SafeFileName.MAX_LEN, "nome curto")


func _test_first_install() -> void:
	var plan := await _install(_manifest(), SoundLayout.Mode.GOMO)
	_eq(InstallPlanner.counts(plan).get("new", 0), 4, "1ª instalação: 4 novos")
	_ok(InstallPlanner.needs_confirmation(plan), "1ª instalação pede confirmação")
	_ok(FileAccess.file_exists(ROOT + "/aranha/ataque.wav"), "pasta do Gomo: por entidade")
	_ok(FileAccess.file_exists(ROOT + "/ambience/vento.wav"), "som de pasta na raiz")
	_ok(FileAccess.file_exists(ROOT + "/con_/morte.wav"), "pasta com nome reservado vira con_")
	_ok(FileAccess.file_exists(ROOT + "/gomo_sounds.tres"), "catálogo gravado")
	var again := InstallPlanner.plan(_manifest(), InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT, true)
	_ok(not InstallSummary.has_changes(again), "rodar de novo: nada muda")
	SfxLibrary.reload_catalog()
	_ok(SfxLibrary.has_sound("aranha.ataque"), "o jogo acha o som pela chave")
	_eq(SfxLibraryScript._by_scene_event.get(SCENE + "|ataque", []).size(), 2, "o jogo acha pela cena + evento")
	_ok(SfxLibraryScript._norm("Seleção ") == SfxLibraryScript._norm("Selecao"), "evento com ou sem acento é o mesmo")
	var wav := AudioStreamWAV.new()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var once := wav.duplicate() as AudioStreamWAV
	SfxLibraryScript._make_one_shot(once)
	_ok(not SfxLibraryScript._is_looping(once), "som de uma vez (play/play_event) nunca fica em loop")
	_ok(SfxLibraryScript._is_looping(wav), "e o recurso compartilhado continua como estava")


func _test_user_edit_is_kept() -> void:
	var path := ROOT + "/aranha/ataque.wav"
	_append_byte(path)
	var sha := FileAccess.get_sha256(path)
	var plan := await _install(_manifest({"f1": "f1b"}), SoundLayout.Mode.GOMO)
	_eq(_op(plan, "aranha.ataque#0"), "edited", "arquivo editado pela pessoa: marcado como dela")
	_eq(FileAccess.get_sha256(path), sha, "versão nova do site NÃO sobrescreve a editada")


func _test_update_in_place() -> void:
	var path := ROOT + "/aranha/ataque_2.wav"
	var before := FileAccess.get_sha256(path)
	var plan := await _install(_manifest({"f1": "f1b", "f2": "f2b"}, {"u_rain": "u_rain2"}), SoundLayout.Mode.GOMO)
	_eq(_op(plan, "aranha.ataque#1"), "update", "áudio editado no site: atualiza no mesmo lugar")
	_ok(FileAccess.get_sha256(path) != before, "conteúdo novo gravado")
	_ok(not FileAccess.file_exists(path + InstallApplier.TMP_SUFFIX), "sem temporário largado")


func _test_scene_folder_never_overwrites() -> void:
	# A file OF THE USER exactly where the new mode wants to put the sound (different case on purpose).
	var theirs := "res://units/aranha/sounds/Aranha_Ataque_2.wav"
	_write(theirs, PackedByteArray([1, 2, 3]))
	var plan := await _install(_manifest({"f1": "f1b", "f2": "f2b"}, {"u_rain": "u_rain2"}), SoundLayout.Mode.SCENE_FOLDER)
	_eq(FileAccess.get_file_as_bytes(theirs), PackedByteArray([1, 2, 3]), "arquivo da pessoa intacto")
	var moved := _action(plan, "aranha.ataque#1")
	_eq(moved.get("op"), "move", "mudou o modo: o arquivo do plugin muda de lugar")
	_eq(moved.get("path"), "res://units/aranha/sounds/aranha_ataque_2_2.wav", "nome ocupado: vira _2")
	_ok(FileAccess.file_exists(moved.get("path", "")), "movido de verdade")
	_eq(_op(plan, "aranha.ataque#0"), "edited", "editado não sai do lugar")
	_ok(FileAccess.file_exists(ROOT + "/ambience/vento.wav"), "som sem cena fica na raiz")
	_ok(InstallPlanner.needs_confirmation(plan), "mudar de lugar pede confirmação")


func _test_removal_only_intact() -> void:
	var m := _manifest({"f1": "f1b", "f2": "f2b"}, {"u_rain": "u_rain2"})
	m["sounds"] = (m["sounds"] as Array).filter(func(s: Dictionary) -> bool: return s["key"] not in ["con.morte", "aranha.ataque"])
	var plan := await _install(m, SoundLayout.Mode.SCENE_FOLDER)
	_eq(_op(plan, "con.morte#0"), "remove", "saiu do site e está intacto: apaga")
	_ok(not FileAccess.file_exists(ROOT + "/con_/morte.wav"), "apagado")
	_eq(_op(plan, "aranha.ataque#0"), "left_edited", "saiu do site mas foi editado: fica")
	_ok(FileAccess.file_exists(ROOT + "/aranha/ataque.wav"), "o editado continua no projeto")


func _test_network_failure_writes_nothing() -> void:
	var m := _manifest()
	m["sounds"] = [_sound("nova.passos", "Nova", "", "Passos", ["u_fire", "u_forest"], ["n1", "n2"])]
	_fail_url = "u_forest"
	var catalog := InstallCatalog.load_catalog(ROOT)
	var plan := InstallPlanner.plan(m, catalog, SoundLayout.Mode.GOMO, ROOT, false)
	var r: Dictionary = await InstallApplier.apply(self, plan, "g", ROOT)
	_fail_url = ""
	_ok(r["error"] != "", "rede caiu: erro")
	_ok(not FileAccess.file_exists(ROOT + "/nova/passos.wav"), "nada gravado pela metade")


## Custom location: the folder comes from the project; changing it moves the sounds AND the catalog there, and the
## old folder is left without a catalog (a single source of truth). Stale settings (the command line doesn't write
## project.godot) must not make the plugin forget its own sounds.
func _test_custom_location() -> void:
	_eq(SfxSettings.target_root(), ROOT, "padrão: pasta do Gomo")
	ProjectSettings.set_setting(SfxSettings.KEY_LAYOUT, "custom")
	ProjectSettings.set_setting(SfxSettings.KEY_CUSTOM_DIR, "res://addons/x")
	_eq(SfxSettings.target_root(), ROOT, "pasta proibida: continua na do Gomo")
	ProjectSettings.set_setting(SfxSettings.KEY_CUSTOM_DIR, CUSTOM + "/")
	_eq(SfxSettings.target_root(), CUSTOM, "local personalizado vale")
	ProjectSettings.set_setting(SfxSettings.KEY_INSTALL_DIR, ROOT)
	var m := _manifest()
	m["sounds"] = [(m["sounds"] as Array)[1]]
	var plan := InstallPlanner.plan(m, InstallCatalog.load_catalog(SfxSettings.install_dir()), SoundLayout.Mode.CUSTOM, CUSTOM, false)
	_eq(_op(plan, "@ambience.vento#0"), "move", "trocou a pasta: o som vai junto")
	var r: Dictionary = await InstallApplier.apply(self, plan, "g", CUSTOM)
	InstallCatalog.retire(ROOT)
	_ok(r["saved"] and FileAccess.file_exists(CUSTOM + "/ambience/vento.wav"), "som na pasta nova")
	_ok(FileAccess.file_exists(CUSTOM + "/gomo_sounds.tres") and not FileAccess.file_exists(ROOT + "/gomo_sounds.tres"), "catálogo mudou de pasta")
	_eq(SfxSettings.install_dir(), CUSTOM, "configuração atrasada: acha o catálogo onde ele está")
	var again := InstallPlanner.plan(m, InstallCatalog.load_catalog(SfxSettings.install_dir()), SoundLayout.Mode.CUSTOM, CUSTOM, false)
	_eq(_op(again, "@ambience.vento#0"), "keep", "e não duplica nada")
	for k: String in [SfxSettings.KEY_LAYOUT, SfxSettings.KEY_CUSTOM_DIR, SfxSettings.KEY_INSTALL_DIR]:
		ProjectSettings.set_setting(k, null)


func _test_legacy_manifest() -> void:
	var dir := "res://audio/sfx_studio"
	_write(dir + "/sounds/velho/pulo.wav", FileAccess.get_file_as_bytes(URLS["u_fire"]))
	var f := FileAccess.open(dir + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"sounds": [{"key": "velho.pulo", "files": ["sounds/velho/pulo.wav"], "fileIds": ["v1"]}]}))
	f.close()
	var catalog := InstallCatalog.load_catalog(dir)
	_eq(catalog.files.size(), 1, "instalação antiga vira catálogo")
	_eq(catalog.files[0]["slot"], "velho.pulo#0", "com a mesma identidade")


## Folder sound inherited by several entities (+ the folder's own entry): ONE file, and every
## key plays it.
func _test_inherited_is_one_file() -> void:
	_reset()
	var m := {"sounds": [
		_shared("@buildings.pronto", "Buildings", ""), _shared("casa.pronto", "Casa", "Buildings"), _shared("torre.pronto", "Torre", "Buildings"),
	]}
	var plan := await _install(m, SoundLayout.Mode.GOMO)
	_eq(InstallPlanner.counts(plan).get("new", 0), 1, "herdado: 1 arquivo, não 3")
	_ok(not FileAccess.file_exists(ROOT + "/buildings/pronto_2.wav"), "sem cópia _2")
	SfxLibrary.reload_catalog()
	_ok(SfxLibrary.has_sound("casa.pronto") and SfxLibrary.has_sound("torre.pronto"), "todas as chaves tocam")


## Install made with the old identity (key#n) and with COPIES of the inherited sound: migrates without downloading
## again and deletes the copies.
func _test_old_slots_migrate() -> void:
	var catalog := InstallCatalog.load_catalog(ROOT)
	for e: Dictionary in catalog.files:
		e["slot"] = "casa.pronto#0"
	var copy := ROOT + "/buildings/pronto_2.wav"
	_write(copy, FileAccess.get_file_as_bytes(ROOT + "/buildings/pronto.wav"))
	catalog.files.append({"slot": "torre.pronto#0", "path": copy, "uid": "", "pinned": false, "sha256": FileAccess.get_sha256(copy), "version": "fp", "loop": false})
	InstallCatalog.save(catalog, ROOT)
	var m := {"sounds": [_shared("@buildings.pronto", "Buildings", ""), _shared("casa.pronto", "Casa", "Buildings"), _shared("torre.pronto", "Torre", "Buildings")]}
	var plan := await _install(m, SoundLayout.Mode.GOMO)
	_eq(InstallPlanner.counts(plan).get("keep", 0), 1, "o original fica (sem baixar de novo)")
	_eq(InstallPlanner.counts(plan).get("remove", 0), 1, "a cópia sai")
	_ok(not FileAccess.file_exists(copy), "cópia apagada")


## Choosing a 2nd variation on the site doesn't rename the 1st (scenes that use attack.wav don't break).
func _test_second_variation_keeps_first() -> void:
	_reset()
	var one := {"sounds": [_sound("aranha.ataque", "Aranha", SCENE, "Ataque", ["u_fire"], ["f1"])]}
	await _install(one, SoundLayout.Mode.GOMO)
	var plan := await _install(_manifest(), SoundLayout.Mode.GOMO)
	_eq(_op(plan, "aranha.ataque#0"), "keep", "a 1ª fica onde estava")
	_ok(FileAccess.file_exists(ROOT + "/aranha/ataque_2.wav"), "a 2ª chega como _2")


## Scene mode, the scene was renamed in Godot and the site still has the old path: the sound stays
## next to it.
func _test_scene_renamed_stays() -> void:
	_reset()
	var plan := await _install(_manifest(), SoundLayout.Mode.SCENE_FOLDER)
	var path: String = _action(plan, "aranha.ataque#0")["path"]
	DirAccess.rename_absolute(SCENE, "res://units/aranha/aranha_nova.tscn")
	var again := await _install(_manifest(), SoundLayout.Mode.SCENE_FOLDER)
	_eq(_action(again, "aranha.ataque#0").get("path"), path, "cena renomeada: o som fica")
	_eq(_op(again, "aranha.ataque#0"), "keep", "e nada muda")


## Edited by the user + new version on the site: ask, and only replace if they opt in.
func _test_edited_can_take_site_version() -> void:
	_reset()
	await _install(_manifest(), SoundLayout.Mode.GOMO)
	var path := ROOT + "/aranha/ataque.wav"
	_append_byte(path)
	var plan := InstallPlanner.plan(_manifest({"f1": "f1-novo"}), InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT, true)
	_eq(InstallPlanner.outdated_edits(plan), 1, "editado com versão nova: oferece trocar")
	_ok(InstallPlanner.needs_confirmation(plan), "e pergunta")
	InstallPlanner.accept_site_versions(plan)
	await InstallApplier.apply(self, plan, "g", ROOT)
	_eq(FileAccess.get_file_as_bytes(path), FileAccess.get_file_as_bytes(URLS["u_fire"]), "marcou: agora é a versão do site")
	var after := InstallPlanner.plan(_manifest({"f1": "f1-novo"}), InstallCatalog.load_catalog(ROOT), SoundLayout.Mode.GOMO, ROOT, true)
	_eq(_op(after, "aranha.ataque#0"), "keep", "e volta a ser do plugin")


func _test_prune_empty_dirs() -> void:
	_write("res://units/vazia/sub/x.wav", PackedByteArray([1]))
	_write("res://units/vazia/outro.txt", PackedByteArray([1]))
	DirAccess.remove_absolute("res://units/vazia/sub/x.wav")
	InstallApplier._prune_empty_dirs("res://units/vazia/sub")
	_ok(not DirAccess.dir_exists_absolute("res://units/vazia/sub"), "pasta vazia sai")
	_ok(DirAccess.dir_exists_absolute("res://units/vazia"), "pasta com coisa dentro fica")


## A folder sound (same eventId and same path for everyone that inherits it).
func _shared(key: String, entity: String, inherited: String) -> Dictionary:
	var s := _sound(key, entity, "", "Pronto", ["u_fire"], ["fp"], "sounds/_pastas/buildings")
	s["eventId"] = "evento-pasta"
	s["inheritedFrom"] = inherited if inherited != "" else null
	return s


## The version is kept in memory: deleting plugin.cfg (reinstall with the editor open) doesn't turn into "0.0.0".
func _test_version_survives_missing_cfg() -> void:
	var version := SfxSettings.plugin_version()
	_ok(version != "0.0.0" and version != "", "versão lida do plugin.cfg")
	var real := ProjectSettings.globalize_path("res://addons/gomo_sounds/plugin.cfg")
	var backup := real + ".bak"
	DirAccess.rename_absolute(real, backup)
	_eq(SfxSettings.plugin_version(), version, "sem o plugin.cfg no disco, a versão continua a mesma")
	DirAccess.rename_absolute(backup, real)


## The tempo of each music file reaches the catalog (games sync visuals to the beat); a catalog from before
## the field gets it on the next Install without downloading anything.
func _test_music_bpm() -> void:
	var dir := "res://musica_bpm"
	var tema := _sound("@music.tema", "Musica", "", "Tema", ["u_fire", "u_rain"], ["m1", "m2"], "sounds/_pastas/music")
	tema["bpms"] = [128, null]
	var site := {"sounds": [tema, _sound("passo.passo", "Passo", "", "Passo", ["u_forest"], ["p1"], "sounds/passo")]}
	var plan := InstallPlanner.plan(site, InstallCatalog.load_catalog(dir), SoundLayout.Mode.GOMO, dir, true)
	await InstallApplier.apply(self, plan, "g", dir)
	var bpm := _bpms(dir)
	_eq(bpm.get("m1"), 128.0, "música: o bpm do site vai pro catálogo (float)")
	_ok(bpm.has("m2") and bpm["m2"] == null, "música sem andamento: bpm null")
	_ok(bpm.has("p1") and bpm["p1"] == null, "som que não é música (site sem bpms): bpm null")
	_ok(not InstallSummary.has_changes(InstallPlanner.plan(site, InstallCatalog.load_catalog(dir), SoundLayout.Mode.GOMO, dir, true)), "bpm igual: rodar de novo não muda nada")

	# Catalog written by 0.6.x: no bpm field. Reads as unknown, and the next Install fills it in, writing no audio.
	var old := InstallCatalog.load_catalog(dir)
	for e: Dictionary in old.files:
		e.erase("bpm")
	InstallCatalog.save(old, dir)
	var again := InstallPlanner.plan(site, InstallCatalog.load_catalog(dir), SoundLayout.Mode.GOMO, dir, true)
	_eq(_op(again, InstallCatalog.slot_for(tema, 0)), "keep", "catálogo antigo: o arquivo fica")
	_ok(InstallSummary.has_changes(again), "catálogo antigo sem bpm: o Instalar tem o que gravar")
	var downloads := _downloads
	await InstallApplier.apply(self, again, "g", dir)
	_eq(_bpms(dir).get("m1"), 128.0, "catálogo antigo ganha o bpm")
	_eq(_downloads, downloads, "sem baixar o áudio de novo")
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
	_eq(r["error"], "", "instalou sem erro")
	return plan


func _manifest(versions := {}, urls := {}) -> Dictionary:
	var v := func(id: String) -> String: return versions.get(id, id)
	var u := func(id: String) -> String: return urls.get(id, id)
	return {"sounds": [
		_sound("aranha.ataque", "Aranha", SCENE, "Ataque", [u.call("u_fire"), u.call("u_rain")], [v.call("f1"), v.call("f2")]),
		_sound("@ambience.vento", "Ambiente", "", "Vento", [u.call("u_forest")], [v.call("f3")], "sounds/_pastas/ambience", [true]),
		_sound("con.morte", "CON", "", "Morte", [u.call("u_fire")], [v.call("f4")], "sounds/con"),
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
	_write(SCENE, "[gd_scene format=3]\n\n[node name=\"Aranha\" type=\"Node3D\"]\n".to_utf8_buffer())


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
	return str(_action(plan, slot).get("op", "(nenhuma)"))


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print(("  ok   " if cond else "  FALHA ") + what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what if got == want else "%s (veio %s, esperado %s)" % [what, got, want])
