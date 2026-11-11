@tool
extends Node

## Photo of a scene, taken by the plugin itself: instances the scene in a hidden
## SubViewport, frames the camera to the model's size, lights it and captures.
## Works for any 3D scene (and 2D, centered), with no configuration and no reliance on the
## editor thumbnail (which only exists for scenes saved in the editor).
## One photo at a time (queue), fixed deadline in frames: never hangs. Outside the editor
## (headless command line doesn't render) returns null.

const SIZE := 256
const SETTLE_FRAMES := 4
## Camera direction: 3/4 from above, like an RTS icon.
const VIEW_DIR := Vector3(0.9, 0.75, 1.1)

var _cache := {}
var _busy := false


func thumbnail(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	if DisplayServer.get_name() == "headless":
		return null
	while _busy:
		await get_tree().process_frame
	if _cache.has(path):
		return _cache[path]
	_busy = true
	var tex := await _render(path)
	_busy = false
	_cache[path] = tex
	return tex


func _render(path: String) -> Texture2D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if inst == null:
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(inst)
	var framed := _frame_3d(vp, inst) if _has_3d(inst) else false
	if not framed:
		# Scene without a mesh in the editor (model built by script at runtime, e.g. per species):
		# photographs the 3D model that lives in the scene's folder.
		var model := _load_model(guess_model(path))
		if model != null:
			inst.queue_free()
			vp.add_child(model)
			framed = _frame_3d(vp, model)
	if not framed and not _has_3d(inst):
		framed = _frame_2d(vp, inst)
	var tex: Texture2D = null
	if framed:
		for i in SETTLE_FRAMES:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty() and not img.is_invisible():
			tex = ImageTexture.create_from_image(img)
	vp.queue_free()
	return tex


## Model files that don't represent the finished entity.
const MODEL_SKIP := ["bk", "backup", "old", "build", "lod", "hole", "wip", "test", "canteiro", "construction", "scaffold"]


static func _load_model(model_path: String) -> Node:
	if model_path == "":
		return null
	var ps := load(model_path) as PackedScene
	return ps.instantiate() if ps else null


## Best .glb/.gltf in the scene's folder (and subfolders): name similar to the scene's first,
## then the shallowest. "" if none.
static func guess_model(scene_path: String) -> String:
	var dir := scene_path.get_base_dir()
	var stem := scene_path.get_file().get_basename().to_lower()
	var folder := dir.get_file().to_lower()
	var found := PackedStringArray()
	_collect_models(dir, 0, found)
	var best := ""
	var best_score := -INF
	for f in found:
		var name := f.get_file().get_basename().to_lower()
		var skip := false
		for word: String in MODEL_SKIP:
			if name.contains(word):
				skip = true
		if skip:
			continue
		var score := -float(f.count("/") - dir.count("/"))
		if name.contains(stem) or stem.contains(name):
			score += 3.0
		if name.contains(folder):
			score += 2.0
		if score > best_score:
			best_score = score
			best = f
	return best


static func _collect_models(dir: String, depth: int, out: PackedStringArray) -> void:
	if depth > 2:
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	var files := d.get_files()
	files.sort()
	for f in files:
		var clean := f.trim_suffix(".import").trim_suffix(".remap")
		if (clean.ends_with(".glb") or clean.ends_with(".gltf")) and not out.has(dir.path_join(clean)):
			out.append(dir.path_join(clean))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect_models(dir.path_join(sub), depth + 1, out)


static func _has_3d(root: Node) -> bool:
	return root is Node3D or not root.find_children("*", "GeometryInstance3D", true, false).is_empty()


## Box enclosing the visible meshes (particles and effects are left out: they inflate the box).
static func _visual_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	for n in nodes:
		if not (n is MeshInstance3D or n is MultiMeshInstance3D or n is CSGShape3D):
			continue
		var gi := n as GeometryInstance3D
		if not gi.visible:
			continue
		var local := gi.get_aabb()
		if local.size == Vector3.ZERO:
			continue
		var world := gi.global_transform * local
		box = world if first else box.merge(world)
		first = false
	return box


func _frame_3d(vp: SubViewport, root: Node) -> bool:
	var box := _visual_aabb(root)
	if box.size == Vector3.ZERO:
		return false
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.01)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = radius * 0.01
	cam.far = radius * 20.0
	vp.add_child(cam)
	# Distance to fit the model's bounding sphere in the field of view.
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 1.05
	cam.position = center + VIEW_DIR.normalized() * dist
	cam.look_at(center, Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	return true


func _frame_2d(vp: SubViewport, root: Node) -> bool:
	if not (root is CanvasItem):
		return false
	var cam := Camera2D.new()
	vp.add_child(cam)
	cam.make_current()
	var rect := _canvas_rect(root)
	if rect.size != Vector2.ZERO:
		cam.position = rect.get_center()
		var k := minf(SIZE / rect.size.x, SIZE / rect.size.y) * 0.9
		cam.zoom = Vector2(k, k)
	return true


static func _canvas_rect(root: Node) -> Rect2:
	var r := Rect2()
	var first := true
	for n in root.find_children("*", "Sprite2D", true, false):
		var s := n as Sprite2D
		var rect := s.global_transform * s.get_rect()
		r = rect if first else r.merge(rect)
		first = false
	return r


## Texture2D → base64 PNG, scaled down to at most `max_size` px (light upload).
static func to_png_base64(tex: Texture2D, max_size: int = 256) -> String:
	if tex == null:
		return ""
	var img := tex.get_image()
	if img == null or img.is_empty():
		return ""
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	var biggest := maxi(img.get_width(), img.get_height())
	if biggest > max_size:
		var k := float(max_size) / biggest
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())
