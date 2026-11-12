extends Node

## Plays, in the game, the sounds installed by Gomo Sounds (catalog gomo_sounds.tres). It is an AUTOLOAD
## named SfxLibrary, registered by the plugin (not class_name): an autoload always ships with the
## exported game, while a class_name script only referenced by name is left out by presets that
## export only the selected scenes (the game would not even start: "SfxLibrary not declared").
##
##   SfxLibrary.play("@interface/buttons.click", self)   # by catalog key
##   SfxLibrary.play_event(self, "Attack")                 # by the node's scene (no key to type)
##   SfxLibrary.play_first(self, ["Gunshot", "Attack"])   # the 1st name the scene has
##   var steps := SfxLibrary.attach_event(self, "Walk")       # loop attached to the node (follows it)
##   SfxLibrary.play_music("@music.village-theme")          # the chosen versions in sequence, with crossfade
##   SfxLibrary.alias_scene("res://arena/arena_archer.tscn", "res://units/archer.tscn")  # a copy plays the original's sounds
##
## A ONE-SHOT sound plays on its own layer (a child of this autoload), where the node is: it
## outlives the node (the death sound plays even after the unit is freed) and leaves nothing hanging in
## the simulation scene. A loop (`attach_*`) is a child of the node so it moves along; the caller stops/frees it.
## 3D when the node is a Node3D, 2D when it is a Node2D, otherwise an interface sound.
## Event with SEVERAL sounds: picks one at random on each play, never repeating the previous one.
## Pitch varies slightly on each play: identical repetition tires the ear.
## (Sound randomness is cosmetic: it touches nothing the game simulation reads.)

## The folder comes from project.godot (the plugin writes it on install); without it, the default and the old versions' ones.
## (sfx_studio/...: the name used by old plugin versions, for games exported before the rename.)
const SETTING_DIRS := ["gomo_sounds/install_dir", "gomo_sounds/custom_dir", "sfx_studio/install_dir", "sfx_studio/custom_dir"]
const DIRS := ["res://gomosounds", "res://audio/sfx_studio"]
const CATALOG_FILE := "gomo_sounds.tres"
const LEGACY_MANIFEST := "manifest.json"
const PITCH_JITTER := 0.06

## Audio bus for the players (the game sets it once, e.g. "SFX"). Missing = Master.
static var bus := "Master"
## Cap on one-shot sounds playing at once: past it, the new one is skipped (the ear can't tell, and
## each player has a cost). Finished players go back to a pool instead of being freed.
static var max_voices := 24
## Bus for 3D (world) sounds only, e.g. "World", so the game can change their volume without touching
## the interface. Empty or missing = the shared `bus`.
static var bus_3d := ""
## Range of 3D sounds in world units (0 = engine default).
static var max_distance_3d := 0.0
## Distance at which a 3D sound plays at full volume; at twice that, about 6 dB quieter (0 = engine default).
static var unit_size_3d := 0.0
## Bus for the music (play_music), e.g. "Music", so the game can mix it apart from the effects. Empty = `bus`.
static var bus_music := ""
## Seconds of overlap between two versions of a track (and of the fade when stopping).
static var music_crossfade_sec := 2.0

var _music: _MusicDeck = null

static var _pool: Dictionary = {}
static var _active := 0

static var _by_key: Dictionary = {}
## Key → the tab on the site ("music", "ambience"...; "" in catalogs older than 0.6.0).
static var _section_by_key: Dictionary = {}
static var _by_scene_event: Dictionary = {}
## Event (comparable name) → the 1st key with that event, from any scene or folder.
static var _key_by_event: Dictionary = {}
## Scene → {name: entity name on the site, events: [names of events with sound, as on the site]}.
static var _events_of_scene: Dictionary = {}
static var _last: Dictionary = {}
static var _loaded := false
## Scene → scene whose sounds it uses (see alias_scene).
static var _alias_of_scene: Dictionary = {}


func play(key: String, at: Node, volume_db: float = 0.0) -> Node:
	return _spawn(_pick_key(key), at, volume_db, false)


