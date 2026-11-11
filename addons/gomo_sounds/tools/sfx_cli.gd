extends SceneTree

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

## Gomo Sounds from the command line (CI, scripts, without opening the editor).
##
##   GOMO_API_KEY=gomo_... godot --headless --path . -s addons/gomo_sounds/tools/sfx_cli.gd -- sync
##   GOMO_API_KEY=gomo_... godot --headless --path . -s addons/gomo_sounds/tools/sfx_cli.gd -- install
##
## sync     registers the scenes in the configured folders (name, description, image)
##          option: --folders=res://units,res://buildings
## install  downloads the chosen sounds (where: gomo_sounds/layout and gomo_sounds/install_dir in
##          project.godot) and saves the catalog. Never overwrites or deletes a file that isn't the
##          plugin's or that someone edited.
## Variables: GOMO_API_KEY (required), GOMO_API_URL, GOMO_GAME_ID (the old SFX_* ones still work).

const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxGameLinker := preload("res://addons/gomo_sounds/core/game_linker.gd")
const SfxSceneRegistrar := preload("res://addons/gomo_sounds/core/scene_registrar.gd")
const SfxSceneScanner := preload("res://addons/gomo_sounds/core/scene_scanner.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SfxSoundInstaller := preload("res://addons/gomo_sounds/core/sound_installer.gd")
const InstallSummary := preload("res://addons/gomo_sounds/core/install_summary.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var command := args[0] if args.size() > 0 else ""
	if command not in ["sync", "install"]:
		printerr("Uso: -- sync [--folders=res://a,res://b] | -- install")
		quit(2)
		return
	SfxSettings.migrate_legacy()
	if SfxSettings.api_key() == "":
		printerr("Defina GOMO_API_KEY (crie a chave em Integrações no Gomo Sounds).")
		quit(2)
		return
	var api := SfxApi.new()
	root.add_child(api)
	var link: Array = await SfxGameLinker.resolve(api)
	var game_id: String = link[0]
	if game_id == "":
		printerr("Sem jogo: ", link[2])
		quit(1)
		return
	print("[sfx] jogo ", game_id, " ", link[2])
	var err := ""
	if command == "sync":
		err = await _sync(api, game_id, args)
	else:
		err = await _install(api, game_id)
	if err != "":
		printerr("[sfx] erro: ", err)
	quit(0 if err == "" else 1)


func _sync(api: SfxApi, game_id: String, args: PackedStringArray) -> String:
	var folders := SfxSettings.scan_folders()
	for a in args:
		if a.begins_with("--folders="):
			folders = a.substr(10).split(",", false)
	var scenes := SfxSceneScanner.list_scenes(folders)
	print("[sfx] ", scenes.size(), " cenas em ", ", ".join(folders))
	var registrar := SfxSceneRegistrar.new()
	registrar.progress.connect(func(msg: String) -> void: print("[sfx] ", msg))
	var res: Dictionary = await registrar.register(api, game_id, scenes, null)
	if str(res["error"]) == "":
		print("[sfx] ", SfxSceneRegistrar.summary(res))
	return str(res["error"])


func _install(api: SfxApi, game_id: String) -> String:
	var r: Dictionary = await SfxSoundInstaller.install(api, game_id)
	if r["error"] == "":
		print("[sfx] ", InstallSummary.text(r["plan"]).replace("\n", "\n[sfx] "))
		print("[sfx] ", T.t("installed_where", SfxSoundInstaller.catalog_path()))
		if InstallSummary.has_changes(r["plan"]):
			_import_new_files()
	return r["error"]


## Godot won't load a downloaded file without its .import: the game stayed SILENT until someone opened the editor
## (which imports on its own). There is no editor here, so run Godot's own import on the project.
func _import_new_files() -> void:
	print("[sfx] ", T.t("cli_importing"))
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"], out, true)
	if code != 0:
		printerr("[sfx] ", T.t("cli_import_failed"))
