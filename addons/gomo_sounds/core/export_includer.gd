@tool
extends EditorExportPlugin

const InstallCatalog := preload("res://addons/gomo_sounds/core/install_catalog.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")

## Makes sure the sounds reach the EXPORTED game. The game loads the catalog and sounds by path,
## so no scene "depends" on them: in a preset that exports only selected scenes/resources, they
## would be left out and the game would ship silent. In those presets the plugin includes the catalog and each
## imported sound (the .import + the imported file), and skips the normal copy of those same files so nothing
## goes in twice. Scripts do NOT go in this way: Godot only registers the class (SfxLibrary) of
## scripts it exports itself. In the "all resources" preset it does nothing.

## EditorExportPreset.EXPORT_SELECTED_SCENES / EXPORT_SELECTED_RESOURCES, as numbers: the class is only
## exposed from 4.3 on, and naming it would stop the plugin from opening on earlier versions.
const SELECTED_FILTERS := [1, 2]

var _added := {}


func _get_name() -> String:
	return "GomoSounds"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_added.clear()
	if not _exports_only_part():
		return
	var dir := SfxSettings.install_dir()
	var catalog_path := SfxSettings.catalog_path(dir)
	if not FileAccess.file_exists(catalog_path):
		return
	_add(catalog_path)
	for e: Dictionary in InstallCatalog.load_catalog(dir).files:
		_add_imported(InstallCatalog.current_path(e))


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _added.has(path):
		skip()


## Preset that exports only part of the project (selected scenes or resources).
func _exports_only_part() -> bool:
	if not has_method("get_export_preset"):
		return false
	var preset: Object = call("get_export_preset")
	if preset == null:
		return false
	return int(preset.call("get_export_filter")) in SELECTED_FILTERS


func _add(path: String) -> void:
	if FileAccess.file_exists(path) and not _added.has(path):
		add_file(path, FileAccess.get_file_as_bytes(path), false)
		_added[path] = true


## Imported sound: the game opens it via the .import, which points to the file in .godot/imported.
func _add_imported(source: String) -> void:
	var cfg := ConfigFile.new()
	if _added.has(source) or cfg.load(source + ".import") != OK:
		return
	add_file(source + ".import", FileAccess.get_file_as_bytes(source + ".import"), false)
	for dest: Variant in cfg.get_value("deps", "dest_files", []):
		_add(str(dest))
	_added[source] = true
