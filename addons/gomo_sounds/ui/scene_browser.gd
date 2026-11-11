@tool
extends VBoxContainer

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxDisclosure := preload("res://addons/gomo_sounds/ui/disclosure.gd")
const SfxSceneRegistrar := preload("res://addons/gomo_sounds/core/scene_registrar.gd")
const SfxSceneScanner := preload("res://addons/gomo_sounds/core/scene_scanner.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SfxThumbnailProvider := preload("res://addons/gomo_sounds/core/thumbnail_provider.gd")
const SfxUi := preload("res://addons/gomo_sounds/ui/sfx_ui.gd")

## Project scenes with thumbnails. Sync = send to the Gomo Sounds Inbox (name,
## description and image figured out automatically; the project's sounds NEVER leave). Scenes that already have
## sound are hidden by default. Clicking one that's already on the site opens its sheet.

signal entity_selected(entity_id: String)
## The linked game no longer exists (deleted on the site): the panel needs to re-link.
signal game_missing

const ICON_PX := 44

var _api: SfxApi
var _thumbs: SfxThumbnailProvider
var _folders: LineEdit
var _filter: LineEdit
var _list: ItemList
var _info: Label
var _empty: Label
var _inbox_note: HBoxContainer
var _inbox_label: Label
var _game_id := ""
var _scenes := PackedStringArray()
var _entity_by_scene := {}
var _inbox_scenes := {}
var _with_sound := {}
var _skip_sound: CheckBox
var _registering := false
var _register_buttons: Array[Button] = []
var _rescan: Button


func setup(api: SfxApi, thumbs: SfxThumbnailProvider) -> void:
	_api = api
	_thumbs = thumbs
	_folders = LineEdit.new()
	_folders.tooltip_text = T.t("folders_tip")
	_folders.text_submitted.connect(_on_folders_submitted)
	_filter = LineEdit.new()
	_filter.placeholder_text = T.t("filter_scenes")
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t: String) -> void: _fill())
	_list = ItemList.new()
	_list.custom_minimum_size.y = 260 * SfxUi.scale()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(ICON_PX, ICON_PX) * SfxUi.scale()
	_list.select_mode = ItemList.SELECT_MULTI
	_list.item_selected.connect(_on_item_selected)
	_list.multi_selected.connect(func(_i: int, _on: bool) -> void: _update_buttons())
	_list.empty_clicked.connect(func(_p: Vector2, _b: int) -> void:
		_list.deselect_all()
		_update_buttons())
	_list.tooltip_text = T.t("legend")
	_empty = SfxUi.hint(T.t("no_scenes"))
	_empty.visible = false
	_info = SfxUi.hint("")
	_skip_sound = CheckBox.new()
	_skip_sound.text = T.t("skip_with_sound")
	_skip_sound.tooltip_text = T.t("skip_with_sound_tip")
	_skip_sound.button_pressed = SfxSettings.skip_scenes_with_sound()
	_skip_sound.toggled.connect(func(on: bool) -> void:
		SfxSettings.set_skip_scenes_with_sound(on)
		_fill())
	_folders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(SfxUi.hint(T.t("send_hint")))
	add_child(_privacy_note())
	add_child(SfxUi.hbox([SfxUi.label(T.t("folders"), true), _folders]))
	add_child(_filter)
	add_child(_skip_sound)
	add_child(_list)
	add_child(_empty)
	_register_buttons = [SfxUi.primary(T.t("sync_selected"), _register_selected, "ArrowUp"), SfxUi.button(T.t("sync_all"), _register_all)]
	for b in _register_buttons:
		b.tooltip_text = T.t("sync_tip")
	# Search again: rereads the project folders and what's already on the site. It comes first because,
	# with an empty list, it's the only possible step.
	_rescan = SfxUi.button(T.t("rescan"), _on_rescan, "Reload")
	_rescan.tooltip_text = T.t("rescan_tip")
	add_child(SfxUi.hbox([_rescan] + _register_buttons))
	_update_buttons()
	# When the project opens the editor is still indexing files and the search comes back empty:
	# once the index is ready, search again automatically (only if nothing was found yet).
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	add_child(_info)
	_inbox_label = SfxUi.hint("")
	_inbox_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var open := SfxUi.button(T.t("open_inbox"), _open_inbox, "ExternalLink")
	open.flat = true
	_inbox_note = SfxUi.hbox([_inbox_label, open])
	_inbox_note.visible = false
	add_child(_inbox_note)


## "What gets sent?": closed by default, for those who want to check before sending.
static func _privacy_note() -> SfxDisclosure:
	var d := SfxDisclosure.new(T.t("privacy_title"), "gomo_sounds/privacy_open")
	d.add(SfxUi.label(T.t("privacy_sent_title")))
	d.add(SfxUi.hint(T.t("privacy_sent")))
	d.add(SfxUi.label(T.t("privacy_kept_title")))
	d.add(SfxUi.hint(T.t("privacy_kept")))
	return d


func load_for_game(game_id: String) -> void:
	_game_id = game_id
	_folders.text = ", ".join(SfxSettings.scan_folders())
	_scenes = SfxSceneScanner.list_scenes(SfxSettings.scan_folders())
	_with_sound.clear()
	for path in _scenes:
		if SfxSceneScanner.has_audio(path, SfxSettings.install_dir()):
			_with_sound[path] = true
	await reload_entities()


