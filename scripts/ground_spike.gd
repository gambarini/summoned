extends Node
## Dusty-rock GROUND spike (THROWAWAY — not wired into the game).
##
## Tests the t3ssel8r / David-Holland "scatter textured sprites over the terrain"
## technique for Ring 1's dusty-rock ground, INSIDE a real `IsoRig` so the actual
## pipeline (texel-snap render + depth outline + 16-colour palette snap) applies and
## the rotation behaviour is honest. Rig is configured with the live Ring 1 settings
## (`Ring1World.apply_environment` + rig camera defaults) so the verdict transfers.
##
## Four cumulative ground panels (focus with number keys; orbit A/D):
##   1 A = current plain tiled ground (the repetitive baseline)
##   2 B = + macro-noise value drift (breaks the 64px tile grid across the whole patch)
##   3 C = + flat ground-aligned detail decals (pebbles/gravel/cracks) — the dusty look
##   4 D = + a few UPRIGHT weed billboards (the grass case, for comparison)
##   0 = origin (all four panels meet — direct A/B/C/D comparison)
##
## What to read: does B alone already fix the repeat? do the decals stay locked to the
## surface under orbit (no swim)? does the depth outline rim the flat decals (it should
## not — tiny Y-offset)? Delete once the technique is accepted or rejected.

const GROUND_TEX := "res://assets/textures/ground_tile.png"
const TRIPLANAR := "res://assets/shaders/cel_triplanar.gdshader"
const SPRITE := "res://assets/shaders/sprite_cel.gdshader"
const GROUND_SCALE := 0.4   # matches Ring1World GROUND_SCALE

const PEBBLES := "res://assets/textures/detail_pebbles.png"
const GRAVEL := "res://assets/textures/detail_gravel.png"
const CRACK := "res://assets/textures/detail_crack.png"
const WEED := "res://assets/textures/detail_weed.png"

const COL_GROUND := Color("7c8591")
const COL_GROUND_LOW := Color("4c5a6d")
const COL_PATH := Color("98a0a8")

const PANEL := 16.0   # patch edge (world units)
const TOP := 0.25     # patch top surface Y (box half-height)

# Macro-noise tuning (the load-bearing layer for dusty rock per advisor).
const MACRO_SCALE := 0.05    # tiles/world-unit -> ~20u period: broad patches across a 16u panel
const MACRO_STRENGTH := 0.5  # value excursion; raised since the flat base has no grain to fight

# TEXTURE TOGGLE: false = drop the tiling ground_tile grain entirely; the base becomes
# a FLAT cel ground colour (via a 1x1 white texture so cel_triplanar outputs just the
# tint) and all surface variation comes from macro-noise drift + scattered decals.
const USE_GROUND_TEXTURE := false

# Internal render resolution (the master "definition" knob). 320x180 = the project
# identity (chunky pixel-art). Raise for a sharper / higher-definition look.
const RENDER_SIZE := Vector2i(480, 270)

# Drop the WarriorMesh onto panel C (flat + macro + decals) to judge the character
# reading against the new ground at this resolution.
const SHOW_WARRIOR := true

var _rig: IsoRig
var _warrior_mesh: WarriorMesh
var _macro_tex: NoiseTexture2D
var _flat_tex: Texture2D
var _panels := {}  # index -> centre Vector3


func _ready() -> void:
	_rig = IsoRig.new()
	_rig.name = "IsoRig"
	_rig.render_size = RENDER_SIZE
	# Live Ring 1 camera + atmosphere so the look judges honestly against the game.
	_rig.cam_size = 26.0
	_rig.pivot_pitch = -30.0
	_rig.initial_yaw = 45.0
	_rig.bg_color = Color("505d70")
	_rig.fog_color = Color("5a697d")
	_rig.fog_density = 0.008
	_rig.ambient_energy = 0.42
	_rig.vignette_strength = 0.18
	add_child(_rig)  # builds the pipeline in its own _ready

	_macro_tex = _build_macro_noise()
	_flat_tex = _build_flat_tex()

	var world := Node3D.new()
	world.name = "SpikeWorld"
	_panels = {
		0: Vector3(-9.0, 0.0, -9.0),  # A baseline
		1: Vector3(9.0, 0.0, -9.0),   # B + macro
		2: Vector3(-9.0, 0.0, 9.0),   # C + decals
		3: Vector3(9.0, 0.0, 9.0),    # D + uprights
	}
	for level in _panels:
		_build_panel(world, _panels[level], level)
	_rig.add_world_child(world)

	if SHOW_WARRIOR:
		# Dev harness: never write the player's save (this scene forces GameState fields).
		GameState.persist_enabled = false
		GameState.current_ring = 1  # WarriorMesh reads ring for tint/coherence
		_add_warrior(_panels[2])  # panel C: flat + macro + decals
		_rig.cam_size = 11.0       # closer so the warrior + ground both read
		_rig.set_follow_target(_panels[2] + Vector3(0.0, 0.9, 0.0))
	else:
		# Default to the centre so all four panels meet in frame (direct comparison).
		_rig.set_follow_target(Vector3.ZERO)


