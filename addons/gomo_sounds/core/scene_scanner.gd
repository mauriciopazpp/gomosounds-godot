@tool
extends RefCounted

## Lists the scenes (.tscn) in the configured folders via the editor index (without
## opening any file). Skips addons and "base" scenes with nothing of their own.

const SKIP_PREFIXES := ["res://addons", "res://.godot"]
## Support folders: they hold effects, parts and art, not game entities.
const SKIP_DIR_NAMES := [
	"effects", "effect", "vfx", "fx", "particles", "components", "component", "parts",
	"models", "model", "materials", "textures", "shaders", "audio", "sounds", "states", "ui", "hud",
]


static func list_scenes(folders: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for folder in folders:
		if Engine.is_editor_hint():
			var dir := EditorInterface.get_resource_filesystem().get_filesystem_path(folder)
			if dir != null:
				_collect(dir, out)
		else:
			walk_disk(folder, ".tscn", out)
	out.sort()
	return drop_base_scenes(out)


## Removes scenes that serve as a BASE for others in the list (e.g. units/unit.tscn, inherited
## by all units): they are templates, not game entities.
static func drop_base_scenes(paths: PackedStringArray) -> PackedStringArray:
	var bases := {}
	for path in paths:
		var parent := inherited_from(path)
		if parent != "":
			bases[parent] = true
	var out := PackedStringArray()
	for path in paths:
		if not bases.has(path):
			out.append(path)
	return out


## Path of the scene that `path` inherits ("" if none), read from the .tscn without instancing.
static func inherited_from(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ids := {}
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("[ext_resource") and line.contains("type=\"PackedScene\""):
			ids[_attr(line, "id")] = _attr(line, "path")
		elif line.begins_with("[node"):
			# Only the 1st node line matters: it's the root. A root with instance= is an inherited scene.
			if line.contains("parent=") or not line.contains("instance=ExtResource("):
				return ""
			var id := line.get_slice("instance=ExtResource(\"", 1).get_slice("\"", 0)
			return str(ids.get(id, ""))
	return ""


## Value of ` name="..."` on the line. The leading space avoids matching `id=` inside `uid=`.
static func _attr(line: String, name: String) -> String:
	return line.get_slice(" " + name + "=\"", 1).get_slice("\"", 0)


## Disk scan (outside the editor). Skips addons and hidden folders.
static func walk_disk(folder: String, suffix: String, out: PackedStringArray) -> void:
	if suffix == ".tscn" and _skip_dir(folder):
		return
	for prefix: String in SKIP_PREFIXES:
		if folder.begins_with(prefix):
			return
	var d := DirAccess.open(folder)
	if d == null:
		return
	for f in d.get_files():
		var path := folder.path_join(f.trim_suffix(".remap"))
		if path.ends_with(suffix) and not out.has(path):
			out.append(path)
	for sub in d.get_directories():
		if not sub.begins_with("."):
			walk_disk(folder.path_join(sub), suffix, out)


static func _skip_dir(path: String) -> bool:
	for prefix: String in SKIP_PREFIXES:
		if path.begins_with(prefix):
			return true
	return path.trim_suffix("/").get_file().to_lower() in SKIP_DIR_NAMES


static func _collect(dir: EditorFileSystemDirectory, out: PackedStringArray) -> void:
	if _skip_dir(dir.get_path()):
		return
	for i in dir.get_file_count():
		var path := dir.get_file_path(i)
		if path.ends_with(".tscn") and not out.has(path):
			out.append(path)
	for i in dir.get_subdir_count():
		_collect(dir.get_subdir(i), out)


const AUDIO_EXTS := [".wav", ".ogg", ".mp3", ".oggvorbisstr", ".sample"]
const MAX_SCENE_DEPTH := 6


## The scene already has sound: an audio player node, or a referenced audio file, in it or
## in any scene it inherits or instances (read from the .tscn, without opening anything). Sounds that
## Gomo Sounds itself installed (`ignore_dir`) don't count.
static func has_audio(path: String, ignore_dir := "") -> bool:
	return _has_audio(path, ignore_dir, {}, 0)


static func _has_audio(path: String, ignore_dir: String, seen: Dictionary, depth: int) -> bool:
	if depth > MAX_SCENE_DEPTH or seen.has(path):
		return false
	seen[path] = true
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var scenes: Array[String] = []
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("[node") and line.contains("type=\"AudioStreamPlayer"):
			return true
		if line.begins_with("[ext_resource"):
			var res := _attr(line, "path")
			if ignore_dir != "" and res.begins_with(ignore_dir):
				continue
			if line.contains("type=\"AudioStream") or AUDIO_EXTS.any(func(e: String) -> bool: return res.to_lower().ends_with(e)):
				return true
			if line.contains("type=\"PackedScene\"") and res.ends_with(".tscn"):
				scenes.append(res)
	for sub in scenes:
		if _has_audio(sub, ignore_dir, seen, depth + 1):
			return true
	return false


## "res://units/ladybug/ladybug_warrior.tscn" → "Ladybug Warrior".
static func humanize(path: String) -> String:
	return path.get_file().get_basename().capitalize()