## Finds the sound by the node's `scene_file_path` (the externalId the plugin registered).
func play_event(node: Node, event_name: String, volume_db: float = 0.0) -> Node:
	return _spawn(_pick_event(node, event_name), node, volume_db, false)


## Stops a ONE-SHOT sound that is still playing (e.g. a new click cuts off the previous response)
## and returns the player for reuse. Just `stop()` on the player is not enough: Godot doesn't emit
## `finished` when stopped manually, and the player never returned to the pool (the voice cap filled up).
func stop(player: Node) -> void:
	if player == null or not is_instance_valid(player) or not player.get("playing"):
		return
	player.call("stop")
	player.emit_signal("finished")


## The sound of the event of node `owner`, played at the position of ANOTHER node `at` (e.g. the shot impact comes
## from the shooter's scene, but plays where the projectile hit).
func play_event_at(owner: Node, event_name: String, at: Node, volume_db: float = 0.0) -> Node:
	return _spawn(_pick_event(owner, event_name), at, volume_db, false)


## The node's event sound, but without position: plays the same at any distance (response to a click,
## like selecting or giving an order, which the player must hear even with the camera far away).
func play_event_flat(node: Node, event_name: String, volume_db: float = 0.0) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return _spawn(_pick_event(node, event_name), _layer(node), volume_db, false)


## The first name the node's scene has (for units that call the same thing by different names).
func play_first(node: Node, event_names: Array, volume_db: float = 0.0) -> Node:
	for name: String in event_names:
		if has_event(node, name):
			return play_event(node, name, volume_db)
	return null


## Loop attached to the node (footsteps, engine): follows the node and dies with it. Returns the player so it can be stopped.
func attach(key: String, node: Node, volume_db: float = 0.0) -> Node:
	return _spawn(_pick_key(key), node, volume_db, true)


func attach_event(node: Node, event_name: String, volume_db: float = 0.0) -> Node:
	return _spawn(_pick_event(node, event_name), node, volume_db, true)


func has_event(node: Node, event_name: String) -> bool:
	_ensure_loaded()
	return _by_scene_event.has(_event_id(node, event_name))


## Scenes with installed event sounds → entity name and events (e.g. {"res://units/x.tscn":
## {"name": "Archer", "events": ["Select", "Death"]}}). For tools: a screen listing what
## each entity plays, a test scene.
func scene_events() -> Dictionary:
	_ensure_loaded()
	return _events_of_scene.duplicate(true)


## The key of a sound by the event NAME, whatever entity or folder it is in ("" if there is
## none). For something in the world that isn't an entity on the site (e.g. "Butterfly flying" stored in a scout).
func event_key(event_name: String) -> String:
	_ensure_loaded()
	return str(_key_by_event.get(_norm(event_name), ""))


func has_sound(key: String) -> bool:
	_ensure_loaded()
	return _by_key.has(key)


## The tab of the event on the site ("music", "ambience", "effects", "interface"; "" when unknown).
func section_of(key: String) -> String:
	_ensure_loaded()
	return str(_section_by_key.get(key, ""))


## Plays a MUSIC event: the chosen versions in sequence, crossfading from one to the next, and
## back to the first at the end. Only ONE track plays at a time (a new call fades the previous one
## out). The players are children of this autoload, on `bus_music` (or `bus`), without position:
## music is not in the world. Returns false if the key has no files.
func play_music(key: String, volume_db: float = 0.0, crossfade_sec: float = -1.0) -> bool:
	_ensure_loaded()
	var paths: Array = _by_key.get(key, [])
	if paths.is_empty() or not is_inside_tree():
		return false
	stop_music(crossfade_sec)
	_music = _MusicDeck.new(self, paths, volume_db, crossfade_sec if crossfade_sec >= 0.0 else music_crossfade_sec)
	_music.start()
	return true


## Fades the playing track out (default: the crossfade time) and frees its players.
func stop_music(fade_sec: float = -1.0) -> void:
	if _music != null:
		_music.stop(fade_sec if fade_sec >= 0.0 else music_crossfade_sec)
		_music = null


## Whether a track is playing (or fading in/out).
func music_playing() -> bool:
	return _music != null


