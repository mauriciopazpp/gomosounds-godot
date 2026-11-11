@tool
extends VBoxContainer

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxUi := preload("res://addons/gomo_sounds/ui/sfx_ui.gd")

## An entity's sheet: events, generate variations, listen and choose.

signal changed

var _api: SfxApi
var _player: AudioStreamPlayer
var _header: HBoxContainer
var _image: TextureRect
var _name: Label
var _events: OptionButton
var _prompt: TextEdit
var _duration: SpinBox
var _variations: SpinBox
var _generate: Button
var _gens: VBoxContainer
var _info: Label
var _entity: Dictionary = {}
var _audio_cache := {}


func setup(api: SfxApi) -> void:
	_api = api
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_image = TextureRect.new()
	_image.custom_minimum_size = Vector2(56, 56) * SfxUi.scale()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_name = SfxUi.title("")
	_header = SfxUi.hbox([_image, _name])
	_events = OptionButton.new()
	_events.item_selected.connect(func(_i: int) -> void: _show_event())
	_prompt = TextEdit.new()
	_prompt.custom_minimum_size.y = 64 * SfxUi.scale()
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_duration = _spin(0.5, 30.0, 0.5, "s")
	_variations = _spin(1, 4, 1, "×")
	_variations.value = 3
	_generate = SfxUi.button(T.t("generate"), _on_generate, "Play")
	_gens = VBoxContainer.new()
	_info = SfxUi.label("", true, true)
	for c: Control in [_header, SfxUi.label(T.t("event")), _events, SfxUi.label(T.t("sound_description")), _prompt,
			SfxUi.hbox([SfxUi.label(T.t("duration")), _duration, SfxUi.label(T.t("variations")), _variations]), _generate, _info, _gens]:
		add_child(c)
	visible = false


