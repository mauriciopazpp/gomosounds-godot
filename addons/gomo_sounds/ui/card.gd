@tool
extends PanelContainer

const SfxBrand := preload("res://addons/gomo_sounds/ui/brand.gd")
const SfxUi := preload("res://addons/gomo_sounds/ui/sfx_ui.gd")

## Card for a panel step: slightly highlighted background, step number and title.
## Content goes into `body` (or via add()).

var body: VBoxContainer


func _init(title_text := "", step := "") -> void:
	var s := SfxUi.scale()
	var box := StyleBoxFlat.new()
	box.bg_color = SfxUi.color("base_color").lightened(0.06)
	box.border_color = Color(1, 1, 1, 0.06)
	box.set_border_width_all(maxi(1, int(s)))
	box.set_corner_radius_all(int(8 * s))
	box.set_content_margin_all(12 * s)
	add_theme_stylebox_override("panel", box)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", int(8 * s))
	add_child(body)
	if title_text == "":
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(8 * s))
	if step != "":
		head.add_child(_badge(step))
	head.add_child(SfxUi.title(title_text))
	body.add_child(head)


func add(c: Control) -> Control:
	body.add_child(c)
	return c


## Little circle with the step number, in Gomo orange.
static func _badge(step: String) -> Label:
	var s := SfxUi.scale()
	var l := Label.new()
	l.text = step
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(22, 22) * s
	l.add_theme_font_size_override("font_size", int(12 * s))
	l.add_theme_color_override("font_color", SfxBrand.ON_ORANGE)
	var box := StyleBoxFlat.new()
	box.bg_color = SfxBrand.ORANGE
	box.set_corner_radius_all(int(11 * s))
	l.add_theme_stylebox_override("normal", box)
	return l
