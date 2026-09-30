extends Node

## Dev harness: films the warrior through the REAL main.tscn + WarriorSync (the exact code
## path the player sees) and writes frames cropped around him. Default mode: the idle guard,
## then one full chained combo at a fixed aim, until the guard return has settled.
##
## Windowed only (headless can't render 3D):
##   Godot --path . res://scenes/warrior_attack_capture.tscn -- --out=/abs/dir [options]
##   --zoom=N     ortho size in world units tall (the game uses 26) — closer look at the pose;
##                omit it to judge readability at true game scale
##   --aim=right|left|up|down|downright   screen-relative aim of the swings
##   --hitbox     overlay the 2D AttackArc's live hit wedge on the ground (red)
##   --mash       keep pressing through the finisher so the 3 -> 0 combo loop fires once
##   --wide       larger crop (reach of the thrust / burst)
##   --facings    idle guard at 8 headings, with a ground stroke along the true facing
##   --walk       locomotion frames (right, down, left, then stop)
##   --summon     re-summon, then death collapse (the Hollow must stay on the chest)
##   --ring=N     ring world to stage in (1..5)
## Frames are grabbed after RenderingServer.force_draw(): an unfocused window stops
## presenting, and a plain viewport grab (or an awaited frame_post_draw) goes stale/hangs.

const OVERLAY_Y := 0.53   # just above the plateau top (0.5)
const CROP_RENDER := Vector2(110.0, 80.0)   # crop size in render texels at game zoom

var _out := ""
var _zoom := 0.0
var _hitbox := false
var _facings := false
var _walk := false
var _mash := false
var _summon := false
var _ring := 1
var _crop_k := 1.0
var _aim_name := "right"
var _rig: IsoRig
var _warrior: CharacterBody2D
var _sync: WarriorSync
var _overlay: MeshInstance3D
var _frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.split("=")[1]
		elif a.begins_with("--zoom="):
			_zoom = float(a.split("=")[1])
		elif a == "--hitbox":
			_hitbox = true
		elif a == "--facings":
			_facings = true
		elif a == "--walk":
			_walk = true
		elif a == "--mash":
			_mash = true
		elif a == "--summon":
			_summon = true
		elif a.begins_with("--ring="):
			_ring = int(a.split("=")[1])
		elif a == "--wide":
			_crop_k = 1.8
		elif a.begins_with("--aim="):
			_aim_name = a.split("=")[1]
	if _out == "":
		push_warning("warrior_attack_capture: pass --out=/abs/dir")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(2))   # watchdog

	# Dev harness: never write the player's save; pinned layout for repeatable frames.
	GameState.persist_enabled = false
	GameState.lock_seed = true
	GameState.current_ring = _ring
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.2).timeout
	for group in ["enemies", "creatures"]:
		for e in get_tree().get_nodes_in_group(group):
			e.set_physics_process(false)
			e.set_process(false)
			if e is Node2D:
				e.global_position += Vector2(4000.0, 4000.0)   # out of frame + out of reach
	_rig = main._rig
	_sync = main._warrior_sync
	_warrior = main.get_node("Warrior")
	if _zoom > 0.0:
		_rig.cam_size = _zoom
		_rig._world_per_texel = _zoom / float(_rig.render_size.y)
		_rig._camera.size = _zoom * float(_rig._padded.y) / float(_rig.render_size.y)

	var screen_dir: Vector2 = {
		"right": Vector2(1, 0), "left": Vector2(-1, 0),
		"down": Vector2(0, 1), "up": Vector2(0, -1),
		"downright": Vector2(1, 1).normalized(),
	}.get(_aim_name, Vector2(1, 0))
	var aim: Vector2 = _rig.camera_relative_dir(screen_dir)
	_warrior.attack_dir_provider = func() -> Vector2: return aim

	if _hitbox:
		_overlay = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("c4547a")
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_overlay.material_override = m
		_rig.add_world_child(_overlay)

	# Let the summon finish (SUMMONING -> IDLE) and the shaders warm.
	for _n in range(240):
		await get_tree().process_frame
		if _warrior.vfx_state() == "IDLE" and _n > 150:
			break

	if _facings:
		await _capture_facings()
		get_tree().quit()
		return
	if _summon:
		# Re-summon (assemble from nothing) then die (crumple + sink): the chest wound must
		# stay on the breastplate through both. DYING is terminal, so it comes last.
		_sync.raw_input_override = Vector2(0, 1)
		for _n in range(12):
			await get_tree().process_frame
		_sync.raw_input_override = Vector2.ZERO
		_warrior._change_state(_warrior.State.SUMMONING)
		for i in range(150):
			await get_tree().process_frame
			if i % 25 == 0:
				_capture("summon_%03d" % i)
		# SUMMONING is invulnerable (warrior.gd SUMMON_INVULN_TIME) — wait it out.
		for _n in range(600):
			await get_tree().process_frame
			if _warrior.vfx_state() == "IDLE":
				break
		_warrior.take_damage(9999)
		for i in range(150):
			await get_tree().process_frame
			if i % 25 == 0:
				_capture("death_%03d" % i)
		get_tree().quit()
		return
	if _walk:
		for sd in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0).normalized()]:
			_sync.raw_input_override = sd
			for i in range(24):
				await get_tree().process_frame
				if i % 4 == 3:
					_capture("walk_%s_%02d" % [str(sd), i])
		_sync.raw_input_override = Vector2.ZERO
		for i in range(20):
			await get_tree().process_frame
			if i % 5 == 4:
				_capture("stop_%02d" % i)
		get_tree().quit()
		return

	# Idle guard, facing the aim: walk a step toward it, stop, settle.
	_sync.raw_input_override = screen_dir
	await _frames(12)
	_sync.raw_input_override = Vector2.ZERO
	await _frames(50)
	_capture("idle")

	# Full chained combo: re-arm the buffer in every recovery until the finisher has been
	# queued (--mash keeps pressing through it, so the 3 -> 0 loop fires once). Runs until the
	# combo has ended AND the guard return has settled.
	_warrior._attack_buffer = 0.15
	var looped := false
	for i in range(400):
		var step: int = _warrior.vfx_combo_step()
		if _warrior.vfx_state() == "ATTACK_RECOVERY" and (step < 3 or (_mash and not looped)):
			_warrior._attack_buffer = 0.15
			looped = looped or step == 3
		_update_overlay()
		await get_tree().process_frame
		if i % 2 == 0:
			_capture("combo_%03d_s%d_%s" % [i, _warrior.vfx_combo_step(), _warrior.vfx_state()])
		if _warrior.vfx_state() == "IDLE" and i > 20 and _sync._relax <= 0.0:
			break
	await _frames(20)
	_capture("after")
	get_tree().quit()