## Rereads the catalog (after installing sounds with the game running from the editor).
func reload_catalog() -> void:
	_loaded = false
	_ensure_loaded()


## Old shortcut. Through the autoload (SfxLibrary.reload()) it lands here; through the script (preload) the name clashes with
## Godot's Script.reload, which is why the proper name is reload_catalog.
func reload() -> void:
	reload_catalog()


## Scene `from` plays the sounds installed for scene `to` (e.g. a game mode with its own copies of the
## units, built on other scenes). Survives reload_catalog. Empty `to` removes the alias.
func alias_scene(from: String, to: String) -> void:
	if to == "":
		_alias_of_scene.erase(from)
	else:
		_alias_of_scene[from] = to


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_by_key.clear()
	_section_by_key.clear()
	_by_scene_event.clear()
	_events_of_scene.clear()
	_key_by_event.clear()
	for dir: String in _candidate_dirs():
		if _load_catalog(dir + "/" + CATALOG_FILE) or _load_legacy(dir):
			return


static func _candidate_dirs() -> Array:
	var dirs: Array = []
	for key: String in SETTING_DIRS:
		var d := str(ProjectSettings.get_setting(key, "")).trim_suffix("/")
		if d.begins_with("res://") and d not in dirs:
			dirs.append(d)
	for d: String in DIRS:
		if d not in dirs:
			dirs.append(d)
	return dirs


## Catalog (.tres): each file by uid (the user may have moved the folder), otherwise by path.
static func _load_catalog(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	# No cache: after an install in the editor, reload() must see the new catalog.
	var catalog := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if catalog == null:
		return false
	# Catalog = plain Resource with the data in the "gomo_sounds" metadata (the 2026-09-26 one had its own
	# script with the list in `sounds`: read both).
	var data: Variant = catalog.get_meta("gomo_sounds", {"sounds": catalog.get("sounds")})
	var sounds: Variant = (data as Dictionary).get("sounds") if data is Dictionary else null
	if not sounds is Array:
		return false
	for s: Dictionary in sounds:
		var files: Array = s.get("files", [])
		var uids: Array = s.get("uids", [])
		var paths: Array = []
		for i in files.size():
			paths.append(_resolve(str(uids[i]) if i < uids.size() else "", str(files[i])))
		_index(s, paths)
	return true


static func _resolve(uid: String, path: String) -> String:
	if uid.begins_with("uid://"):
		var id := ResourceUID.text_to_id(uid)
		if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id) and ResourceLoader.exists(ResourceUID.get_id_path(id)):
			return ResourceUID.get_id_path(id)
	return path


## Install from old plugin versions (manifest.json with paths relative to the folder).
static func _load_legacy(dir: String) -> bool:
	var path := dir + "/" + LEGACY_MANIFEST
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	for s: Dictionary in (parsed as Dictionary).get("sounds", []):
		var paths: Array = []
		for f in s.get("files", [s.get("file", "")]):
			if str(f) != "":
				paths.append(dir + "/" + str(f))
		_index(s, paths)
	return true


static func _index(s: Dictionary, paths: Array) -> void:
	_by_key[str(s.get("key", ""))] = paths
	# Old catalogs have no `section`: a folder event of the Music tab still has the "@music" key prefix ("@music.theme", "@music/battles.boss").
	_section_by_key[str(s.get("key", ""))] = str(s.get("section", "music" if str(s.get("key", "")).begins_with("@music") else ""))
	if not paths.is_empty():
		_key_by_event.get_or_add(_norm(str(s.get("event", ""))), str(s.get("key", "")))
	var ext_id := str(s.get("externalId", ""))
	if ext_id != "" and ext_id != "<null>":
		_by_scene_event[ext_id + "|" + _norm(str(s.get("event", "")))] = paths
		var entry: Dictionary = _events_of_scene.get_or_add(ext_id, {"name": str(s.get("entity", "")), "events": []})
		var names: Array = entry["events"]
		var ev := str(s.get("event", ""))
		if not paths.is_empty() and not names.any(func(n: String) -> bool: return _norm(n) == _norm(ev)):
			names.append(ev)


