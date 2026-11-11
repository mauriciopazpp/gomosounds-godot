@tool
extends VBoxContainer

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const SfxGameLinker := preload("res://addons/gomo_sounds/core/game_linker.gd")
const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SfxUi := preload("res://addons/gomo_sounds/ui/sfx_ui.gd")

## Which Gomo Sounds game matches this project. Opens with none selected: it only links when
## the person picks from the list (matching by name linked to the wrong game with the same name). The choice is stored in project.godot.

signal game_changed(game_id: String)
## Request for a full reload (account + games), fired by the ⟳ button.
signal refresh_requested

var _api: SfxApi
var _option: OptionButton
var _info: Label
var _create: Button
var _games: Array = []


func setup(api: SfxApi) -> void:
	_api = api
	_option = OptionButton.new()
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option.item_selected.connect(_on_selected)
	_info = SfxUi.hint("")
	_info.visible = false
	var site := SfxUi.icon_button("ExternalLink", T.t("open_site"), _open_site)
	var reload := SfxUi.icon_button("Reload", T.t("reload_all"), refresh_requested.emit)
	add_child(SfxUi.hbox([SfxUi.label(T.t("game"), true), _option, site, reload]))
	add_child(_info)
	# No game selected: create one with the project's name, only on click (never on its own).
	_create = SfxUi.button("", _on_create, "Add")
	_create.visible = false
	add_child(_create)


func load_games() -> void:
	_option.clear()
	_info.text = ""
	_info.visible = false
	if SfxSettings.api_key() == "":
		return
	var res: Array = await SfxGameLinker.resolve(_api)
	var linked: String = res[0]
	_games = res[1]
	# The first row is "none": with no choice, the rest of the panel stays hidden.
	_option.add_item(T.t("pick_game"))
	_option.set_item_metadata(0, "")
	for i in _games.size():
		_option.add_item(str(_games[i]["name"]))
		_option.set_item_metadata(i + 1, str(_games[i]["id"]))
		if str(_games[i]["id"]) == linked:
			_option.select(i + 1)
	if linked == "":
		_option.select(0)
	_show_info("" if linked != "" else (T.t("pick_game_hint") if res[2] == T.t("no_game_linked") else str(res[2])))
	_update_create(linked)
	game_changed.emit(linked)


func _show_info(text: String) -> void:
	_info.text = text
	_info.visible = text != ""


## Opens the game's page in the browser (sound direction, folders, generate).
func _open_site() -> void:
	var id := SfxSettings.game_id()
	var path := "/app/games/" + id if id != "" else "/app/games"
	OS.shell_open(SfxSettings.api_url() + path)


func _on_selected(index: int) -> void:
	var id := str(_option.get_item_metadata(index))
	SfxSettings.set_game_id(id)
	_show_info("" if id != "" else T.t("pick_game_hint"))
	_update_create(id)
	game_changed.emit(id)


## The button only shows with no game selected. If a game with the project's name already exists, it says "another", so
## nobody creates a duplicate thinking it's the same one.
func _update_create(linked: String) -> void:
	var wanted := SfxSettings.project_name()
	var taken := false
	for g: Dictionary in _games:
		taken = taken or str(g["name"]).to_lower() == wanted.to_lower()
	_create.text = T.t("create_another_game" if taken else "create_game", wanted)
	_create.visible = linked == ""
	_create.disabled = false


func _on_create() -> void:
	_create.disabled = true
	var r := await _api.call_tool("create_game", {"name": SfxSettings.project_name(), "engine": "godot", "language": T.http_language()})
	if not r.ok:
		_show_info(r.error)
		_create.disabled = false
		return
	SfxSettings.set_game_id(str(r.data["id"]))
	await load_games()
	_show_info(T.t("game_created", SfxSettings.project_name()))
