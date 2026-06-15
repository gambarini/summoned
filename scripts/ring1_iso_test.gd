extends Node

## EXPLORATORY SPIKE — not part of the game.
## Low-res 3D isometric render of Ring 1 (The Pale Reaches), built to test
## whether 3D blockout geometry + far orthographic camera + pixelation reads
## like docs reference `../idea/the_pale_reaches_concept_1.png`.
##
## Walled off on purpose: own scene, own script, touches nothing in the run
## loop and never modifies project.godot (the whole 3D world lives inside a
## SubViewport rendered at the game's 480x270, displayed nearest-neighbour).
##
## Terrain = CSG greybox (silhouette + palette + fog is the concept at this
## distance). Warrior = camera-facing billboard of the existing 8-dir sheet,
## so it survives camera rotation and stays on-aesthetic pixel art.
##
## Interactive: Q / E orbit the camera. Headless: renders one frame to
## res://docs/gen/ring1_iso_spike.png and quits (for review).

const RENDER_SIZE := Vector2i(320, 180)  # chunky pixel grid, free of the game's 480x270
const CAPTURE_PATH := "res://docs/gen/ring1_iso_spike.png"

const WARRIOR_SPEED := 6.0   # world units / sec
const ROT_SPEED := 90.0      # degrees / sec for free camera orbit
const WARRIOR_Y := 2.0       # keeps feet on the plateau top
const BOUNDS := Vector2(12.0, 10.0)  # half-extents the warrior can roam

# 8-dir sheet names, ordered clockwise from "away from camera".
const DIR_NAMES := [
	"north", "north-east", "east", "south-east",
	"south", "south-west", "west", "north-west",
]

# Authored Pale Reaches palette, sampled directly from the Ring 1 concept art.
# A tight, light, desaturated cool blue-grey ramp + a pale highlight + the one
# warm doorway accent. This is the concept's actual colour scheme.
const PALETTE := [
	"2a333f", "36414f", "485462", "4c5a6d",  # shadows
	"566375", "5a697d", "616b78", "667383",  # mids (measured surfaces)
	"6e7a89", "7c8591", "8b95a0",             # lights
	"a8b1ba", "cbd2d3",                       # pale highlights
	"c89a5e",                                 # warm doorway
]

# Pale Reaches palette, read off the concept art.
# Albedos set to the values measured off the concept art (soft, low-contrast).
const COL_GROUND := Color("7c8591")     # measured open ground
const COL_GROUND_LOW := Color("4c5a6d") # measured cliff/lowland
const COL_PATH := Color("98a0a8")       # pale cool trail
const COL_STONE := Color("667383")      # measured dome
const COL_STONE_DARK := Color("4c5a6d")
const COL_FLORA := Color("828d9b")
const COL_FLORA2 := Color("6e7a89")
const COL_PALE := Color("cbd2d3")
const COL_DOORWAY := Color("c89a5e")    # warm pinpoint (concept doorway)
const COL_FOG := Color("5a697d")        # measured sky/haze
const COL_BG := Color("5a697d")         # measured sky/haze
const COL_AMBIENT := Color("eef1f5")    # near-white flat fill (keeps albedo)

var _pivot: Node3D
var _camera: Camera3D
var _world_viewport: SubViewport  # the 3D render
var _post_viewport: SubViewport   # 3D render + pixel-art post pass (captured)
var _yaw := 45.0
var _warrior: Sprite3D
var _dir_textures := {}
var _facing := "south"
var _cel_shader: Shader


func _ready() -> void:
	_cel_shader = load("res://assets/shaders/cel.gdshader")
	_build_display()
	_build_world()
	# Headless has no GPU and can't render 3D, so capture runs windowed,
	# triggered by passing `-- --capture [yaw=NNN]` on the command line.
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		for a in args:
			if a.begins_with("yaw="):
				_orbit(float(a.trim_prefix("yaw=")) - _yaw)
		_capture_and_quit()