const _ACCENTS := {"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "é": "e", "è": "e", "ê": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u", "ç": "c", "ñ": "n"}


## Event name for comparison: lowercase, no accents and no extra spaces. "Café",
## "Cafe" and "café " are the same event: the name on the site doesn't always match the code.
static func _norm(event_name: String) -> String:
	var out := event_name.strip_edges().to_lower()
	for a: String in _ACCENTS:
		out = out.replace(a, _ACCENTS[a])
	return out


## Picks one from the list, without repeating the last one played for that key.
static func _pick(id: String, paths: Array) -> String:
	if paths.is_empty():
		return ""
	if paths.size() == 1:
		return paths[0]
	var i := randi() % paths.size()  # det: cosmetic
	if paths[i] == _last.get(id, ""):
		i = (i + 1) % paths.size()
	_last[id] = paths[i]
	return paths[i]


static func _pick_key(key: String) -> String:
	_ensure_loaded()
	return _pick(key, _by_key.get(key, []))


static func _pick_event(node: Node, event_name: String) -> String:
	_ensure_loaded()
	var id := _event_id(node, event_name)
	return _pick(id, _by_scene_event.get(id, []))


static func _event_id(node: Node, event_name: String) -> String:
	var scene := node.scene_file_path
	return str(_alias_of_scene.get(scene, scene)) + "|" + _norm(event_name)


## `attached` = loop as a child of the node; otherwise, a one-shot sound on the layer, at the node's position.
static func _spawn(file: String, at: Node, volume_db: float, attached: bool) -> Node:
	if file == "" or at == null or not at.is_inside_tree():
		return null
	var stream := load(file) as AudioStream
	if stream == null:
		return null
	if attached:
		# Copy: the loaded resource is shared, and turning it into a loop would make the same one-shot
		# sound play forever somewhere else.
		stream = stream.duplicate()
		_make_loop(stream)
	elif _is_looping(stream):
		# A ONE-SHOT sound (play/play_event) always plays once, even if marked as loop on the site
		# or imported with loop: otherwise it never ended, the player never returned to the pool and each
		# play stacked one more endless sound. Loops only go through attach. Copy, for the same reason as above.
		stream = stream.duplicate()
		_make_one_shot(stream)
	if not attached and _active >= max_voices:
		return null
	var player: Node = _take_player(at, attached)
	if player == null:
		return null
	player.set("stream", stream)
	player.set("volume_db", volume_db)
	player.set("bus", bus_3d if player is AudioStreamPlayer3D and bus_3d != "" and AudioServer.get_bus_index(bus_3d) >= 0 else bus)
	player.set("pitch_scale", 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER))  # det: cosmetic
	if attached:
		at.add_child(player)
	else:
		_active += 1
		if at is Node3D:
			(player as Node3D).global_position = (at as Node3D).global_position
		elif at is Node2D:
			(player as Node2D).global_position = (at as Node2D).global_position
	player.call("play")
	return player


## Player for the node: loop = new, child of the node; one-shot = from the layer's pool (or new, if the pool is empty).
static func _take_player(at: Node, attached: bool) -> Node:
	var kind := _kind_of(at)
	if attached:
		return _new_player(kind)
	var free: Array = _pool.get(kind, [])
	if not free.is_empty():
		return free.pop_back()
	var player := _new_player(kind)
	var layer := _layer(at)
	if layer == null:
		return null
	layer.add_child(player)
	player.connect("finished", _on_finished.bind(player, kind))
	return player


static func _on_finished(player: Node, kind: String) -> void:
	_active = maxi(0, _active - 1)
	if not _pool.has(kind):
		_pool[kind] = []
	(_pool[kind] as Array).append(player)


static func _kind_of(at: Node) -> String:
	return "3d" if at is Node3D else "2d" if at is Node2D else "ui"


static func _new_player(kind: String) -> Node:
	match kind:
		"3d":
			var p := AudioStreamPlayer3D.new()
			if max_distance_3d > 0.0:
				p.max_distance = max_distance_3d
			if unit_size_3d > 0.0:
				p.unit_size = unit_size_3d
			return p
		"2d":
			return AudioStreamPlayer2D.new()
	return AudioStreamPlayer.new()


