@tool
extends RefCounted

const InstallCatalog := preload("res://addons/gomo_sounds/core/install_catalog.gd")
const SoundLayout := preload("res://addons/gomo_sounds/core/sound_layout.gd")

## Decides, WITHOUT writing anything, what the install will do with each file. The rules that
## protect the user's project live here:
##   - a file that is NOT the plugin's is never overwritten, moved or deleted: the new sound gets
##     another name (_2, _3…);
##   - a plugin file someone EDITED (different hash) isn't either: it stays as is and the
##     game plays the user's version;
##   - a name that differs only in case ("Attack.wav" vs "attack.wav") counts as taken: on Windows and
##     macOS it's the same file.
##
## Operations: new, update (new version in the same place), restore (was ours and went missing), keep,
## move / move_update (the place changed: mode, folder or name on the site; never a file the USER
## moved within Godot, which stays "pinned" where they put it), edited (keeps the user's),
## remove (gone from the site, untouched), left (gone from the site, removal turned off), left_edited (gone from the
## site but edited: stays, and no longer belongs to the plugin).

const WRITES := ["new", "update", "restore", "move_update"]


static func plan(manifest: Dictionary, catalog: Resource, mode: int, root: String, remove_missing: bool) -> Dictionary:
	InstallCatalog.forget_moves()
	var ctx := _Context.new(catalog, _legacy_slots(manifest))
	var actions: Array = []
	var sounds: Array = []
	for s: Dictionary in manifest.get("sounds", []):
		var urls: Array = s.get("files", [s.get("file", "")])
		var rels: Array = s.get("paths", [s.get("path", "")])
		var versions: Array = s.get("fileIds", s.get("generationIds", []))
		var loops: Array = s.get("loops", [])
		# `bpms`: the tempo of each music file (site 0.15.0+); an older site sends none = unknown.
		var bpms: Array = s.get("bpms", [])
		var key := str(s.get("key", ""))
		# `section`: the tab on the site (music plays its chosen files in sequence; the rest picks one at random).
		var sound := {"key": key, "event": s.get("event", ""), "entity": s.get("entity", ""), "externalId": s.get("externalId", ""), "section": str(s.get("section", "")), "slots": []}
		for i in urls.size():
			if key == "" or str(urls[i]) == "":
				continue
			var slot := InstallCatalog.slot_for(s, i)
			sound["slots"].append(slot)
			# The same file in several sounds (folder event inherited by N entities): a single file.
			if ctx.seen.has(slot):
				continue
			ctx.seen[slot] = true
			var ext := str(rels[i]).get_extension() if i < rels.size() else "wav"
			var a := {
				"slot": slot, "url": str(urls[i]), "version": str(versions[i]) if i < versions.size() else "",
				"loop": bool(loops[i]) if i < loops.size() else false,
				"bpm": bpm_at(bpms, i),
				"want": SoundLayout.target(mode as SoundLayout.Mode, root, s, i, urls.size(), ext),
				"scene_gone": SoundLayout.scene_gone(mode as SoundLayout.Mode, s),
			}
			_decide(a, ctx)
			ctx.claim(a["path"], slot)
			actions.append(a)
		sounds.append(sound)
	for slot: String in ctx.owned:
		if not ctx.seen.has(slot) and not ctx.adopted.has(slot):
			var gone := _removal(ctx.owned[slot], remove_missing)
			if not gone.is_empty():
				actions.append(gone)
	return {"actions": actions, "sounds": sounds, "first_install": ctx.owned.is_empty()}


## Installs from before per-event identity recorded "<key>#<n>": map to the new slot.
static func _legacy_slots(manifest: Dictionary) -> Dictionary:
	var out := {}
	for s: Dictionary in manifest.get("sounds", []):
		var urls: Array = s.get("files", [s.get("file", "")])
		for i in urls.size():
			out[InstallCatalog.slot_id(str(s.get("key", "")), i)] = InstallCatalog.slot_for(s, i)
	return out


## The tempo of file `i`: a positive number becomes a float; missing, null or zero = unknown (null).
static func bpm_at(bpms: Array, i: int) -> Variant:
	var v: Variant = bpms[i] if i < bpms.size() else null
	if (v is int or v is float) and float(v) > 0:
		return float(v)
	return null


## A file the site wants in the project: what to do with it.
static func _decide(a: Dictionary, ctx: _Context) -> void:
	var entry: Dictionary = ctx.owned.get(a["slot"], {})
	if entry.is_empty():
		entry = ctx.adopt(a["want"], a["slot"])
	if entry.is_empty():
		a["op"] = "new"
		a["path"] = ctx.free_path(a["want"], a["slot"])
		return
	var cur := InstallCatalog.current_path(entry)
	a["entry"] = entry
	if not FileAccess.file_exists(cur):
		a["op"] = "restore"
		a["path"] = ctx.free_path(a["want"], a["slot"])
	elif not InstallCatalog.is_intact(entry, cur):
		a["op"] = "edited"
		a["path"] = cur
		a["outdated"] = str(entry.get("version", "")) != a["version"]
	else:
		var changed: bool = str(entry.get("version", "")) != a["version"] or bool(entry.get("loop", false)) != a["loop"]
		# The user moved the file within Godot (the uid found it elsewhere): stays where they put it, forever.
		if cur != str(entry.get("path", "")) or bool(entry.get("pinned", false)):
			a["pinned"] = true
			a["want"] = cur
		# The scene is gone from the path the site knows (renamed/moved, not synced yet): the sound
		# stays where it is instead of going back to the Gomo folder.
		elif a["scene_gone"]:
			a["want"] = cur
		if cur.to_lower() == str(a["want"]).to_lower():
			a["op"] = "update" if changed else "keep"
			a["path"] = cur
		else:
			a["from"] = cur
			a["path"] = ctx.free_path(a["want"], a["slot"])
			a["op"] = "move_update" if changed else "move"
			if a["path"] == cur:
				a["op"] = "update" if changed else "keep"
		# Same file, but the catalog doesn't have the tempo the site knows (a catalog from before 0.7.0): only the
		# catalog is rewritten, nothing is downloaded.
		if a["op"] == "keep" and entry.get("bpm") != a["bpm"]:
			a["bpm_changed"] = true


