@tool
extends "res://addons/gomo_sounds/ui/card.gd"

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const InstallPlanner := preload("res://addons/gomo_sounds/core/install_planner.gd")
const InstallSummary := preload("res://addons/gomo_sounds/core/install_summary.gd")
const SfxApi := preload("res://addons/gomo_sounds/core/sfx_api.gd")
const SfxInstallOptions := preload("res://addons/gomo_sounds/ui/install_options.gd")
const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")
const SfxSoundInstaller := preload("res://addons/gomo_sounds/core/sound_installer.gd")

## Step 3: downloads the chosen sounds into the project. First builds the plan (nothing written) and, when
## something moves, disappears or collides with a file of the person's, shows the summary and asks for confirmation.

var _api: SfxApi
var _button: Button
var _result: Label
var _confirm: ConfirmationDialog
var _replace_edits: CheckBox
var _pending: Dictionary = {}


func _init() -> void:
	super(T.t("step_install"), "3")


func setup(api: SfxApi) -> void:
	_api = api
	add(SfxInstallOptions.new())
	_button = add(SfxUi.primary(T.t("install_button"), _on_install, "AssetLib|ArrowDown|Load")) as Button
	_result = add(SfxUi.hint("")) as Label
	_result.visible = false
	_confirm = ConfirmationDialog.new()
	_confirm.title = T.t("confirm_title")
	_confirm.ok_button_text = T.t("confirm_ok")
	_confirm.dialog_autowrap = true
	_confirm.min_size = Vector2i(460, 0) * SfxUi.scale()
	# Only shown when there are sounds edited by the person with a new version on the site; always unchecked.
	_replace_edits = CheckBox.new()
	_confirm.add_child(_replace_edits)
	_confirm.confirmed.connect(func() -> void:
		if _replace_edits.visible and _replace_edits.button_pressed:
			InstallPlanner.accept_site_versions(_pending)
		_apply_pending())
	# ✕, Esc and Cancel: nothing is written, the button comes back.
	_confirm.canceled.connect(func() -> void:
		_pending = {}
		_finish(""))
	add_child(_confirm)


func _on_install() -> void:
	var game_id := SfxSettings.game_id()
	_show(T.t("pick_game_first") if game_id == "" else T.t("install_checking"))
	if game_id == "":
		return
	_button.disabled = true
	var p: Dictionary = await SfxSoundInstaller.prepare(_api, game_id)
	if p["error"] != "":
		_finish(p["error"])
		return
	var plan_data: Dictionary = p["plan"]
	if not InstallSummary.has_changes(plan_data):
		_show(T.t("importing"))
		await SfxSoundInstaller.repair(_api, game_id)
		_finish(InstallSummary.text(plan_data))
		return
	_pending = plan_data
	if InstallPlanner.needs_confirmation(plan_data):
		_confirm.dialog_text = InstallSummary.text(plan_data)
		var outdated := InstallPlanner.outdated_edits(plan_data)
		_replace_edits.visible = outdated > 0
		_replace_edits.button_pressed = false
		_replace_edits.text = T.t("replace_edits", outdated)
		_confirm.reset_size()
		_confirm.popup_centered()
	else:
		_apply_pending()


func _apply_pending() -> void:
	var plan_data := _pending
	_pending = {}
	if plan_data.is_empty():
		return
	_show(T.t("downloading"))
	var r: Dictionary = await SfxSoundInstaller.apply(_api, SfxSettings.game_id(), plan_data, _show)
	if r["error"] != "":
		_finish(r["error"])
		return
	_finish(InstallSummary.text(plan_data) + "\n" + T.t("installed_where", SfxSoundInstaller.catalog_path()))


func _show(text: String) -> void:
	_result.visible = text != ""
	_result.text = text


func _finish(text: String) -> void:
	_button.disabled = false
	_show(text)
