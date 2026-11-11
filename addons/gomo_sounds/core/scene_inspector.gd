@tool
extends RefCounted

const SfxSceneScanner := preload("res://addons/gomo_sounds/core/scene_scanner.gd")
const SfxTranslationLookup := preload("res://addons/gomo_sounds/core/translation_lookup.gd")

## Extracts from a scene what can be found without configuration: name, description and
## image. Looks at the root and its exported Resources (e.g. UnitData)
## for properties with common names. Works for any game; whatever isn't found
## falls back to the file name and the editor thumbnail.

const IMAGE_PROPS := ["portrait", "icon", "thumbnail", "avatar", "image", "picture", "card_art", "preview"]
const NAME_PROPS := ["display_name", "unit_name", "title", "label"]
const NAME_KEY_PROPS := ["display_name_key", "name_key", "title_key"]
const DESC_PROPS := ["description", "desc", "flavor_text", "tooltip"]
const DESC_KEY_PROPS := ["description_key", "desc_key", "tooltip_key"]

class Info:
	var path: String
	var name: String
	var description: String
	var image: Texture2D


static func inspect(path: String, tr: SfxTranslationLookup) -> Info:
	var info := Info.new()
	info.path = path
	info.name = SfxSceneScanner.humanize(path)
	var packed := load(path) as PackedScene
	if packed == null:
		return info
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if root == null:
		return info
	var sources: Array[Object] = [root]
	for p in root.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_STORAGE and int(p["type"]) == TYPE_OBJECT:
			var v: Variant = root.get(p["name"])
			if v is Resource and not (v is Texture2D) and not (v is Script) and not (v is PackedScene):
				sources.append(v)
	info.image = _first_texture(sources)
	var n := _first_text(sources, NAME_PROPS, NAME_KEY_PROPS, tr)
	if n != "":
		info.name = n
	info.description = _first_text(sources, DESC_PROPS, DESC_KEY_PROPS, tr)
	root.free()
	return info


static func _first_texture(sources: Array[Object]) -> Texture2D:
	for prop: String in IMAGE_PROPS:
		for s in sources:
			var v: Variant = s.get(prop)
			if v is Texture2D:
				return v
	return null


static func _first_text(sources: Array[Object], props: Array, key_props: Array, tr: SfxTranslationLookup) -> String:
	for prop: String in props:
		for s in sources:
			var v: Variant = s.get(prop)
			if v is String and (v as String).strip_edges() != "":
				var translated := tr.tr_key(v)
				return translated if translated != "" else (v as String)
	for prop: String in key_props:
		for s in sources:
			var v: Variant = s.get(prop)
			if v is String:
				var t := tr.tr_key(v)
				if t != "":
					return t
	return ""