static func _removal(entry: Dictionary, remove_missing: bool) -> Dictionary:
	var cur := InstallCatalog.current_path(entry)
	if not FileAccess.file_exists(cur):
		return {}
	var a := {"slot": entry.get("slot", ""), "path": cur, "entry": entry}
	if not remove_missing:
		a["op"] = "left"
	elif InstallCatalog.is_intact(entry, cur):
		a["op"] = "remove"
	else:
		a["op"] = "left_edited"
	return a


## How many of each operation (for the summary).
static func counts(plan_data: Dictionary) -> Dictionary:
	var out := {}
	for a: Dictionary in plan_data["actions"]:
		out[a["op"]] = int(out.get(a["op"], 0)) + 1
	return out


## Files the user edited that have a NEW version on the site (the dock offers to replace them).
static func outdated_edits(plan_data: Dictionary) -> int:
	var n := 0
	for a: Dictionary in plan_data["actions"]:
		n += 1 if a["op"] == "edited" and a.get("outdated", false) else 0
	return n


## The user asked: edited files with a new version on the site get updated (in the same place).
static func accept_site_versions(plan_data: Dictionary) -> void:
	for a: Dictionary in plan_data["actions"]:
		if a["op"] == "edited" and a.get("outdated", false):
			a["op"] = "update"
			a["overwrote_edit"] = true


## Ask for confirmation first? The first time and whenever something moves, goes missing or runs
## into a user's file. Just downloading a new version in the same place doesn't need it.
static func needs_confirmation(plan_data: Dictionary) -> bool:
	if plan_data["first_install"] and not plan_data["actions"].is_empty():
		return true
	for a: Dictionary in plan_data["actions"]:
		if a["op"] in ["move", "move_update", "remove", "left_edited"] or renamed(a):
			return true
	return outdated_edits(plan_data) > 0


## The sound got another name because the right place already had someone else's file.
static func renamed(a: Dictionary) -> bool:
	return a.has("want") and a.has("path") and a["op"] in ["new", "restore", "move", "move_update"] \
		and str(a["path"]).to_lower() != str(a["want"]).to_lower()


## Decision state: what belongs to the plugin, which paths were already promised and what exists on disk.
class _Context:
	var owned := {}
	var owned_at := {}
	var claimed := {}
	var seen := {}
	var adopted := {}
	var _news := {}
	var _listing := {}

	## `legacy`: old slot → new. If two old ones map to the same new one (the copies of an inherited sound),
	## the first keeps the identity and the other copies go out as "no longer on the site".
	func _init(catalog: Resource, legacy: Dictionary) -> void:
		for v: String in legacy.values():
			_news[v] = true
		for e: Dictionary in catalog.get("files"):
			var slot := str(e.get("slot", ""))
			if not _news.has(slot) and legacy.has(slot) and not owned.has(legacy[slot]):
				e = e.duplicate()
				e["slot"] = legacy[slot]
				slot = e["slot"]
			owned[slot] = e
			owned_at[InstallCatalog.current_path(e).to_lower()] = slot

	## Unregistered sound whose place has a plugin file no site sound claims anymore
	## (the key changed on the site): it's the same sound; inherits the registry instead of becoming _2 + deleting the old one.
	func adopt(want: String, slot: String) -> Dictionary:
		var other: String = owned_at.get(want.to_lower(), "")
		if other == "" or _news.has(other) or adopted.has(other):
			return {}
		adopted[other] = true
		owned_at[want.to_lower()] = slot
		var e: Dictionary = (owned[other] as Dictionary).duplicate()
		e["slot"] = slot
		return e

	func claim(path: String, slot: String) -> void:
		claimed[path.to_lower()] = slot

	## The requested path, or the first "_2", "_3"… that belongs to no one.
	func free_path(want: String, slot: String) -> String:
		var base := want.get_basename()
		var ext := want.get_extension()
		var candidate := want
		var n := 2
		while not _is_free(candidate, slot):
			candidate = "%s_%d.%s" % [base, n, ext]
			n += 1
		return candidate

	func _is_free(path: String, slot: String) -> bool:
		var low := path.to_lower()
		if claimed.has(low) and claimed[low] != slot:
			return false
		if _exists_ignoring_case(path):
			return owned_at.get(low, "") == slot
		return true

	## Is there a file or folder with that name, in any case? (lists the folder only once)
	func _exists_ignoring_case(path: String) -> bool:
		var dir := path.get_base_dir()
		if not _listing.has(dir):
			var names := {}
			if DirAccess.dir_exists_absolute(dir):
				for f in DirAccess.get_files_at(dir):
					names[f.to_lower()] = true
				for d in DirAccess.get_directories_at(dir):
					names[d.to_lower()] = true
			_listing[dir] = names
		return (_listing[dir] as Dictionary).has(path.get_file().to_lower())
