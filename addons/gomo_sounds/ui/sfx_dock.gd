@tool
extends ScrollContainer

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const SfxAccountBar := preload("res://addons/gomo_sounds/ui/account_bar.gd")
const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxCard := preload("res://addons/gomo_sounds/ui/card.gd")
const SfxEntityPanel := preload("res://addons/gomo_sounds/ui/entity_panel.gd")
const SfxGamePicker := preload("res://addons/gomo_sounds/ui/game_picker.gd")
const SfxInstallCard := preload("res://addons/gomo_sounds/ui/install_card.gd")
const SfxSceneBrowser := preload("res://addons/gomo_sounds/ui/scene_browser.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SfxThumbnailProvider := preload("res://addons/gomo_sounds/core/thumbnail_provider.gd")
const SfxUi := preload("res://addons/gomo_sounds/ui/sfx_ui.gd")

## Gomo Sounds panel. It just wires the parts: account → game → 1 send scenes → 2 create sounds → 3 install.
## Each hint lives in the step it explains; when disconnected, only the connect card shows.

var _api: SfxApi
var _thumbs: SfxThumbnailProvider
var _account: SfxAccountBar
var _game: SfxGamePicker
var _scenes: SfxSceneBrowser
var _entity: SfxEntityPanel
var _entity_hint: Label
var _body: VBoxContainer
## Steps 1 to 3: only shown with a game selected.
var _steps: Array[Control] = []


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Texts already come in the editor's language (i18n): without this Godot re-translates only the words
	# that exist in its own dictionary ("Jogo", "Desconectar") and the panel ends up in two languages.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var s := SfxUi.scale()
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(8 * s))
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", int(10 * s))
	margin.add_child(root)
	_api = SfxApi.new()
	_thumbs = SfxThumbnailProvider.new()
	add_child(_api)
	add_child(_thumbs)

	root.add_child(SfxUi.brand_header())
	_account = SfxAccountBar.new()
	root.add_child(_account)
	_account.setup(_api)
	_account.connection_changed.connect(_on_connection_changed)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(10 * s))
	root.add_child(_body)
	_game = SfxGamePicker.new()
	_body.add_child(_game)
	_game.setup(_api)
	_game.game_changed.connect(_on_game_changed)
	_game.refresh_requested.connect(_refresh_all)

	var send := SfxCard.new(T.t("step_send"), "1")
	_scenes = SfxSceneBrowser.new()
	send.add(_scenes)
	_body.add_child(send)
	_steps.append(send)
	_scenes.setup(_api, _thumbs)
	_scenes.entity_selected.connect(_open_entity)
	_scenes.game_missing.connect(_game.load_games)

	var sounds := SfxCard.new(T.t("step_sounds"), "2")
	_entity_hint = sounds.add(SfxUi.hint(T.t("sounds_hint"))) as Label
	_entity = SfxEntityPanel.new()
	sounds.add(_entity)
	_body.add_child(sounds)
	_steps.append(sounds)
	_entity.setup(_api)
	_entity.changed.connect(func() -> void: _scenes.reload_entities())

	var install := SfxInstallCard.new()
	_body.add_child(install)
	_steps.append(install)
	install.setup(_api)

	_on_connection_changed()


func _on_connection_changed() -> void:
	_body.visible = SfxSettings.api_key() != ""
	if _body.visible:
		_game.load_games()


func _refresh_all() -> void:
	await _account.refresh()
	_on_connection_changed()


func _on_game_changed(game_id: String) -> void:
	for step in _steps:
		step.visible = game_id != ""
	_show_entity(false)
	if game_id != "":
		_scenes.load_for_game(game_id)


func _open_entity(id: String) -> void:
	_show_entity(true)
	_entity.open(id)


## With no scene open, step 2 shows only the hint on how to open one.
func _show_entity(on: bool) -> void:
	_entity.visible = on
	_entity_hint.visible = not on