func _build_display() -> void:
	# Pipeline (both SubViewports stay locked at RENDER_SIZE — they must NOT be
	# under a SubViewportContainer, whose stretch would resize them to the
	# window): 3D world -> _world_viewport -> TextureRect with the pixel-art
	# post shader -> _post_viewport (captured) -> a display TextureRect scaled
	# up nearest-neighbour to fill the window.
	_world_viewport = SubViewport.new()
	_world_viewport.size = RENDER_SIZE
	_world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_world_viewport)

	_post_viewport = SubViewport.new()
	_post_viewport.size = RENDER_SIZE
	_post_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_post_viewport)

	var post_rect := TextureRect.new()
	post_rect.size = Vector2(RENDER_SIZE)
	post_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	post_rect.stretch_mode = TextureRect.STRETCH_SCALE
	post_rect.texture = _world_viewport.get_texture()
	post_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	post_rect.material = _make_post_material()
	_post_viewport.add_child(post_rect)

	# On-screen view: scale the fixed-res post render up to the window.
	var display := TextureRect.new()
	display.texture = _post_viewport.get_texture()
	display.set_anchors_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(display)


func _make_post_material() -> ShaderMaterial:
	var pal := PackedVector3Array()
	for hex in PALETTE:
		var c := Color(hex)
		pal.append(Vector3(c.r, c.g, c.b))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/pixel_post.gdshader")
	mat.set_shader_parameter("palette", pal)
	mat.set_shader_parameter("palette_count", pal.size())
	mat.set_shader_parameter("tex_size", Vector2(RENDER_SIZE))
	mat.set_shader_parameter("dither_strength", 0.0)  # flat bands, not stippled blend
	mat.set_shader_parameter("edge_strength", 0.0)    # no ink outline
	return mat


func _build_world() -> void:
	_world_viewport.add_child(_make_environment())
	_world_viewport.add_child(_make_key_light())
	_world_viewport.add_child(_make_camera_rig())
	_world_viewport.add_child(_make_terrain())
	_world_viewport.add_child(_make_warrior())


func _make_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COL_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = COL_AMBIENT
	env.ambient_light_energy = 1.0  # near-white flat fill; cel light adds the bands
	# Very light haze: only the far lowland edge fades, so near surfaces keep
	# flat crisp colour instead of a smooth gradient across everything.
	env.fog_enabled = true
	env.fog_light_color = COL_FOG
	env.fog_light_energy = 1.0
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0

	var we := WorldEnvironment.new()
	we.environment = env
	return we


func _make_key_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	# Cold, low, raking from the back-left — long melancholic shadows.
	light.rotation_degrees = Vector3(-42.0, 130.0, 0.0)
	light.light_color = Color("c8d0db")
	light.light_energy = 1.0  # cel light_gain controls how soft the bands are
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	return light


func _make_camera_rig() -> Node3D:
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position = Vector3(0.0, 0.5, 0.0)
	_pivot.rotation_degrees = Vector3(-30.0, _yaw, 0.0)  # ~2:1 dimetric feel

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL  # the iso-defining choice
	_camera.size = 26.0  # world units shown vertically (zoom)
	# Ortho projection is distance-independent, so keep the camera near the
	# scene — a far camera makes depth fog wash the whole frame.
	_camera.position = Vector3(0.0, 0.0, 22.0)
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.current = true
	_pivot.add_child(_camera)
	return _pivot


func _solid_material(col: Color, _rough := 0.95) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _cel_shader
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("bands", 2.0)
	m.set_shader_parameter("light_gain", 0.3)  # soft, but enough to separate forms
	return m


# Lightweight box prop (MeshInstance3D, not CSG) for the many small details.
func _box(size: Vector3, col: Color, rough := 0.95) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _solid_material(col, rough)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	return mi


