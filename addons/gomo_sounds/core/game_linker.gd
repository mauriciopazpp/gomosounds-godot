@tool
extends RefCounted

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

## Which Gomo Sounds game this project is: only what the person chose in the panel (saved in
## project.godot) or the command line's GOMO_GAME_ID. Never picks by name nor creates a game
## on its own: it linked to the wrong game when the account had two with the same name. Used by the panel and the
## command line.

const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")


## Returns [game_id, games (Array), message]. game_id "" = none chosen, or the chosen one is gone
## (message says what to do).
static func resolve(api: SfxApi) -> Array:
	var r := await api.call_tool("list_games")
	if not r.ok:
		return ["", [], r.error]
	var games: Array = r.data["games"]
	var linked := SfxSettings.game_id()
	for g: Dictionary in games:
		if str(g["id"]) == linked:
			return [linked, games, ""]
	return ["", games, T.t("no_game_linked")]
