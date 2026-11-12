extends Node

## Runs INSIDE the exported game (tests/run.sh, phase 3): the preset exports only this scene, so the
## sounds only arrive if the plugin includes them. Prints the verdict and exits.


func _ready() -> void:
	var has := SfxLibrary.has_sound("spider.attack")
	# Loops go through attach (attached to the node); play is always a one-shot sound (sfx_library.gd).
	var player := SfxLibrary.attach("@ambience.wind", self)
	var stream: AudioStream = player.get("stream") if player != null else null
	print("GOMO_EXPORT has=%s played=%s loop=%s" % [has, player != null, stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED])
	get_tree().quit()
