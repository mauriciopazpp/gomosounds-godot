@tool
extends EditorPlugin

## Gomo Sounds panel in the editor sidebar. All the logic lives in the dock and in core/.
## Godot 4.6+: tab via EditorDock (tangerine icon and orange title). Before that, the
## old path (add_control_to_dock), with the icon. Methods are called by name on purpose:
## the plugin still opens on versions that don't have the new API.

const DOCK_SCENE_SCRIPT := preload("res://addons/gomo_sounds/ui/sfx_dock.gd")
const SfxBrand := preload("res://addons/gomo_sounds/ui/brand.gd")
const SfxExportIncluder := preload("res://addons/gomo_sounds/core/export_includer.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")

const TITLE := "Gomo Sounds"
## What the game calls to play (SfxLibrary.play / play_event). Autoload: always exported.
const AUTOLOAD := "SfxLibrary"
const AUTOLOAD_PATH := "res://addons/gomo_sounds/runtime/sfx_library.gd"

var _dock: Control
var _holder: Control
var _export: EditorExportPlugin


func _enable_plugin() -> void:
	_ensure_autoload()


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD):
		remove_autoload_singleton(AUTOLOAD)


## Also in _enter_tree: anyone who already had the plugin enabled (class_name version) gets the autoload
## without having to disable and re-enable it. If it points elsewhere (the old plugin, in
## addons/sfx_studio), switches it to the current path.
func _ensure_autoload() -> void:
	var key := "autoload/" + AUTOLOAD
	if ProjectSettings.has_setting(key) and str(ProjectSettings.get_setting(key)).trim_prefix("*") != AUTOLOAD_PATH:
		remove_autoload_singleton(AUTOLOAD)
	if not ProjectSettings.has_setting(key):
		add_autoload_singleton(AUTOLOAD, AUTOLOAD_PATH)


func _enter_tree() -> void:
	# Stores the version while plugin.cfg is sure to exist.
	SfxSettings.plugin_version()
	SfxSettings.migrate_legacy()
	_ensure_autoload()
	_export = SfxExportIncluder.new()
	add_export_plugin(_export)
	_dock = DOCK_SCENE_SCRIPT.new()
	_dock.name = TITLE
	var icon := SfxBrand.icon(int(16 * EditorInterface.get_editor_scale()))
	if ClassDB.class_exists("EditorDock") and has_method("add_dock"):
		_holder = ClassDB.instantiate("EditorDock")
		_holder.set("title", TITLE)
		_holder.set("layout_key", "gomo_sounds")
		_holder.set("dock_icon", icon)
		_holder.set("force_show_icon", true)
		_holder.set("title_color", SfxBrand.ORANGE)
		_holder.set("default_slot", DOCK_SLOT_RIGHT_UL)
		_holder.add_child(_dock)
		call("add_dock", _holder)
	else:
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
		if icon != null and has_method("set_dock_tab_icon"):
			call("set_dock_tab_icon", _dock, icon)


func _exit_tree() -> void:
	if _export:
		remove_export_plugin(_export)
		_export = null
	if _holder:
		call("remove_dock", _holder)
		_holder.queue_free()
	elif _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_holder = null
	_dock = null
