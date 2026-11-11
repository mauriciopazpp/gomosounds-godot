@tool
extends RefCounted

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")

## Code-based connection: requests a code, opens the site for approval and waits for the key.
## Never asks for a password in the editor; the new key lives only in EditorSettings.

signal code_ready(user_code: String, url: String)

var _cancelled := false


func cancel() -> void:
	_cancelled = true


## Returns "" on success (key already saved) or the error message.
func run(api: SfxApi) -> String:
	_cancelled = false
	var client := "Godot · " + SfxSettings.project_name()
	var start := await api.post_json("/plugin/device/start", {"clientName": client.substr(0, 60)})
	if not start.ok:
		return start.error
	var d: Dictionary = start.data
	code_ready.emit(str(d["userCode"]), str(d["verificationUrl"]))
	OS.shell_open(str(d["verificationUrl"]))
	var interval := float(d.get("intervalSec", 3))
	var deadline := Time.get_ticks_msec() + int(float(d.get("expiresInSec", 600)) * 1000.0)
	var tree := Engine.get_main_loop() as SceneTree
	while not _cancelled and Time.get_ticks_msec() < deadline:
		await tree.create_timer(interval).timeout
		if _cancelled:
			break
		var poll := await api.post_json("/plugin/device/poll", {"deviceCode": d["deviceCode"]})
		if not poll.ok:
			continue
		match str(poll.data.get("status", "")):
			"approved":
				SfxSettings.set_api_key(str(poll.data["apiKey"]))
				return ""
			"denied":
				return T.t("login_denied")
			"expired":
				return T.t("login_expired")
	return T.t("login_cancelled") if _cancelled else T.t("login_expired")