# Stand a fully-formed WarriorMesh at a panel centre (feet on the panel top surface).
func _add_warrior(panel_centre: Vector3) -> void:
	_warrior_mesh = WarriorMesh.new()
	_warrior_mesh.position = panel_centre + Vector3(0.0, TOP, 0.0)
	_rig.add_world_child(_warrior_mesh)
	_warrior_mesh.build(_rig)
	_warrior_mesh.set_form(1.0)       # fully summoned
	_warrior_mesh.set_coherence(0.6)
	_warrior_mesh.set_walk(0.0, 0.0)  # idle
	_warrior_mesh.set_attack(0.0)
	_warrior_mesh.set_cape(0.06)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_0:
				_rig.set_follow_target(Vector3.ZERO)
			KEY_1, KEY_2, KEY_3, KEY_4:
				focus_panel(event.keycode - KEY_1)
			KEY_A:
				_rig.orbit(-15.0)
			KEY_D:
				_rig.orbit(15.0)
			KEY_MINUS, KEY_Q:
				_zoom(1.0)   # zoom OUT (bigger ortho size)
			KEY_EQUAL, KEY_E:
				_zoom(-1.0)  # zoom IN
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1.0)


func _zoom(dir: float) -> void:
	var cam := _rig.get_camera()
	cam.size = clampf(cam.size + dir * 2.0, 3.0, 40.0)


## Centre the camera on one panel at the live zoom (called by keys and by exec capture).
func focus_panel(i: int) -> void:
	if _panels.has(i):
		_rig.set_follow_target(_panels[i] + Vector3(0.0, 0.4, 0.0))


func _build_macro_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# LOW freq = a few big smooth blobs across the 256px tile (was 0.6 = fine static, a bug).
	noise.frequency = 0.02
	noise.seed = 7
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.normalize = true     # spread to 0..1, mean ~0.5 (so the shader's (m-0.5) is balanced)
	nt.noise = noise
	return nt


# A 1x1 white texture: fed to cel_triplanar, ALBEDO collapses to the tint (flat colour).
func _build_flat_tex() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


# A cel_triplanar ground material (optionally with macro value-drift enabled).
# USE_GROUND_TEXTURE=false -> flat cel ground colour (no tiling grain).
func _ground_material(macro: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(TRIPLANAR)
	if USE_GROUND_TEXTURE:
		m.set_shader_parameter("albedo_tex", load(GROUND_TEX))
		m.set_shader_parameter("tint", Color.WHITE)
	else:
		m.set_shader_parameter("albedo_tex", _flat_tex)
		m.set_shader_parameter("tint", COL_GROUND)
	m.set_shader_parameter("texture_scale", GROUND_SCALE)
	m.set_shader_parameter("bands", _rig.cel_bands)
	m.set_shader_parameter("light_gain", _rig.cel_light_gain)
	if macro:
		m.set_shader_parameter("macro_noise", _macro_tex)
		m.set_shader_parameter("macro_scale", MACRO_SCALE)
		m.set_shader_parameter("macro_strength", MACRO_STRENGTH)
	return m


# A sprite_cel material for one scattered detail sprite.
func _sprite_material(tex_path: String, tint: Color, billboard: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SPRITE)
	m.set_shader_parameter("albedo_tex", load(tex_path))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("bands", _rig.cel_bands)
	m.set_shader_parameter("light_gain", _rig.cel_light_gain)
	m.set_shader_parameter("alpha_cut", 0.5)
	m.set_shader_parameter("billboard", billboard)
	return m


func _build_panel(world: Node3D, centre: Vector3, level: int) -> void:
	# Base ground slab (BoxMesh top, so triplanar top-projection == real plateau).
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(PANEL, 0.5, PANEL)
	slab.mesh = bm
	slab.position = centre
	slab.material_override = _ground_material(level >= 1)  # B,C,D get macro-noise
	world.add_child(slab)

	if level >= 2:
		_scatter_decals(world, centre)
	if level >= 3:
		_scatter_uprights(world, centre)


# Flat, ground-aligned detail decals — laid on the surface, tiny Y-offset so the depth
# outline does not rim them. SPARSE accents (the macro-noise carries the broad read).
func _scatter_decals(world: Node3D, centre: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centre.x * 13.0 + centre.z * 7.0) + 100
	var i := 0
	# (texture, count, min_size, max_size)
	for spec in [[PEBBLES, 10, 1.4, 2.8], [GRAVEL, 7, 1.6, 3.0], [CRACK, 3, 3.0, 5.0]]:
		for _n in range(spec[1]):
			var s: float = rng.randf_range(spec[2], spec[3])
			var decal := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(s, s)
			decal.mesh = pm
			# Tiny per-decal Y stagger to avoid coplanar z-fighting; stays sub-cm.
			decal.position = centre + Vector3(
				rng.randf_range(-7.0, 7.0), TOP + 0.02 + i * 0.001, rng.randf_range(-7.0, 7.0)
			)
			decal.rotation_degrees.y = rng.randf_range(0.0, 360.0)
			# Slight value variation so accents don't all match (still on the ground hue).
			var t := COL_GROUND.lerp([COL_GROUND_LOW, COL_PATH, COL_GROUND][rng.randi() % 3], rng.randf() * 0.4)
			var tint := Color(t.r / COL_GROUND.r, t.g / COL_GROUND.g, t.b / COL_GROUND.b)
			decal.material_override = _sprite_material(spec[0], tint, false)
			world.add_child(decal)
			i += 1


# A few UPRIGHT weed billboards (the grass case) — sparse, for the comparison only.
func _scatter_uprights(world: Node3D, centre: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centre.x * 5.0 + centre.z * 11.0) + 200
	for _n in range(8):
		var s := rng.randf_range(0.9, 1.5)
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(s, s)
		quad.mesh = qm
		# Bottom of the quad sits on the surface.
		quad.position = centre + Vector3(
			rng.randf_range(-7.0, 7.0), TOP + s * 0.5, rng.randf_range(-7.0, 7.0)
		)
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(0.92, 0.95, 1.0), rng.randf())
		quad.material_override = _sprite_material(WEED, tint, true)
		world.add_child(quad)
