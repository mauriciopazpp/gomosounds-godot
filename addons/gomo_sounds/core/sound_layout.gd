@tool
extends RefCounted

const SafeFileName := preload("res://addons/gomo_sounds/core/safe_file_name.gd")

## WHERE each sound lives in the project (single source for the modes). Only computes paths; whoever decides
## whether it may write there (someone else's file, name already taken) is the planner.
##
##   GOMO          <root>/<entity>/<event>.wav               everything in one folder (default)
##   SCENE_FOLDER  <scene folder>/sounds/<scene>_<event>.wav
##   BESIDE_SCENE  <scene folder>/<scene>_<event>.wav
##   CUSTOM        <chosen folder>/<entity>/<event>.wav      (like GOMO, in another folder)
##
## In scene modes, sounds WITHOUT a scene (Interface, Ambience, entity created on the site) and sounds INHERITED from
## a folder (one file for several entities) stay in the root: copying to each scene would duplicate them.

enum Mode { GOMO, SCENE_FOLDER, BESIDE_SCENE, CUSTOM }

const MODE_IDS := ["gomo", "scene_folder", "beside_scene", "custom"]


static func mode_from_id(id: String) -> Mode:
	var i := MODE_IDS.find(id)
	return (i if i >= 0 else Mode.GOMO) as Mode


## `sound` = one entry of the server manifest; `index`/`count` = which of the chosen ones.
static func target(mode: Mode, root: String, sound: Dictionary, index: int, count: int, ext: String) -> String:
	# The 1st variation never gets a number: choosing a 2nd one on the site creates attack_2.wav without renaming the
	# attack.wav already in the project (and in scenes).
	var suffix := "_%d" % (index + 1) if index > 0 else ""
	var event := SafeFileName.slug(str(sound.get("event", "")))
	var file := event + suffix + "." + _ext(ext)
	var scene := _own_scene(sound)
	if mode in [Mode.SCENE_FOLDER, Mode.BESIDE_SCENE] and scene != "":
		var dir := scene.get_base_dir()
		if mode == Mode.SCENE_FOLDER:
			dir += "/sounds"
		return dir + "/" + SafeFileName.slug(scene.get_file().get_basename()) + "_" + file
	return root + "/" + "/".join(_gomo_dirs(sound)) + "/" + file


## Scene mode, the entity's own sound, but the scene is no longer at the path the site knows.
static func scene_gone(mode: Mode, sound: Dictionary) -> bool:
	if mode not in [Mode.SCENE_FOLDER, Mode.BESIDE_SCENE] or sound.get("inheritedFrom") != null:
		return false
	var ext_id := str(sound.get("externalId", ""))
	return ext_id.begins_with("res://") and not FileAccess.file_exists(ext_id)


## The entity's own scene, if the sound is its own and the scene still exists in the project.
static func _own_scene(sound: Dictionary) -> String:
	var ext_id := str(sound.get("externalId", ""))
	if sound.get("inheritedFrom") != null or not ext_id.begins_with("res://"):
		return ""
	if not (ext_id.ends_with(".tscn") or ext_id.ends_with(".scn")):
		return ""
	return ext_id if FileAccess.file_exists(ext_id) else ""


## The folders of the path suggested by the server ("sounds/<owner>/<event>.wav"), each with a
## safe name.
static func _gomo_dirs(sound: Dictionary) -> PackedStringArray:
	var paths: Array = sound.get("paths", [sound.get("path", "")])
	var rel := str(paths[0]) if not paths.is_empty() else ""
	var parts := rel.get_base_dir().split("/", false)
	# "sounds/" (the root is already the sounds folder) and "_pastas/" (Portuguese name for everyone) are dropped:
	# a folder's sound lives in <root>/<folder>/, next to the entity folders.
	for skip: String in ["sounds", "_pastas"]:
		if not parts.is_empty() and parts[0] == skip:
			parts.remove_at(0)
	var out := PackedStringArray()
	for p in parts:
		out.append(SafeFileName.slug(p, "folder"))
	if out.is_empty():
		out.append(SafeFileName.slug(str(sound.get("entity", "")), "sounds"))
	return out


static func _ext(ext: String) -> String:
	var e := ext.to_lower()
	return e if e in ["wav", "ogg", "mp3"] else "wav"
