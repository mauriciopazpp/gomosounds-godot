@tool
extends VBoxContainer

const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SfxUi := preload("res://addons/gomo_sounds/ui/sfx_ui.gd")

## Row that opens and closes a block (e.g. "How to play in the game"). Remembers whether it was left open
## (editor setting, `key`), so details that only matter sometimes don't clutter the panel.

var body: VBoxContainer
var _toggle: Button
var _key: String


func _init(title_text: String, key: String) -> void:
	_key = key
	_toggle = SfxUi.button(title_text, func() -> void: set_open(not body.visible))
	_toggle.flat = true
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.modulate = Color(1, 1, 1, 0.8)
	add_child(_toggle)
	body = VBoxContainer.new()
	add_child(body)
	var ed := SfxSettings._editor()
	set_open(ed != null and ed.has_setting(_key) and bool(ed.get_setting(_key)))


func add(c: Control) -> Control:
	body.add_child(c)
	return c


func set_open(open: bool) -> void:
	body.visible = open
	_toggle.icon = SfxUi.icon("GuiTreeArrowDown" if open else "GuiTreeArrowRight")
	var ed := SfxSettings._editor()
	if ed != null:
		ed.set_setting(_key, open)
