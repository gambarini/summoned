extends Node

## THROWAWAY Milestone-1 harness (warrior mesh redesign). Renders the WarriorMesh
## body through the real pipeline at FOUR world facings (front / sides / back relative
## to the camera) on a ring, to validate it reads from every angle — the true-3D
## rotation question the camera-facing blockout never tested. Plus a static preview
## ember at the chest socket (the dynamic Hollow is WarriorSync's, added in M2).
##
## Usage (windowed; headless can't render 3D):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/warrior_mesh_test.tscn -- --ring=1
## Captures docs/gen/warrior_mesh_ringN_face{0,90,180,270}.png (deg from facing camera).

const FEET_Y := 0.5

func _ready() -> void:
	var ring := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ring="):
			ring = int(a.split("=")[1])
	GameState.current_ring = ring

	var rig: IsoRig = load("res://scenes/iso_rig.tscn").instantiate()
	var world: Node3D = _make_ring_world(ring)
	if world.has_method("palette"):
		rig.palette = world.palette()
	if world.has_method("apply_environment"):
		world.apply_environment(rig)
	add_child(rig)
	world.build(rig)
	rig.add_world_child(world)

	var mesh := WarriorMesh.new()
	mesh.position = Vector3(0.0, FEET_Y, 0.0)
	rig.add_world_child(mesh)
	mesh.build(rig)
	_add_preview_ember(mesh)

	var yaw := rig.get_yaw()
	for _n in range(150):  # cold shader compile headroom
		await get_tree().process_frame
	for deg in [0, 90, 180, 270]:
		mesh.rotation_degrees.y = yaw + deg
		for _n in range(8):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_capture("res://docs/gen/warrior_mesh_ring%d_face%d.png" % [ring, deg])

	# Pose captures (front facing): prove the leg / sword / cape pivots articulate.
	mesh.rotation_degrees.y = yaw
	for pose in [["neutral", 0.0, 0.0, false], ["walk", PI * 0.5, 0.0, true], ["attack", 0.0, 1.0, false]]:
		mesh.set_walk(pose[1], 1.0 if pose[3] else 0.0)
		mesh.set_attack(pose[2])
		mesh.set_cape(0.06 + (0.30 if pose[3] else 0.0) + maxf(pose[2], 0.0) * 0.22)
		await _settle(8)
		_capture("res://docs/gen/warrior_mesh_pose_%s.png" % pose[0])

	get_tree().quit()


func _settle(frames: int) -> void:
	for _n in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _make_ring_world(ring: int) -> Node3D:
	match ring:
		2: return Ring2World.new()
		3: return Ring3World.new()
		4: return Ring4World.new()
		5: return Ring5World.new()
		_: return Ring1World.new()


# Static ember at the chest socket so the preview reads complete (WarriorSync drives
# the real stress-gated Hollow in the game). Child of the mesh, so it rotates with it.
func _add_preview_ember(mesh: WarriorMesh) -> void:
	for pair in [[0.16, "c89a5e"], [0.07, "f0e8d8"]]:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = pair[0]
		c.bottom_radius = pair[0]
		c.height = 0.04
		c.radial_segments = 12
		mi.mesh = c
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(pair[1])
		mi.material_override = m
		mi.position = Vector3(0.0, WarriorMesh.CHEST_Y, WarriorMesh.CHEST_Z + 0.04)
		mi.rotation_degrees.x = 90.0
		mesh.add_child(mi)


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("captured ", path)