func reload_entities() -> void:
	_entity_by_scene.clear()
	_inbox_scenes.clear()
	if _game_id != "":
		var r := await _api.call_tool("get_game", {"game_id": _game_id})
		if r.status == 404:
			SfxSettings.set_game_id("")
			game_missing.emit()
			return
		if r.ok:
			for e: Dictionary in r.data["entities"]:
				if e.get("externalId") != null:
					_entity_by_scene[str(e["externalId"])] = e
			for i: Dictionary in r.data.get("inbox", []):
				_inbox_scenes[str(i["externalId"])] = true
		else:
			_info.text = r.error
	_fill()


func _fill() -> void:
	_list.clear()
	var q := _filter.text.strip_edges().to_lower()
	var skipped := 0
	for path in _scenes:
		if q != "" and not path.to_lower().contains(q):
			continue
		# A scene that already has sound (and isn't on the site yet) is left out: nothing from it leaves the project.
		if _skip_sound.button_pressed and _with_sound.has(path) and not _entity_by_scene.has(path) and not _inbox_scenes.has(path):
			skipped += 1
			continue
		var e: Dictionary = _entity_by_scene.get(path, {})
		var text := SfxSceneScanner.humanize(path)
		if not e.is_empty():
			text = "%s  ✓ %d/%d" % [e["name"], int(e["doneCount"]), int(e["slotCount"])]
		elif _inbox_scenes.has(path):
			text = "%s  ↑ %s" % [text, T.t("in_inbox")]
		var i := _list.add_item(text)
		_list.set_item_metadata(i, path)
		_list.set_item_tooltip(i, path)
		_load_icon(i, path)
	_update_buttons()
	# An empty list becomes a notice (instead of a gap): the reason is usually the folder.
	_list.visible = _list.item_count > 0
	_empty.visible = not _list.visible
	_info.text = T.t("scenes_count", [_scenes.size(), _entity_by_scene.size()])
	if skipped > 0:
		_info.text += " · " + T.t("hidden_with_sound", skipped)
	# Inbox notice only when there are scenes waiting there: it's the next step, and it happens on the site.
	_inbox_note.visible = not _inbox_scenes.is_empty()
	_inbox_label.text = T.t("inbox_waiting", _inbox_scenes.size())


func _load_icon(index: int, path: String) -> void:
	var tex := await _thumbs.thumbnail(path)
	if tex and index < _list.item_count and _list.get_item_metadata(index) == path:
		_list.set_item_icon(index, tex)


func _on_item_selected(index: int) -> void:
	_update_buttons()
	var e: Dictionary = _entity_by_scene.get(str(_list.get_item_metadata(index)), {})
	if not e.is_empty():
		entity_selected.emit(str(e["id"]))


func _on_filesystem_changed() -> void:
	if _scenes.is_empty() and _game_id != "" and not _registering:
		await load_for_game(_game_id)


func _on_rescan() -> void:
	if _game_id == "":
		game_missing.emit()
		return
	_info.text = T.t("rescanning")
	await load_for_game(_game_id)


func _open_inbox() -> void:
	OS.shell_open("%s/app/games/%s" % [SfxSettings.api_url(), _game_id])


func _on_folders_submitted(text: String) -> void:
	var folders := PackedStringArray()
	for f in text.split(",", false):
		var clean := f.strip_edges()
		if clean != "":
			folders.append(clean if clean.begins_with("res://") else "res://" + clean)
	SfxSettings.set_scan_folders(folders)
	load_for_game(_game_id)


func _register_selected() -> void:
	var paths := PackedStringArray()
	for i in _list.get_selected_items():
		paths.append(str(_list.get_item_metadata(i)))
	await _register(paths)


func _register_all() -> void:
	var paths := PackedStringArray()
	for i in _list.item_count:
		paths.append(str(_list.get_item_metadata(i)))
	await _register(paths)


func _register(paths: PackedStringArray) -> void:
	if _registering:
		return
	if _game_id == "" or paths.is_empty():
		_info.text = T.t("select_first")
		return
	_set_registering(true)
	var registrar := SfxSceneRegistrar.new()
	registrar.progress.connect(func(msg: String) -> void: _info.text = msg)
	var res: Dictionary = await registrar.register(_api, _game_id, paths, _thumbs)
	_set_registering(false)
	if str(res["error"]) != "":
		_info.text = T.t("sync_error", res["error"])
		return
	await reload_entities()
	_info.text = SfxSceneRegistrar.summary(res)


func _set_registering(on: bool) -> void:
	_registering = on
	_update_buttons()


## Send selected only with something checked; send all only with scenes in the list; nothing while sending.
func _update_buttons() -> void:
	if _register_buttons.size() < 2:
		return
	_register_buttons[0].disabled = _registering or _list.get_selected_items().is_empty()
	_register_buttons[1].disabled = _registering or _list.item_count == 0
	_rescan.disabled = _registering
	# Empty list: the button has text ("Search scenes"); with scenes in the list, only the icon remains.
	_rescan.text = T.t("rescan") if _list.item_count == 0 else ""