# Idle guard at 8 screen headings, with a ground stroke along the sim facing (ground truth
# for "which way is he turned") so the pose's directional read can be judged.
func _capture_facings() -> void:
	var marker := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("c4547a")
	marker.material_override = m
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.02, 2.5)
	marker.mesh = box
	_rig.add_world_child(marker)
	var names := ["right", "downright", "down", "downleft", "left", "upleft", "up", "upright"]
	for i in names.size():
		var ang := i * PI / 4.0
		var sd := Vector2(cos(ang), sin(ang))
		_sync.raw_input_override = sd
		await get_tree().process_frame
		for _n in range(10):
			await get_tree().process_frame
		_sync.raw_input_override = Vector2.ZERO
		for _n in range(45):
			await get_tree().process_frame
		var fd: Vector2 = _sync._face_dir
		var feet := SimSpace.to_world(_warrior.global_position, 0.55)
		marker.position = feet + Vector3(fd.x, 0.0, fd.y) * 1.25
		marker.rotation = Vector3(0.0, atan2(fd.x, fd.y), 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_capture("facing_%s_%s" % [names[i], _sync.get_facing()])


func _frames(n: int) -> void:
	for _n in range(n):
		_update_overlay()
		await get_tree().process_frame


# Mirror every live, still-monitoring AttackArc hit wedge onto the ground plane.
func _update_overlay() -> void:
	if _overlay == null:
		return
	var verts := PackedVector3Array()
	for arc in get_tree().get_nodes_in_group("attack_arcs"):
		var area: Area2D = arc.get_node_or_null("HitArea")
		if area == null or not area.monitoring:
			continue
		var shape: CollisionPolygon2D = area.get_node("HitShape")
		var xf := shape.global_transform
		var poly := PackedVector2Array()
		for p in shape.polygon:
			poly.append(xf * p)
		var tris := Geometry2D.triangulate_polygon(poly)
		for idx in tris:
			verts.append(SimSpace.to_world(poly[idx], OVERLAY_Y))
	if verts.is_empty():
		_overlay.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_overlay.mesh = mesh


# Crop the device-res composite around the warrior and save it. Forces a draw first: an
# unfocused/occluded window stops presenting, and the grab would otherwise return a stale
# frame (identical images while the warrior moves).
func _capture(tag: String) -> void:
	RenderingServer.force_draw(true, 0.0)
	var img := _rig.get_screen_viewport().get_texture().get_image()
	var k := float(img.get_width()) / float(_rig.render_size.x)
	var feet := SimSpace.to_world(_warrior.global_position, 1.8)
	var c := _rig.world_to_render(feet) * k
	var zoom_k := 26.0 / _zoom if _zoom > 0.0 else 1.0
	var size := CROP_RENDER * k * minf(zoom_k, 2.2) * _crop_k
	var r := Rect2i(Vector2i(c - size * 0.5), Vector2i(size))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.save_png(_out.path_join("%03d_%s.png" % [_frame, tag]))
	_frame += 1
