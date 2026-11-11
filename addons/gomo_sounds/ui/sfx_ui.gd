@tool
extends RefCounted

const SfxBrand := preload("res://addons/gomo_sounds/ui/brand.gd")

## Small UI pieces repeated across the panel. Sizes and neutral colors come from the editor theme
## (light or dark); the accent is Gomo's orange (SfxBrand), the same as the site.


static func scale() -> float:
	return EditorInterface.get_editor_scale()


static func color(name: String) -> Color:
	return EditorInterface.get_editor_theme().get_color(name, "Editor")


## Editor icon by name. Names change between Godot versions: "A|B|C" tries in order and,
## if none exists, shows no icon (no warning in the person's console).
static func icon(names: String) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	for n in names.split("|", false):
		if theme.has_icon(n, "EditorIcons"):
			return theme.get_icon(n, "EditorIcons")
	return null


static func label(text: String, muted := false, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	if muted:
		l.modulate = Color(1, 1, 1, 0.6)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, size := 15) -> Label:
	var l := label(text)
	l.add_theme_font_size_override("font_size", int(size * scale()))
	return l


## Help text: small, muted and wrapping. Sits near what it explains.
static func hint(text: String) -> Label:
	var l := label(text, true, true)
	l.add_theme_font_size_override("font_size", int(12 * scale()))
	return l


static func button(text: String, on_press: Callable, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	if icon_name != "":
		b.icon = icon(icon_name)
	b.pressed.connect(on_press)
	return b


## The step's main button: Gomo orange, taller.
static func primary(text: String, on_press: Callable, icon_name := "") -> Button:
	var b := button(text, on_press, icon_name)
	b.custom_minimum_size.y = 32 * scale()
	var accent := SfxBrand.ORANGE
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = accent.lightened(0.12) if state == "hover" else accent.darkened(0.15) if state == "pressed" else accent
		if state == "disabled":
			box.bg_color.a = 0.4
		if state == "focus":
			box.draw_center = false
		box.set_corner_radius_all(int(6 * scale()))
		box.set_content_margin_all(8 * scale())
		b.add_theme_stylebox_override(state, box)
	var dark := SfxBrand.ON_ORANGE
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(c, dark)
	return b


## Icon-only button, subtle, with a tooltip.
static func icon_button(icon_name: String, tip: String, on_press: Callable) -> Button:
	var b := button("", on_press, icon_name)
	b.flat = true
	b.tooltip_text = tip
	return b


static func hbox(children: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	for c: Control in children:
		h.add_child(c)
	return h


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Panel header: the tangerine icon and the name, in orange.
static func brand_header() -> HBoxContainer:
	var logo := TextureRect.new()
	logo.texture = SfxBrand.icon(int(26 * scale()))
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	var word := title("Gomo Sounds", 16)
	word.add_theme_color_override("font_color", SfxBrand.ORANGE)
	var h := hbox([logo, word])
	h.add_theme_constant_override("separation", int(8 * scale()))
	return h