## The layer for one-shot sounds: this autoload. Without it in the tree (script used via preload, tests),
## the scene root.
static func _layer(at: Node) -> Node:
	var root := at.get_tree().root
	return root.get_node_or_null("SfxLibrary") if root.has_node("SfxLibrary") else root


## Safeguard for sounds marked as loop on the site, in case the import didn't enable it (installed from the
## command line, or the user changed the import).
static func _is_looping(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return "loop" in stream and bool(stream.get("loop"))


static func _make_one_shot(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif "loop" in stream:
		stream.set("loop", false)


static func _make_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif "loop" in stream:
		stream.set("loop", true)


## The music deck: two players, the next version fades in while the current one fades out. The
## catalog order is the order of the chosen versions on the site. Each step is a scheduled one-shot:
## when the current version is `crossfade` seconds from its end, the next one starts and the two cross.
## (Cosmetic: nothing the game simulation reads.)
class _MusicDeck:
	var _host: Node
	var _paths: Array
	var _volume_db: float
	var _crossfade: float
	var _index := -1
	var _current: AudioStreamPlayer = null
	var _timer: SceneTreeTimer = null
	var _stopped := false

	func _init(host: Node, paths: Array, volume_db: float, crossfade: float) -> void:
		_host = host
		_paths = paths
		_volume_db = volume_db
		_crossfade = maxf(0.0, crossfade)

	func start() -> void:
		_next()

	func stop(fade_sec: float) -> void:
		_stopped = true
		if _timer != null and _timer.timeout.is_connected(_next):
			_timer.timeout.disconnect(_next)
		_timer = null
		if _current != null:
			_fade_out(_current, fade_sec)
			_current = null

	func _next() -> void:
		if _stopped or _paths.is_empty():
			return
		_index = (_index + 1) % _paths.size()
		var stream := load(str(_paths[_index])) as AudioStream
		if stream == null:
			return
		# A version marked as loop on the site would never end: the deck decides the sequence, not the file.
		if SfxLibrary_is_looping(stream):
			stream = stream.duplicate()
			SfxLibrary_make_one_shot(stream)
		var player := AudioStreamPlayer.new()
		player.stream = stream
		var music_bus: String = _host.get("bus_music")
		var default_bus: String = _host.get("bus")
		player.bus = music_bus if music_bus != "" and AudioServer.get_bus_index(music_bus) >= 0 else default_bus
		player.volume_db = _volume_db if _current == null else -60.0
		_host.add_child(player)
		player.play()
		if _current != null:
			# The cross: the old one goes out while the new one comes in, over the same seconds.
			_fade_out(_current, _crossfade)
			var tween := _host.create_tween()  # det: cosmetic
			tween.tween_property(player, "volume_db", _volume_db, _crossfade)
		_current = player
		# The next version starts `crossfade` seconds before this one ends (never before it started playing).
		var length := stream.get_length()
		var wait := maxf(0.1, length - _crossfade) if length > 0.0 else 0.0
		if wait <= 0.0:
			# Unknown length (a stream Godot cannot measure): plays to the end, then the next one, without the cross.
			player.finished.connect(_next, CONNECT_ONE_SHOT)
			return
		_timer = _host.get_tree().create_timer(wait)
		_timer.timeout.connect(_next)

	func _fade_out(player: AudioStreamPlayer, seconds: float) -> void:
		if seconds <= 0.0:
			player.queue_free()
			return
		var tween := _host.create_tween()  # det: cosmetic
		tween.tween_property(player, "volume_db", -60.0, seconds)
		tween.tween_callback(player.queue_free)

	static func SfxLibrary_is_looping(stream: AudioStream) -> bool:
		if stream is AudioStreamWAV:
			return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
		return "loop" in stream and bool(stream.get("loop"))

	static func SfxLibrary_make_one_shot(stream: AudioStream) -> void:
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		elif "loop" in stream:
			stream.set("loop", false)
