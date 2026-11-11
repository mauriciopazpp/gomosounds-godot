@tool
extends RefCounted

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

## Registers scenes in Gomo Sounds: discovers each one's name/description/image and
## syncs them in batches (idempotent: registering again only refreshes the image).
## Used by the panel (with editor thumbnails) and the command line (without).

const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxSceneInspector := preload("res://addons/gomo_sounds/core/scene_inspector.gd")
const SfxThumbnailProvider := preload("res://addons/gomo_sounds/core/thumbnail_provider.gd")
const SfxTranslationLookup := preload("res://addons/gomo_sounds/core/translation_lookup.gd")

const BATCH := 8

signal progress(message: String)


## Returns {error: "", created: n, updated: m, skipped: k, inbox_max: x}. `thumbs` may be null
## (outside the editor). Idempotent on the server: an already registered scene only gets its IMAGE updated; nothing
## is duplicated. A full Inbox doesn't stop the upload: `skipped` counts the new scenes left out.
func register(api: SfxApi, game_id: String, paths: PackedStringArray, thumbs: SfxThumbnailProvider) -> Dictionary:
	var tr := SfxTranslationLookup.new()
	var items: Array = []
	for i in paths.size():
		progress.emit(T.t("reading", [paths[i].get_file(), i + 1, paths.size()]))
		items.append(await _item(paths[i], tr, thumbs))
	disambiguate(items)
	var result := {"error": "", "created": 0, "updated": 0, "skipped": 0, "inbox_max": 0}
	for start in range(0, items.size(), BATCH):
		var r := await api.call_tool("sync_scenes", {"game_id": game_id, "items": items.slice(start, start + BATCH)})
		if not r.ok:
			result["error"] = r.error
			return result
		for e: Dictionary in r.data.get("entities", []):
			result["created" if e.get("created", false) else "updated"] += 1
		result["skipped"] += int(r.data.get("skipped", 0))
		result["inbox_max"] = int(r.data.get("inboxMax", result["inbox_max"]))
	return result


## The end-of-upload sentence (panel and command line): what went in and, with the Inbox full,
## how many scenes were left out.
static func summary(res: Dictionary) -> String:
	var text := T.t("sync_done", [res["created"], res["updated"]])
	if int(res.get("skipped", 0)) > 0:
		text += " " + T.t("inbox_full_skipped", [res["inbox_max"], res["skipped"]])
	return text


## Repeated names (e.g. three "Worker", one per species) get the scene's folder
## ("Worker · Ladybug"); if still repeated, the file name. Without this the list and
## search become ambiguous.
static func disambiguate(items: Array) -> void:
	var original := {}
	for it: Dictionary in items:
		original[it["externalId"]] = it["name"]
	_suffix_duplicates(items, original, func(path: String) -> String: return path.get_base_dir().get_file().capitalize())
	_suffix_duplicates(items, original, func(path: String) -> String: return path.get_file().get_basename().capitalize())


## Where the name still repeats, replace it with "<original name> · <suffix>".
static func _suffix_duplicates(items: Array, original: Dictionary, suffix_of: Callable) -> void:
	var count := {}
	for it: Dictionary in items:
		count[it["name"]] = int(count.get(it["name"], 0)) + 1
	for it: Dictionary in items:
		if int(count[it["name"]]) > 1:
			var path := str(it["externalId"])
			it["name"] = ("%s · %s" % [original[path], suffix_of.call(path)]).substr(0, 80)


func _item(path: String, tr: SfxTranslationLookup, thumbs: SfxThumbnailProvider) -> Dictionary:
	var info := SfxSceneInspector.inspect(path, tr)
	var tex: Texture2D = info.image
	if tex == null and thumbs != null:
		tex = await thumbs.thumbnail(path)
	# The folder comes from the scene path (the server creates "Units", "Buildings"... with the project's names).
	var item := {"externalId": path, "name": info.name.substr(0, 80)}
	if info.description != "":
		item["description"] = info.description.substr(0, 400)
	var png := SfxThumbnailProvider.to_png_base64(tex)
	if png != "":
		item["image"] = {"mimeType": "image/png", "base64": png}
	return item