func _make_terrain() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# --- Surrounding lowland: a large plane so terrain fills the frame at any
	# camera angle and fades into pale haze instead of a void. ---
	var land := CSGBox3D.new()
	land.size = Vector3(300.0, 2.0, 300.0)  # large enough to fill the frame at any yaw
	land.position = Vector3(0.0, -2.6, 0.0)  # top sits just below the cliffs
	land.material = _solid_material(COL_GROUND_LOW)
	root.add_child(land)

	# --- Plateau the tribe shelters on ---
	var plateau := CSGBox3D.new()
	plateau.size = Vector3(26.0, 1.0, 22.0)
	plateau.position = Vector3(0.0, 0.0, 0.0)
	plateau.material = _solid_material(COL_GROUND)
	root.add_child(plateau)

	# Worn ground patches break the flat single colour.
	for n in range(7):
		var patch := _box(
			Vector3(rng.randf_range(3.0, 6.0), 0.06, rng.randf_range(3.0, 6.0)),
			COL_GROUND_LOW if n % 2 == 0 else COL_GROUND.lerp(COL_PATH, 0.25)
		)
		patch.position = Vector3(rng.randf_range(-10.0, 10.0), 0.5, rng.randf_range(-8.0, 8.0))
		patch.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		root.add_child(patch)

	# --- Stratified cliff descending off the front-left edge ---
	for i in range(3):
		var w := 10.0 - i * 2.0
		var base_y := -1.0 - i * 1.2
		var step := CSGBox3D.new()
		step.size = Vector3(w, 1.0, 6.0)
		step.position = Vector3(-9.0 - i * 1.5, base_y, 8.0 + i * 1.0)
		step.material = _solid_material(COL_GROUND_LOW.lerp(COL_FOG, i * 0.2))
		root.add_child(step)
		# Rock strata: thin darker bands on the cliff face.
		for s in range(2):
			var band := _box(Vector3(w + 0.1, 0.18, 6.1), COL_STONE_DARK.lerp(COL_FOG, i * 0.25))
			band.position = Vector3(-9.0 - i * 1.5, base_y - 0.25 - s * 0.4, 8.0 + i * 1.0)
			root.add_child(band)

	# --- Carved stairway up the plateau edge (front) ---
	root.add_child(_make_stairs(Vector3(5.5, 0.5, 9.5), 5))

	# --- Winding path (two angled flat strips of pale dirt) ---
	var path_a := CSGBox3D.new()
	path_a.size = Vector3(2.0, 0.12, 11.0)
	path_a.position = Vector3(-2.0, 0.52, 2.0)
	path_a.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	path_a.material = _solid_material(COL_PATH, 1.0)
	root.add_child(path_a)

	var path_b := CSGBox3D.new()
	path_b.size = Vector3(2.0, 0.12, 8.0)
	path_b.position = Vector3(1.5, 0.52, -5.0)
	path_b.rotation_degrees = Vector3(0.0, -22.0, 0.0)
	path_b.material = _solid_material(COL_PATH, 1.0)
	root.add_child(path_b)

	# --- Domed observatory (back-centre), with a warm-lit doorway ---
	root.add_child(_make_domed_ruin(Vector3(2.0, 0.5, -7.5), 2.4, true))
	# --- Second, smaller dome (right) ---
	root.add_child(_make_domed_ruin(Vector3(9.0, 0.5, -1.0), 1.8, false))

	# --- A broken arch (left) ---
	root.add_child(_make_arch(Vector3(-8.0, 0.5, -3.0)))

	# --- Bunting strung across the camp (the Singers are here) ---
	root.add_child(_make_bunting(Vector3(-5.0, 0.5, 4.0), Vector3(-1.0, 0.5, -1.0)))
	root.add_child(_make_bunting(Vector3(-1.0, 0.5, -1.0), Vector3(4.0, 0.5, -3.5)))
	root.add_child(_make_bunting(Vector3(4.0, 0.5, -3.5), Vector3(6.5, 0.5, 1.0)))

	# --- Grass tufts and pale flora, clustered along edges and ruins ---
	for n in range(34):
		var tuft := _make_grass_tuft(
			Vector3(rng.randf_range(-11.0, 11.0), 0.5, rng.randf_range(-9.0, 9.0)), rng
		)
		root.add_child(tuft)

	# --- A little scattered rubble near the ruins ---
	for n in range(8):
		var s := rng.randf_range(0.3, 0.6)
		var chunk := _box(Vector3(s, s * 0.6, s), COL_STONE_DARK)
		chunk.position = Vector3(rng.randf_range(-9.0, 9.0), 0.5 + s * 0.3, rng.randf_range(-7.0, 7.0))
		chunk.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 90.0), 0.0)
		root.add_child(chunk)

	return root


func _make_stairs(base_pos: Vector3, steps: int) -> Node3D:
	var stair := Node3D.new()
	stair.position = base_pos
	for i in range(steps):
		var s := _box(Vector3(3.0, 0.3, 0.7), COL_STONE.lerp(COL_GROUND, 0.4))
		s.position = Vector3(0.0, -0.15 - i * 0.3, 0.7 + i * 0.7)
		stair.add_child(s)
	return stair


