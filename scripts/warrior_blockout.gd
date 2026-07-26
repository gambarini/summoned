extends Node

## THROWAWAY redesign-preview harness (Warrior 3D study, 2026-06-19).
## Renders a low-poly ARMORED-KNIGHT blockout through the real game pipeline
## (IsoRig + cel.gdshader + palette snap) so the redesign can be judged at true
## game fidelity — silhouette, cel banding, palette snap, iso angle — on real
## terrain. NOT the final mesh: primitives only, no rig/animation. The existing
## warrior billboard/effects are untouched; this never wires into the game.
##
## Usage (headless can't render 3D — run windowed, like ring_capture):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/warrior_blockout.tscn -- --ring=1
## Captures the ROOT WINDOW to docs/gen/warrior_blockout_ringN_yaw{45,135}.png.

const FEET_Y := 0.5            # plateau top (warrior billboard hovers above this)
const FACE_OFFSET := 0.0       # deg added to yaw so the knight's front (+Z) faces camera

# --- Warrior palette (will SNAP to the active ring palette in the post pass —
# that snap is the point: it shows how the figure actually reads in-engine). ---
const ARMOR_DARK  := Color("241a33")   # deep indigo plate -> dark blue-grey
const ARMOR_MID   := Color("4a4560")   # lit plate / pauldrons -> mid
const SURCOAT     := Color("2e2440")   # cloak/surcoat
const VOID_COL    := Color("0d0a1e")   # the Hollow recess -> darkest
const EMBER_COL   := Color("c89a5e")   # warm ember (a palette-present warm slot)
const EYE_COL     := Color("cbd2d3")   # pale glowing eyes
const BLADE_COL   := Color("a8b1ba")   # metal blade -> light
const GLYPH_COL   := Color("e6e2ee")   # pale notation debris (kept off the signal hues)
const HOTCORE     := Color("f0e8d8")   # hot pale wound/eye core

const NOTATION_SHEET := preload("res://assets/sprites/notation_glyphs.png")


func _ready() -> void:
	var ring := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ring="):
			ring = int(a.split("=")[1])
	# Dev harness: never write the player's save (this scene forces GameState fields).
	GameState.persist_enabled = false
	GameState.current_ring = ring

	# --- Real pipeline mount (mirrors main._ready) ---------------------------
	var rig: IsoRig = load("res://scenes/iso_rig.tscn").instantiate()
	var world: Node3D = _make_ring_world(ring)
	if world.has_method("palette"):
		rig.palette = world.palette()
	if world.has_method("apply_environment"):
		world.apply_environment(rig)
	add_child(rig)
	world.build(rig)
	rig.add_world_child(world)

	# --- The blockout, at the warrior's spot (sim centre -> world origin) -----
	var knight := _build_knight(rig)
	knight.position = Vector3(0.0, FEET_Y, 0.0)
	rig.add_world_child(knight)

	# Cold launch compiles the cel/post shaders — give it generous headroom.
	for _n in range(150):
		knight.rotation_degrees.y = rig.get_yaw() + FACE_OFFSET  # keep facing camera
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture("res://docs/gen/warrior_blockout_ring%d_yaw45.png" % ring)

	rig.orbit(90.0)
	for _n in range(30):
		knight.rotation_degrees.y = rig.get_yaw() + FACE_OFFSET
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture("res://docs/gen/warrior_blockout_ring%d_yaw135.png" % ring)

	get_tree().quit()


func _make_ring_world(ring: int) -> Node3D:
	match ring:
		2: return Ring2World.new()
		3: return Ring3World.new()
		4: return Ring4World.new()
		5: return Ring5World.new()
		_: return Ring1World.new()


# --- Blockout geometry (local space, feet at y=0, front = +Z) ----------------