func _spin(lo: float, hi: float, step: float, suffix: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.suffix = suffix
	return s


func open(entity_id: String) -> void:
	var r := await _api.call_tool("get_entity", {"entity_id": entity_id, "include_image": false})
	if not r.ok:
		_info.text = r.error
		return
	var keep := _selected_event_id()
	_entity = r.data["entity"]
	visible = true
	_name.text = "%s · %s" % [_entity["name"], _folder_label(_entity.get("folderPath", []))]
	_load_image(_entity.get("imageUrl"))
	_events.clear()
	for i in _entity["events"].size():
		var ev: Dictionary = _entity["events"][i]
		var n_chosen: int = (ev.get("chosenGenerationIds", []) as Array).size()
		var mark := "✓%d " % n_chosen if n_chosen > 1 else ("✓ " if n_chosen == 1 else "")
		var folder: Variant = ev.get("folder")
		var origin := ""
		if ev.get("source", "entity") == "folder" and folder is Dictionary:
			origin = " · " + T.t("from_folder", str(folder["name"]))
		_events.add_item("%s%s (%d)%s" % [mark, ev["name"], ev["generations"].size(), origin])
		_events.set_item_metadata(i, str(ev["id"]))
		if origin != "":
			_events.set_item_tooltip(i, T.t("from_folder_tip", str(folder["name"])))
		if str(ev["id"]) == keep:
			_events.select(i)
	_show_event()


func _folder_label(path: Array) -> String:
	if path.is_empty():
		return T.t("no_folder")
	var names: PackedStringArray = []
	for f: Dictionary in path:
		names.append(str(f["name"]))
	return " / ".join(names)


func _load_image(url: Variant) -> void:
	_image.texture = null
	if url == null:
		return
	var f := await _api.get_bytes(str(url))
	if not f.ok:
		return
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if f.content_type.contains("png"):
		err = img.load_png_from_buffer(f.bytes)
	elif f.content_type.contains("jpeg"):
		err = img.load_jpg_from_buffer(f.bytes)
	elif f.content_type.contains("webp"):
		err = img.load_webp_from_buffer(f.bytes)
	if err == OK:
		_image.texture = ImageTexture.create_from_image(img)


func _selected_event_id() -> String:
	return str(_events.get_item_metadata(_events.selected)) if _events.selected >= 0 else ""


func _current_event() -> Dictionary:
	var id := _selected_event_id()
	for ev: Dictionary in _entity.get("events", []):
		if str(ev["id"]) == id:
			return ev
	return {}


func _show_event() -> void:
	for c in _gens.get_children():
		c.queue_free()
	var ev := _current_event()
	if ev.is_empty():
		return
	_prompt.text = str(ev["prompt"])
	_duration.value = float(ev["durationSec"])
	for shared: Dictionary in ev.get("shared", []):
		_gens.add_child(_shared_row(ev, shared))
	var gens: Array = ev["generations"]
	for i in gens.size():
		_gens.add_child(_generation_row(ev, gens[i], gens.size() - i))


func _generation_row(ev: Dictionary, g: Dictionary, n: int) -> Control:
	var chosen: bool = g["chosen"]
	var play := SfxUi.button("", _play.bind(str(g["audioUrl"])), "Play")
	play.tooltip_text = _understood_tip(g)
	var text := SfxUi.label("#%d · %ss%s" % [n, g["durationSec"], T.t("chosen_mark") if chosen else ""])
	text.tooltip_text = play.tooltip_text
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choose := SfxUi.button(T.t("unset") if chosen else T.t("use"), _choose.bind(str(ev["id"]), str(g["id"]), "remove" if chosen else "add"))
	choose.tooltip_text = T.t("list_tip")
	return SfxUi.hbox([play, text, choose])


## Variation tooltip: what the AI understood, in the editor's language, and below it the English sent to the generator.
static func _understood_tip(g: Dictionary) -> String:
	var local: Variant = g.get("promptLocal")
	if local is String and local != "":
		return T.t("understood", local) + "\n\n" + T.t("sent_en", g["prompt"])
	return T.t("understood", g["prompt"])


func _shared_row(ev: Dictionary, g: Dictionary) -> Control:
	var play := SfxUi.button("", _play.bind(str(g["audioUrl"])), "Play")
	play.tooltip_text = g["prompt"]
	var origin := "%s · %s" % [g.get("fromEntity", ""), g.get("fromEvent", "")]
	var text := SfxUi.label(T.t("shared_from", origin) + T.t("chosen_mark"))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var unset := SfxUi.button(T.t("unset"), _choose.bind(str(ev["id"]), str(g["id"]), "remove"))
	return SfxUi.hbox([play, text, unset])


func _play(url: String) -> void:
	var stream: AudioStream = _audio_cache.get(url)
	if stream == null:
		var f := await _api.get_bytes(url)
		if not f.ok:
			_info.text = f.error
			return
		stream = AudioStreamMP3.load_from_buffer(f.bytes) if f.content_type.contains("mpeg") else AudioStreamWAV.load_from_buffer(f.bytes)
		_audio_cache[url] = stream
	_player.stream = stream
	_player.pitch_scale = 1.0
	_player.play()


func _choose(event_id: String, generation_id: String, mode: String) -> void:
	# prune false: in the plugin the person chooses bit by bit; the unchosen ones stay around to swap later.
	var r := await _api.call_tool("choose_sound", {"event_id": event_id, "generation_id": generation_id, "mode": mode, "prune": false})
	if not r.ok:
		_info.text = r.error
		return
	await open(str(_entity["id"]))
	changed.emit()


func _on_generate() -> void:
	var ev := _current_event()
	if ev.is_empty():
		return
	_generate.disabled = true
	_info.text = T.t("generating", int(_variations.value))
	# The server waits for the sound to be ready (queue and generation) and only then responds.
	var r := await _api.call_tool("generate_sounds", {
		"event_id": str(ev["id"]),
		"prompt": _prompt.text.strip_edges(),
		"duration_sec": _duration.value,
		"variations": int(_variations.value),
	}, SfxApi.GENERATE_TIMEOUT_SEC)
	_generate.disabled = false
	if not r.ok:
		_info.text = r.error
		return
	_info.text = T.t("generated", [int(r.data["created"]), int(r.data["credits"])])
	await open(str(_entity["id"]))
	changed.emit()