func _make_grass_tuft(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var tuft := Node3D.new()
	tuft.position = pos
	var base := COL_FLORA2 if rng.randf() < 0.3 else COL_FLORA  # pale cool variation
	for i in range(rng.randi_range(4, 7)):
		var h := rng.randf_range(0.4, 0.95)
		var blade := _box(Vector3(0.05, h, 0.05), base.lerp(COL_GROUND, rng.randf() * 0.35))
		blade.position = Vector3(rng.randf_range(-0.2, 0.2), h * 0.5, rng.randf_range(-0.2, 0.2))
		blade.rotation_degrees = Vector3(
			rng.randf_range(-18.0, 18.0), rng.randf_range(0.0, 360.0), rng.randf_range(-18.0, 18.0)
		)
		tuft.add_child(blade)
	return tuft


func _make_bunting(a: Vector3, b: Vector3) -> Node3D:
	var n := Node3D.new()
	# Posts at each end.
	for p in [a, b]:
		var post := _box(Vector3(0.18, 3.0, 0.18), COL_STONE_DARK)
		post.position = p + Vector3(0.0, 1.5, 0.0)
		n.add_child(post)
	# Drooping line: two segments to a sagged midpoint.
	var top_a := a + Vector3(0.0, 2.9, 0.0)
	var top_b := b + Vector3(0.0, 2.9, 0.0)
	var mid := (top_a + top_b) * 0.5 + Vector3(0.0, -0.5, 0.0)
	n.add_child(_line_segment(top_a, mid, COL_STONE_DARK))
	n.add_child(_line_segment(mid, top_b, COL_STONE_DARK))
	# Triangular-ish flags hanging along the line, alternating warm / pale.
	_hang_flags(n, top_a, mid)
	_hang_flags(n, mid, top_b)
	return n


func _line_segment(p: Vector3, q: Vector3, col: Color) -> MeshInstance3D:
	var seg := _box(Vector3(0.04, 0.04, p.distance_to(q)), col)
	var d := (q - p).normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x := up.cross(d).normalized()
	var y := d.cross(x).normalized()
	seg.transform = Transform3D(Basis(x, y, d), (p + q) * 0.5)
	return seg


func _hang_flags(parent: Node3D, p: Vector3, q: Vector3) -> void:
	var count := maxi(2, int(p.distance_to(q) / 0.55))
	for i in range(1, count):
		var pos := p.lerp(q, float(i) / count)
		var col := COL_PALE if i % 2 == 0 else COL_FLORA  # muted cool flags
		var flag := _box(Vector3(0.34, 0.42, 0.02), col, 0.8)
		flag.position = pos + Vector3(0.0, -0.26, 0.0)
		flag.rotation_degrees.x = 12.0
		parent.add_child(flag)


func _make_domed_ruin(base_pos: Vector3, radius: float, lit_doorway: bool) -> Node3D:
	var ruin := Node3D.new()
	ruin.position = base_pos

	var drum := CSGCylinder3D.new()
	drum.radius = radius
	drum.height = radius * 1.1
	drum.position = Vector3(0.0, radius * 0.55, 0.0)
	drum.material = _solid_material(COL_STONE)
	ruin.add_child(drum)

	# Faceted dome (low segment count reads as built panels, not a balloon).
	var dome := CSGSphere3D.new()
	dome.radius = radius
	dome.radial_segments = 8
	dome.rings = 4
	dome.position = Vector3(0.0, radius * 1.1, 0.0)
	dome.material = _solid_material(COL_STONE.lerp(COL_PALE, 0.12))
	ruin.add_child(dome)

	# Structural ring band where dome meets drum.
	var band := CSGCylinder3D.new()
	band.radius = radius * 1.06
	band.height = 0.3
	band.position = Vector3(0.0, radius * 1.1, 0.0)
	band.material = _solid_material(COL_STONE_DARK)
	ruin.add_child(band)

	# Finial spire on top.
	var spire := _box(Vector3(0.18, radius * 0.7, 0.18), COL_STONE_DARK)
	spire.position = Vector3(0.0, radius * 2.0 + radius * 0.35, 0.0)
	ruin.add_child(spire)

	# Arched doorway: dark recess + a stone surround.
	var door := CSGBox3D.new()
	door.size = Vector3(radius * 0.5, radius * 0.85, 0.7)
	door.position = Vector3(0.0, radius * 0.42, radius * 0.95)
	door.material = _solid_material(Color("10131a"))
	ruin.add_child(door)
	var lintel := _box(Vector3(radius * 0.72, 0.25, 0.3), COL_STONE_DARK)
	lintel.position = Vector3(0.0, radius * 0.88, radius * 1.0)
	ruin.add_child(lintel)

	if lit_doorway:
		var glow := OmniLight3D.new()
		glow.light_color = COL_DOORWAY
		glow.light_energy = 9.0
		glow.omni_range = radius * 4.0
		glow.position = Vector3(0.0, radius * 0.4, radius * 1.1)
		ruin.add_child(glow)

	return ruin


func _make_arch(base_pos: Vector3) -> Node3D:
	var arch := Node3D.new()
	arch.position = base_pos
	var mat := _solid_material(COL_STONE_DARK)
	for dx in [-1.4, 1.4]:
		var pillar := CSGBox3D.new()
		pillar.size = Vector3(0.8, 4.0, 0.8)
		pillar.position = Vector3(dx, 2.0, 0.0)
		pillar.material = mat
		arch.add_child(pillar)
	var lintel := CSGBox3D.new()
	lintel.size = Vector3(3.6, 0.8, 0.8)
	lintel.position = Vector3(0.0, 4.0, 0.0)
	lintel.material = mat
	arch.add_child(lintel)
	# A broken-off stub on top, suggesting ruin.
	var stub := _box(Vector3(0.8, 1.2, 0.8), COL_STONE_DARK)
	stub.position = Vector3(-1.4, 5.0, 0.0)
	stub.rotation_degrees.z = 8.0
	arch.add_child(stub)
	return arch


func _make_warrior() -> Sprite3D:
	for dir_name in DIR_NAMES:
		_dir_textures[dir_name] = load("res://assets/sprites/warrior_8dir/%s.png" % dir_name)
	var sprite := Sprite3D.new()
	sprite.name = "Warrior"
	sprite.texture = _dir_textures[_facing]
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.pixel_size = 0.045  # 64px -> ~2.9 world units tall
	sprite.position = Vector3(-1.0, WARRIOR_Y, 1.0)  # standing on the path
	_warrior = sprite
	return sprite


func _process(delta: float) -> void:
	_update_camera(delta)
	_update_warrior(delta)


func _update_camera(delta: float) -> void:
	# Free, continuous orbit on Q / E (and left/right arrows). Pitch stays
	# locked, so the isometric perspective is preserved at any yaw.
	var spin := 0.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		spin += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
		spin -= 1.0
	if spin != 0.0:
		_orbit(spin * ROT_SPEED * delta)


func _orbit(delta_deg: float) -> void:
	_yaw = fmod(_yaw + delta_deg, 360.0)
	_pivot.rotation_degrees.y = _yaw


func _update_warrior(delta: float) -> void:
	if _warrior == null:
		return
	# Camera-relative ground vectors (so "up" on screen is always away).
	var basis := _camera.global_transform.basis
	var fwd := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length() < 0.1:
		return  # idle: keep last facing

	var move := (right * input.x - fwd * input.y).normalized()
	var pos := _warrior.position + move * WARRIOR_SPEED * delta
	pos.x = clampf(pos.x, -BOUNDS.x, BOUNDS.x)
	pos.z = clampf(pos.z, -BOUNDS.y, BOUNDS.y)
	pos.y = WARRIOR_Y
	_warrior.position = pos

	# Pick the 8-dir sheet from the move direction *as seen on screen*.
	var screen_x := move.dot(right)
	var screen_up := move.dot(fwd)
	var angle := rad_to_deg(atan2(screen_x, screen_up))  # 0 = away, +90 = right
	var idx := int(round(angle / 45.0)) % DIR_NAMES.size()
	if idx < 0:
		idx += DIR_NAMES.size()
	if _facing != DIR_NAMES[idx]:
		_facing = DIR_NAMES[idx]
		_warrior.texture = _dir_textures[_facing]


func _capture_and_quit() -> void:
	# Let the renderer settle, then dump the SubViewport to disk for review.
	get_tree().create_timer(8.0).timeout.connect(func() -> void: get_tree().quit(2))
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var img := _post_viewport.get_texture().get_image()
	var path := CAPTURE_PATH
	if _yaw != 45.0:
		path = "res://docs/gen/ring1_iso_spike_yaw%d.png" % int(_yaw)
	var err := img.save_png(path)
	if err != OK:
		push_warning("ring1_iso_test: capture failed (%d)" % err)
	get_tree().quit(0 if err == OK else 1)