func _build_knight(rig: IsoRig) -> Node3D:
	var root := Node3D.new()
	root.name = "WarriorBlockout"
	var armor := rig.solid_material(ARMOR_DARK)
	var lit := rig.solid_material(ARMOR_MID)
	var coat := rig.solid_material(SURCOAT)
	var blade := rig.solid_material(BLADE_COL)

	# Tattered split cape behind the body (two trailing panels, flared back)
	_box(root, Vector3(0.32, 1.55, 0.05), Vector3(-0.17, 1.02, -0.22), coat, 4.0, 9.0)
	_box(root, Vector3(0.28, 1.72, 0.05), Vector3(0.18, 1.10, -0.25), coat, -3.0, 7.0)
	# Legs (slimmer, longer — a more upright knightly stance)
	_box(root, Vector3(0.20, 0.95, 0.24), Vector3(-0.16, 0.47, 0.04), armor)
	_box(root, Vector3(0.20, 0.95, 0.24), Vector3(0.16, 0.47, 0.04), armor)
	# Surcoat / robe skirt — faceted cone, narrower for a leaner figure
	_cyl(root, 0.26, 0.50, 1.05, Vector3(0.0, 1.18, 0.0), coat)
	# Torso / breastplate (narrower)
	_box(root, Vector3(0.60, 0.74, 0.40), Vector3(0.0, 1.98, 0.0), armor)
	_box(root, Vector3(0.34, 0.48, 0.10), Vector3(0.0, 2.04, 0.20), lit)  # chest plate front
	# Pauldrons (angled, prominent)
	_box(root, Vector3(0.34, 0.30, 0.42), Vector3(-0.44, 2.22, 0.0), lit, -18.0)
	_box(root, Vector3(0.34, 0.30, 0.42), Vector3(0.44, 2.22, 0.0), lit, 18.0)
	# Neck + helm/cowl (slightly tapered, with a crest)
	_box(root, Vector3(0.18, 0.14, 0.18), Vector3(0.0, 2.42, 0.0), armor)
	_box(root, Vector3(0.40, 0.46, 0.40), Vector3(0.0, 2.70, 0.0), armor)
	_box(root, Vector3(0.10, 0.16, 0.30), Vector3(0.0, 2.96, -0.02), lit)  # crest fin
	_box(root, Vector3(0.42, 0.07, 0.06), Vector3(0.0, 2.88, 0.18), lit)   # brow ridge
	# Hooded face: a dark recess with two bright glowing eyes (Pale Reaches read)
	_box(root, Vector3(0.28, 0.30, 0.06), Vector3(0.0, 2.70, 0.20), _unshaded(VOID_COL))
	_box(root, Vector3(0.09, 0.10, 0.04), Vector3(-0.08, 2.72, 0.23), _unshaded(HOTCORE))
	_box(root, Vector3(0.09, 0.10, 0.04), Vector3(0.08, 2.72, 0.23), _unshaded(HOTCORE))
	_disc_z(root, 0.17, Vector3(0.0, 2.72, 0.18), _glowmat(EYE_COL, 0.18))  # faint face glow

	# Burning hem at the cloak base + a little warm bleed up the lower cloak
	_cyl(root, 0.46, 0.54, 0.22, Vector3(0.0, 0.71, 0.0), _unshaded(EMBER_COL))
	_box(root, Vector3(0.06, 0.30, 0.04), Vector3(-0.20, 0.96, 0.20), _glowmat(EMBER_COL, 0.4))
	_box(root, Vector3(0.05, 0.24, 0.04), Vector3(0.16, 0.94, 0.21), _glowmat(EMBER_COL, 0.4))

	# --- The Hollow: a burning chest wound — halo, void, ember, hot core ------
	# Discs face +Z (camera, since the figure is rotated to face it). Bright at the
	# core but a restrained halo, so the armored form still reads as primary.
	_disc_z(root, 0.38, Vector3(0.0, 2.00, 0.20), _glowmat(EMBER_COL, 0.30))  # warm halo
	_disc_z(root, 0.30, Vector3(0.0, 2.00, 0.22), _unshaded(VOID_COL))        # void
	_disc_z(root, 0.18, Vector3(0.0, 2.00, 0.25), _unshaded(EMBER_COL))       # ember
	_disc_z(root, 0.075, Vector3(0.0, 2.00, 0.27), _unshaded(HOTCORE))        # hot core
	# "The song broke here": a faint ember seam running down from the wound
	_box(root, Vector3(0.06, 0.60, 0.04), Vector3(0.0, 1.56, 0.205), _unshaded(EMBER_COL))

	# --- Notation drift: pale score-debris shedding off the trailing edge -----
	# (Hints the "dissolving into music" identity; the real game drives this with
	# the GPUParticles3D NotationDrift node.)
	_glyph(root, 0, Vector3(0.42, 2.34, -0.10), 0.30)
	_glyph(root, 2, Vector3(0.58, 2.02, -0.28), 0.26)
	_glyph(root, 1, Vector3(0.34, 2.62, 0.02), 0.22)
	_glyph(root, 3, Vector3(-0.46, 2.18, -0.16), 0.28)
	_glyph(root, 2, Vector3(0.64, 1.66, -0.24), 0.24)
	_glyph(root, 0, Vector3(-0.34, 2.52, -0.06), 0.20)

	# --- Blade: lowered, resting point-down at the right side ----------------
	_box(root, Vector3(0.10, 1.30, 0.05), Vector3(0.40, 0.78, 0.12), blade)  # blade, tip near feet
	_box(root, Vector3(0.32, 0.08, 0.10), Vector3(0.40, 1.50, 0.12), lit)    # crossguard
	_box(root, Vector3(0.07, 0.13, 0.07), Vector3(0.40, 1.60, 0.12), armor)  # grip/pommel
	_box(root, Vector3(0.16, 0.22, 0.18), Vector3(0.38, 1.44, 0.12), armor)  # gauntlet/hand

	# Faint warm underglow on the ground — the figure smoulders where it stands
	_cyl(root, 0.60, 0.60, 0.02, Vector3(0.0, 0.03, 0.0), _glowmat(EMBER_COL, 0.28))
	return root


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, roll := 0.0, pitch := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(pitch, 0.0, roll)
	parent.add_child(mi)


# A thin disc lying in the XY plane (flat face toward +Z / the camera) — the
# Hollow wound. Reads as a hole on the chest, not a convex bulge.
func _disc_z(parent: Node, r: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.04
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = 90.0  # axis Y -> Z, flat face points at camera
	parent.add_child(mi)


func _cyl(parent: Node, top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = h
	c.radial_segments = 8  # faceted, reads pixel-chunky
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


# A billboarded notation glyph (one 32px frame from the 4-frame strip), pale and
# unshaded — drifting score-debris. `frame` 0..3 picks the glyph.
func _glyph(parent: Node, frame: int, pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var at := AtlasTexture.new()
	at.atlas = NOTATION_SHEET
	at.region = Rect2(frame * 32, 0, 32, 32)
	m.albedo_texture = at
	m.albedo_color = GLYPH_COL
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	mi.mesh = q
	mi.position = pos
	parent.add_child(mi)


func _sphere(parent: Node, r: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 5
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


# Unshaded bright material (eyes / ember / void) — pops past the cel banding,
# still snaps to the nearest palette entry like everything else.
func _unshaded(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m


# Faint additive glow (halos, warm bleed, underglow) — adds light over what's
# behind, then the palette snap resolves it to the nearest warm/pale entry.
func _glowmat(col: Color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, a)
	return m


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("captured ", path)
