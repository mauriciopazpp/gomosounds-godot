@tool
extends VBoxContainer

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SfxUi := preload("res://addons/gomo_sounds/ui/sfx_ui.gd")
const SoundLayout := preload("res://addons/gomo_sounds/core/sound_layout.gd")

## The install choices: where the sounds live (mode and, for "Custom location", the folder) and whether
## what left the site leaves the project. Everything is stored in project.godot, so it applies to the whole team and comes back
## the same when reopening the project. Changing it doesn't touch anything right away: the next install shows what will
## move and asks for confirmation.

var _mode: OptionButton
var _mode_hint: Label
var _custom_row: HBoxContainer
var _custom: LineEdit
var _custom_error: Label
var _picker: EditorFileDialog


func _init() -> void:
	add_theme_constant_override("separation", int(6 * SfxUi.scale()))
	add_child(SfxUi.label(T.t("layout_label"), true))
	_mode = OptionButton.new()
	for id: String in SoundLayout.MODE_IDS:
		_mode.add_item(T.t("layout_" + id))
	_mode.selected = SoundLayout.mode_from_id(SfxSettings.layout())
	_mode.item_selected.connect(func(i: int) -> void:
		SfxSettings.set_layout(SoundLayout.MODE_IDS[i])
		_refresh())
	add_child(_mode)
	_build_custom_row()
	_mode_hint = SfxUi.hint("")
	add_child(_mode_hint)
	var remove := CheckBox.new()
	remove.text = T.t("remove_missing")
	remove.button_pressed = SfxSettings.remove_missing()
	remove.toggled.connect(SfxSettings.set_remove_missing)
	add_child(remove)
	add_child(SfxUi.hint(T.t("remove_missing_hint")))
	_refresh()


## Path field + choose folder + show in FileSystem. Only shown for "Custom location".
func _build_custom_row() -> void:
	_custom = LineEdit.new()
	_custom.placeholder_text = T.t("custom_placeholder")
	_custom.text = SfxSettings.custom_dir()
	_custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom.text_submitted.connect(_on_custom)
	_custom.focus_exited.connect(func() -> void: _on_custom(_custom.text))
	var pick := SfxUi.icon_button("Folder", T.t("folder_change"), _pick_folder)
	var show := SfxUi.icon_button("Filesystem", T.t("folder_show"), func() -> void:
		if DirAccess.dir_exists_absolute(SfxSettings.target_root()):
			EditorInterface.get_file_system_dock().navigate_to_path(SfxSettings.target_root()))
	_custom_row = SfxUi.hbox([_custom, pick, show])
	add_child(_custom_row)
	_custom_error = SfxUi.hint(T.t("folder_invalid"))
	_custom_error.add_theme_color_override("font_color", SfxUi.color("error_color"))
	add_child(_custom_error)


func _refresh() -> void:
	var custom := SfxSettings.layout() == "custom"
	_custom_row.visible = custom
	_custom_error.visible = custom and _custom.text.strip_edges() != "" and not SfxSettings.is_valid_install_dir(_custom.text.strip_edges())
	_mode_hint.text = T.t("layout_%s_hint" % SfxSettings.layout(), SfxSettings.target_root())


func _pick_folder() -> void:
	if _picker == null:
		_picker = EditorFileDialog.new()
		_picker.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		_picker.access = EditorFileDialog.ACCESS_RESOURCES
		_picker.dir_selected.connect(_on_custom)
		add_child(_picker)
	var cur := SfxSettings.custom_dir()
	_picker.current_dir = cur if DirAccess.dir_exists_absolute(cur) else "res://"
	_picker.popup_file_dialog()


## An invalid path (outside the project, addons, .godot) is not saved: the warning stays and installs
## keep going to the Gomo folder until it is fixed.
func _on_custom(dir: String) -> void:
	var d := dir.strip_edges().trim_suffix("/")
	_custom.text = d
	if SfxSettings.is_valid_install_dir(d) and d != SfxSettings.custom_dir():
		SfxSettings.set_custom_dir(d)
	_refresh()
