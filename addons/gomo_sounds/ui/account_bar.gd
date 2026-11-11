@tool
extends VBoxContainer

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxCard := preload("res://addons/gomo_sounds/ui/card.gd")
const SfxDeviceLogin := preload("res://addons/gomo_sounds/core/device_login.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SfxUi := preload("res://addons/gomo_sounds/ui/sfx_ui.gd")

## Account. Disconnected: only the welcome card with Connect (and the connect help).
## Connected: one line showing who is connected and the sign-out menu.

signal connection_changed

const MENU_DISCONNECT := 0

var _api: SfxApi
var _welcome: SfxCard
var _welcome_status: Label
var _code_box: VBoxContainer
var _code_label: Label
var _connect_btn: Button
var _line: HBoxContainer
var _who: Label
## New plugin version notice (hidden when up to date).
var _update: HBoxContainer
var _update_label: Label
var _update_url := ""
var _login: SfxDeviceLogin


func setup(api: SfxApi) -> void:
	_api = api
	_build_welcome()
	_build_line()
	refresh()


func _build_welcome() -> void:
	_welcome = SfxCard.new()
	_welcome.add(SfxUi.label(T.t("welcome_body"), false, true))
	_connect_btn = _welcome.add(SfxUi.primary(T.t("connect"), _on_connect, "Load")) as Button
	_welcome.add(SfxUi.hint(T.t("connect_hint")))
	_code_box = VBoxContainer.new()
	_code_box.visible = false
	_code_label = SfxUi.title("", 26)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_box.add_child(SfxUi.hint(T.t("approve_code")))
	_code_box.add_child(_code_label)
	var cancel := SfxUi.button(T.t("cancel"), _on_cancel)
	cancel.flat = true
	_code_box.add_child(cancel)
	_welcome.add(_code_box)
	_welcome_status = _welcome.add(SfxUi.hint("")) as Label
	add_child(_welcome)


func _build_line() -> void:
	_who = SfxUi.label("", true)
	_who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var menu := MenuButton.new()
	menu.icon = SfxUi.icon("GuiTabMenuHl")
	menu.flat = true
	menu.tooltip_text = T.t("account_menu")
	menu.get_popup().add_icon_item(SfxUi.icon("Unlinked"), T.t("disconnect"), MENU_DISCONNECT)
	menu.get_popup().id_pressed.connect(func(id: int) -> void:
		if id == MENU_DISCONNECT:
			_on_disconnect())
	var dot := SfxUi.label("●")
	dot.add_theme_color_override("font_color", SfxUi.color("success_color"))
	dot.add_theme_font_size_override("font_size", int(10 * SfxUi.scale()))
	_line = SfxUi.hbox([dot, _who, menu])
	add_child(_line)
	_update_label = SfxUi.label("", false, true)
	_update_label.add_theme_color_override("font_color", SfxUi.color("warning_color"))
	_update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var download := SfxUi.button(T.t("update_download"), func() -> void: OS.shell_open(_update_url), "Load")
	_update = SfxUi.hbox([_update_label, download])
	_update.visible = false
	add_child(_update)


func is_connected_account() -> bool:
	return SfxSettings.api_key() != ""


func refresh() -> void:
	var connected := is_connected_account()
	_welcome.visible = not connected
	_line.visible = connected
	if not connected:
		return
	_who.text = T.t("checking")
	var me := await _api.call_tool("list_games")
	if not me.ok:
		_who.text = T.t("error", me.error)
		if me.status == 401:
			SfxSettings.set_api_key("")
			refresh()
		return
	_check_version()
	var d: Dictionary = me.data["account"]
	_who.text = T.t("account_short", [d["user"]["name"], _thousands(int(d["credits"]))])
	_who.tooltip_text = T.t("account_line", [d["user"]["name"], _thousands(int(d["credits"])), d["plan"]["name"]])


## Asks the site for the current version: if newer than this one, shows the notice with the download link.
func _check_version() -> void:
	var info := await _api.plugin_info()
	if not info.ok or not info.data is Dictionary:
		return
	var latest := str(info.data.get("latest", ""))
	_update_url = str(info.data.get("download", ""))
	_update.visible = latest != "" and newer(latest, SfxSettings.plugin_version())
	_update_label.text = T.t("update_available", [latest, SfxSettings.plugin_version()])


## Is `a` newer than `b`? ("0.3.0" > "0.2.9")
static func newer(a: String, b: String) -> bool:
	var x := a.split(".")
	var y := b.split(".")
	for i in 3:
		var p := int(x[i]) if i < x.size() else 0
		var q := int(y[i]) if i < y.size() else 0
		if p != q:
			return p > q
	return false


func _on_connect() -> void:
	_welcome_status.text = ""
	_login = SfxDeviceLogin.new()
	_login.code_ready.connect(func(code: String, _url: String) -> void:
		_code_label.text = code
		_code_box.visible = true)
	_connect_btn.disabled = true
	var err := await _login.run(_api)
	_code_box.visible = false
	_connect_btn.disabled = false
	_login = null
	if err != "":
		_welcome_status.text = err
		return
	await refresh()
	connection_changed.emit()


func _on_cancel() -> void:
	if _login:
		_login.cancel()


func _on_disconnect() -> void:
	SfxSettings.set_api_key("")
	refresh()
	connection_changed.emit()


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
