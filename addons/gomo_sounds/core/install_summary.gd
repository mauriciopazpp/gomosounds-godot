@tool
extends RefCounted

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const InstallPlanner := preload("res://addons/gomo_sounds/core/install_planner.gd")

## The plan in words: one line of counts ("3 new · 1 deleted") and the warnings the user
## needs to read (their file preserved, name changed to avoid overwriting). The same text serves
## for the confirmation and the result.

const MAX_NOTES := 6
## Operation → count text (move and move_update count together).
const COUNTED := [["new", "sum_new"], ["update", "sum_update"], ["restore", "sum_restore"], ["move", "sum_move"], ["remove", "sum_remove"]]


static func has_changes(plan_data: Dictionary) -> bool:
	for a: Dictionary in plan_data["actions"]:
		if a["op"] not in ["keep", "left", "edited"] or a.get("bpm_changed", false):
			return true
	# Only edited ones with a new version on the site: there's still something to offer (replace with the site's).
	return InstallPlanner.outdated_edits(plan_data) > 0


static func counts_line(plan_data: Dictionary) -> String:
	var c := InstallPlanner.counts(plan_data)
	c["move"] = int(c.get("move", 0)) + int(c.get("move_update", 0))
	var parts := PackedStringArray()
	for pair: Array in COUNTED:
		if int(c.get(pair[0], 0)) > 0:
			parts.append(T.t(pair[1], int(c[pair[0]])))
	if parts.is_empty():
		return T.t("install_nothing")
	if int(c.get("keep", 0)) > 0:
		parts.append(T.t("sum_keep", int(c["keep"])))
	return " · ".join(parts) + "."


static func notes(plan_data: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for a: Dictionary in plan_data["actions"]:
		var note := _note(a)
		if note != "":
			out.append(note)
	if out.size() > MAX_NOTES:
		var extra := out.size() - MAX_NOTES
		out = out.slice(0, MAX_NOTES)
		out.append(T.t("note_more", extra))
	return out


static func text(plan_data: Dictionary) -> String:
	var lines := PackedStringArray([counts_line(plan_data)])
	lines.append_array(notes(plan_data))
	return "\n".join(lines)


static func _note(a: Dictionary) -> String:
	if InstallPlanner.renamed(a):
		return T.t("note_renamed", [a["want"], str(a["path"]).get_file()])
	if a.get("move_failed", false):
		return T.t("note_move_failed", a["path"])
	if a.get("overwrote_edit", false):
		return T.t("note_overwrote_edit", a["path"])
	match a["op"]:
		"edited":
			return T.t("note_edited_outdated" if a.get("outdated", false) else "note_edited", a["path"])
		"left_edited":
			return T.t("note_left_edited", a["path"])
		"left":
			return T.t("note_left", a["path"])
	return ""
