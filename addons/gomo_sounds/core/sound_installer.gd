@tool
extends RefCounted

const InstallApplier := preload("res://addons/gomo_sounds/core/install_applier.gd")
const InstallCatalog := preload("res://addons/gomo_sounds/core/install_catalog.gd")
const InstallImport := preload("res://addons/gomo_sounds/core/install_import.gd")
const InstallPlanner := preload("res://addons/gomo_sounds/core/install_planner.gd")
const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SoundLayout := preload("res://addons/gomo_sounds/core/sound_layout.gd")

## Installs the game's CHOSEN sounds into the project, in two steps: `prepare` (asks the site and
## builds the plan, writing nothing, so the dock can show the summary and ask for confirmation) and `apply`.
## Where each sound lives: SoundLayout. What may or may not be touched: InstallPlanner.


## Returns {error, plan}.
static func prepare(api: SfxApi, game_id: String) -> Dictionary:
	# Just looking doesn't count as "installed" on the site (the user may still cancel): that's mark_installed.
	var r := await api.call_tool("get_manifest", {"game_id": game_id})
	if not r.ok:
		return {"error": r.error, "plan": {}}
	# The catalog comes from where it IS; the sounds go where the mode says (if it changed, the plan moves them).
	var catalog := InstallCatalog.load_catalog(SfxSettings.install_dir())
	var mode := SoundLayout.mode_from_id(SfxSettings.layout())
	var plan_data := InstallPlanner.plan(r.data, catalog, mode, SfxSettings.target_root(), SfxSettings.remove_missing())
	return {"error": "", "plan": plan_data}


## Returns {error, written}. The catalog now lives in the new folder; the old one loses its own (a single
## source of truth) and the new folder is saved in project.godot (the exported game reads it from there).
static func apply(api: SfxApi, game_id: String, plan_data: Dictionary, progress := Callable()) -> Dictionary:
	var old := SfxSettings.install_dir()
	var dir := SfxSettings.target_root()
	var r: Dictionary = await InstallApplier.apply(api, plan_data, game_id, dir, progress)
	if r.get("saved", false):
		if old != dir:
			InstallCatalog.retire(old)
		if Engine.is_editor_hint():
			SfxSettings.set_install_dir(dir)
	if r["error"] == "":
		# Now it has actually reached the game (the site shows "installed"). Failing here undoes nothing.
		await api.call_tool("mark_installed", {"game_id": game_id})
	return r


## Nothing new to download: fixes what an earlier install left halfway (uid, loop) and tells the site the
## sounds are in the game (that install never got to say it).
static func repair(api: SfxApi, game_id: String) -> void:
	var dir := SfxSettings.install_dir()
	var catalog := InstallCatalog.load_catalog(dir)
	if catalog == null or catalog.get("files").is_empty():
		return
	if Engine.is_editor_hint() and await InstallImport.repair(catalog):
		InstallCatalog.save(catalog, dir)
	await api.call_tool("mark_installed", {"game_id": game_id})


## All at once (command line): returns {error, plan}. No confirmation, but also no
## risk: the plan never touches a file that isn't the plugin's nor an edited file.
static func install(api: SfxApi, game_id: String) -> Dictionary:
	var p := await prepare(api, game_id)
	if p["error"] != "":
		return p
	var r := await apply(api, game_id, p["plan"])
	return {"error": r["error"], "plan": p["plan"]}


static func catalog_path() -> String:
	return SfxSettings.catalog_path(SfxSettings.install_dir())
