extends Node

## EXPLORATORY SPIKE — not part of the game.
## Authentic 3D pixel-art rendering, t3ssel8r / David Holland technique.
## Walled off: own scene + script + shaders, touches nothing in the run loop,
## never modifies project.godot (the 3D world lives in a SubViewport).
##
## The five techniques, each gated so they can be proven one at a time via the
## `pipeline=` command-line arg (baseline | snap | subpixel | outline | full):
##   1. Render the 3D scene to a low-res target at pixel-art resolution.
##   2. Pixel-perfect CAMERA SNAP: snap the follow-camera to whole-texel world
##      increments so the world does not sub-pixel jitter.
##   3. SUB-PIXEL SMOOTHING: render to a target padded by a few px, snap the
##      camera to texels, then offset the final upscaled blit by the fractional
##      sub-pixel remainder -> smooth motion AND crisp stable pixels, no crawl.
##   4. Depth-based pixel outlines (silhouette + interior creases).
##   5. Toon/banded lighting (cel.gdshader) + stable grid-anchored dither.
##
## The headline (sub-pixel smoothing) is a TRANSLATION fix: the harness FOLLOWS a
## moving warrior so the camera actually translates. Camera orbit (Q/E) reprojects
## the scene every frame, so snapping only *reduces* orbit shimmer, never removes
## it -- judged separately.
##
## Interactive: WASD walk the warrior (camera follows), Q/E orbit.
## Capture: `-- --capture pipeline=full frames=6 step=0.05` renders a pan sequence
## to res://docs/gen/ and quits (windowed; --headless cannot render 3D).

const RENDER_SIZE := Vector2i(320, 180)   # low internal pixel grid
const PAD := 3                            # texels of overscan each side for sub-pixel slide
const UPSCALE := 4                        # window = RENDER_SIZE * UPSCALE = 1280x720
const BASE_ORTHO := 26.0                  # ortho world-units shown vertically across RENDER_SIZE.y

const WARRIOR_SPEED := 5.0
const ROT_SPEED := 90.0
const WARRIOR_Y := 2.0
const PIVOT_Y := 0.5
const BOUNDS := Vector2(11.0, 9.0)

const DIR_NAMES := [
	"north", "north-east", "east", "south-east",
	"south", "south-west", "west", "north-west",
]

# Pale Reaches palette, sampled from the Ring 1 concept art (cool desaturated ramp).
const PALETTE := [
	"2a333f", "36414f", "485462", "4c5a6d",
	"566375", "5a697d", "616b78", "667383",
	"6e7a89", "7c8591", "8b95a0",
	"a8b1ba", "cbd2d3",
	"c89a5e",
]

const COL_GROUND := Color("7c8591")
const COL_GROUND_LOW := Color("4c5a6d")
const COL_PATH := Color("98a0a8")
const COL_STONE := Color("667383")
const COL_STONE_DARK := Color("3c4756")
const COL_FLORA := Color("828d9b")
const COL_FLORA2 := Color("6e7a89")
const COL_PALE := Color("cbd2d3")
const COL_DOORWAY := Color("c89a5e")
const COL_FOG := Color("5a697d")
const COL_BG := Color("5a697d")
const COL_AMBIENT := Color("eef1f5")

# Derived pixel-grid maths.
var _padded := RENDER_SIZE + Vector2i(2 * PAD, 2 * PAD)
var _world_per_texel := BASE_ORTHO / float(RENDER_SIZE.y)
var _cam_size := BASE_ORTHO * float(_padded.y) / float(RENDER_SIZE.y)

# Pipeline gates (set from `pipeline=` arg; full = all on).
var _snap := true
var _subpixel := true
var _outline := true
var _dither := 0.0   # Bayer 4x4 ordered dither (0 = off; anchored to the low-res grid)

var _pivot: Node3D
var _camera: Camera3D
var _world_viewport: SubViewport
var _post_viewport: SubViewport
var _screen_viewport: SubViewport   # composited output at RENDER_SIZE*UPSCALE (captured)
var _display: TextureRect
var _yaw := 45.0
var _warrior: Sprite3D
var _dir_textures := {}
var _facing := "south"
var _cel_shader: Shader
var _target := Vector3(0.0, PIVOT_Y, 0.0)   # desired (continuous) follow position
var _capturing := false


func _ready() -> void:
	_cel_shader = load("res://assets/shaders/cel.gdshader")
	_parse_pipeline_arg()
	get_window().size = RENDER_SIZE * UPSCALE
	_build_display()
	_build_world()
	# Place camera/warrior so the very first frame is already snapped & centred.
	_target = Vector3(_warrior.position.x, PIVOT_Y, _warrior.position.z)
	_update_camera_follow(0.0)

	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		_capturing = true
		_run_capture(args)


func _parse_pipeline_arg() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("pipeline="):
			var mode := a.trim_prefix("pipeline=")
			# Each later stage builds on the earlier ones.
			_snap = mode in ["snap", "subpixel", "outline", "full"]
			_subpixel = mode in ["subpixel", "outline", "full"]
			_outline = mode in ["outline", "full"]
		elif a.begins_with("dither="):
			_dither = float(a.trim_prefix("dither="))


func _build_display() -> void:
	# 3D world -> _world_viewport (padded) -> TextureRect w/ palette post -> _post_viewport
	# (padded) -> _display TextureRect upscaled NEAREST, offset by the sub-pixel remainder.
	_world_viewport = SubViewport.new()
	_world_viewport.size = _padded
	_world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world_viewport.transparent_bg = false
	# No temporal/MSAA jitter -- it would masquerade as (and dominate) orbit shimmer.
	_world_viewport.use_taa = false
	_world_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_world_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(_world_viewport)

	_post_viewport = SubViewport.new()
	_post_viewport.size = _padded
	_post_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_post_viewport)

	var post_rect := TextureRect.new()
	post_rect.size = Vector2(_padded)
	post_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	post_rect.stretch_mode = TextureRect.STRETCH_SCALE
	post_rect.texture = _world_viewport.get_texture()
	post_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	post_rect.material = _make_post_material()
	_post_viewport.add_child(post_rect)

	# Composited output at a deterministic RENDER_SIZE*UPSCALE, independent of the OS
	# window (which the project's content-scale settings can override). This is what
	# gets captured, and the sub-pixel offset lives here (in the blit, not the RT).
	_screen_viewport = SubViewport.new()
	_screen_viewport.size = RENDER_SIZE * UPSCALE
	_screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_screen_viewport)

	# Upscale the padded post render NEAREST. Sized PADDED*UPSCALE so the inner
	# RENDER_SIZE region fills the screen with PAD*UPSCALE overscan on each side
	# (room to slide by the sub-pixel offset without revealing a gap).
	_display = TextureRect.new()
	_display.texture = _post_viewport.get_texture()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.size = Vector2(_padded) * float(UPSCALE)
	_display.position = Vector2(-PAD * UPSCALE, -PAD * UPSCALE)
	_screen_viewport.add_child(_display)

	# Live on-screen view: the composited screen viewport, scaled to fit the window.
	var window_view := TextureRect.new()
	window_view.texture = _screen_viewport.get_texture()
	window_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	window_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	window_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(window_view)


func _make_post_material() -> ShaderMaterial:
	var pal := PackedVector3Array()
	for hex in PALETTE:
		var c := Color(hex)
		pal.append(Vector3(c.r, c.g, c.b))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/pixel_post.gdshader")
	mat.set_shader_parameter("palette", pal)
	mat.set_shader_parameter("palette_count", pal.size())
	mat.set_shader_parameter("tex_size", Vector2(_padded))
	mat.set_shader_parameter("dither_strength", _dither)
	mat.set_shader_parameter("edge_strength", 0.0)  # depth outline replaces the Sobel
	return mat


func _build_world() -> void:
	_world_viewport.add_child(_make_environment())
	_world_viewport.add_child(_make_key_light())
	_world_viewport.add_child(_make_camera_rig())
	_world_viewport.add_child(_make_terrain())
	_world_viewport.add_child(_make_warrior())
	if _outline:
		_camera.add_child(_make_outline_overlay())


func _make_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COL_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = COL_AMBIENT
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = COL_FOG
	env.fog_light_energy = 1.0
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	return we


func _make_key_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, 130.0, 0.0)
	light.light_color = Color("c8d0db")
	light.light_energy = 1.0
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	return light


func _make_camera_rig() -> Node3D:
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position = Vector3(0.0, PIVOT_Y, 0.0)
	_pivot.rotation_degrees = Vector3(-30.0, _yaw, 0.0)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _cam_size
	_camera.position = Vector3(0.0, 0.0, 22.0)
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.current = true
	_pivot.add_child(_camera)
	return _pivot


func _make_outline_overlay() -> MeshInstance3D:
	# Full-screen post quad in the transparent pass: reads DEPTH_TEXTURE (available
	# after opaque), darkens silhouette + crease edges by alpha. In the transparent
	# pass so SCREEN_TEXTURE ordering is never an issue.
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/pixel_outline_t3.gdshader")
	mat.set_shader_parameter("view_size", Vector2(_padded))
	mat.set_shader_parameter("depth_threshold", 0.16)
	mat.set_shader_parameter("normal_threshold", 0.12)
	mat.set_shader_parameter("outline_color", Vector3(0.08, 0.10, 0.14))
	mat.set_shader_parameter("outline_strength", 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "OutlineOverlay"
	mi.mesh = quad
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _solid_material(col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _cel_shader
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("bands", 2.0)
	m.set_shader_parameter("light_gain", 0.3)
	return m


func _box(size: Vector3, col: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _solid_material(col)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	return mi


func _make_terrain() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	var land := CSGBox3D.new()
	land.size = Vector3(300.0, 2.0, 300.0)
	land.position = Vector3(0.0, -2.6, 0.0)
	land.material = _solid_material(COL_GROUND_LOW)
	root.add_child(land)

	var plateau := CSGBox3D.new()
	plateau.size = Vector3(30.0, 1.0, 26.0)
	plateau.position = Vector3(0.0, 0.0, 0.0)
	plateau.material = _solid_material(COL_GROUND)
	root.add_child(plateau)

	for n in range(7):
		var patch := _box(
			Vector3(rng.randf_range(3.0, 6.0), 0.06, rng.randf_range(3.0, 6.0)),
			COL_GROUND_LOW if n % 2 == 0 else COL_GROUND.lerp(COL_PATH, 0.25)
		)
		patch.position = Vector3(rng.randf_range(-10.0, 10.0), 0.5, rng.randf_range(-8.0, 8.0))
		patch.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		root.add_child(patch)

	# Stone blocks of varied height -- give the outline pass crisp silhouettes + creases.
	for n in range(9):
		var h := rng.randf_range(1.2, 3.4)
		var blk := _box(Vector3(rng.randf_range(1.4, 2.6), h, rng.randf_range(1.4, 2.6)),
			COL_STONE if n % 2 == 0 else COL_STONE.lerp(COL_STONE_DARK, 0.5))
		blk.position = Vector3(rng.randf_range(-10.0, 10.0), 0.5 + h * 0.5, rng.randf_range(-8.0, 8.0))
		blk.rotation_degrees.y = rng.randf_range(0.0, 45.0)
		root.add_child(blk)

	root.add_child(_make_domed_ruin(Vector3(3.0, 0.5, -7.5), 2.4, true))
	root.add_child(_make_domed_ruin(Vector3(9.0, 0.5, 2.0), 1.8, false))
	root.add_child(_make_arch(Vector3(-8.0, 0.5, -3.0)))

	for n in range(30):
		root.add_child(_make_grass_tuft(
			Vector3(rng.randf_range(-11.0, 11.0), 0.5, rng.randf_range(-9.0, 9.0)), rng))

	return root


func _make_grass_tuft(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var tuft := Node3D.new()
	tuft.position = pos
	var base := COL_FLORA2 if rng.randf() < 0.3 else COL_FLORA
	for i in range(rng.randi_range(4, 7)):
		var h := rng.randf_range(0.4, 0.95)
		var blade := _box(Vector3(0.06, h, 0.06), base.lerp(COL_GROUND, rng.randf() * 0.35))
		blade.position = Vector3(rng.randf_range(-0.2, 0.2), h * 0.5, rng.randf_range(-0.2, 0.2))
		blade.rotation_degrees = Vector3(
			rng.randf_range(-18.0, 18.0), rng.randf_range(0.0, 360.0), rng.randf_range(-18.0, 18.0))
		tuft.add_child(blade)
	return tuft


func _make_domed_ruin(base_pos: Vector3, radius: float, lit_doorway: bool) -> Node3D:
	var ruin := Node3D.new()
	ruin.position = base_pos

	var drum := CSGCylinder3D.new()
	drum.radius = radius
	drum.height = radius * 1.1
	drum.position = Vector3(0.0, radius * 0.55, 0.0)
	drum.material = _solid_material(COL_STONE)
	ruin.add_child(drum)

	var dome := CSGSphere3D.new()
	dome.radius = radius
	dome.radial_segments = 8
	dome.rings = 4
	dome.position = Vector3(0.0, radius * 1.1, 0.0)
	dome.material = _solid_material(COL_STONE.lerp(COL_PALE, 0.12))
	ruin.add_child(dome)

	var spire := _box(Vector3(0.18, radius * 0.7, 0.18), COL_STONE_DARK)
	spire.position = Vector3(0.0, radius * 2.0 + radius * 0.35, 0.0)
	ruin.add_child(spire)

	var door := CSGBox3D.new()
	door.size = Vector3(radius * 0.5, radius * 0.85, 0.7)
	door.position = Vector3(0.0, radius * 0.42, radius * 0.95)
	door.material = _solid_material(Color("10131a"))
	ruin.add_child(door)

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
	sprite.pixel_size = 0.045
	sprite.position = Vector3(0.0, WARRIOR_Y, 0.0)
	_warrior = sprite
	return sprite


func _process(delta: float) -> void:
	if _capturing:
		return
	_update_orbit(delta)
	_update_warrior(delta)
	_update_camera_follow(delta)


func _update_orbit(delta: float) -> void:
	var spin := 0.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		spin += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
		spin -= 1.0
	if spin != 0.0:
		_yaw = fmod(_yaw + spin * ROT_SPEED * delta, 360.0)
		_pivot.rotation_degrees.y = _yaw


func _update_warrior(delta: float) -> void:
	if _warrior == null:
		return
	var basis := _camera.global_transform.basis
	var fwd := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length() < 0.1:
		return
	var move := (right * input.x - fwd * input.y).normalized()
	var pos := _warrior.position + move * WARRIOR_SPEED * delta
	pos.x = clampf(pos.x, -BOUNDS.x, BOUNDS.x)
	pos.z = clampf(pos.z, -BOUNDS.y, BOUNDS.y)
	pos.y = WARRIOR_Y
	_warrior.position = pos

	var screen_x := move.dot(right)
	var screen_up := move.dot(fwd)
	var angle := rad_to_deg(atan2(screen_x, screen_up))
	var idx := int(round(angle / 45.0)) % DIR_NAMES.size()
	if idx < 0:
		idx += DIR_NAMES.size()
	if _facing != DIR_NAMES[idx]:
		_facing = DIR_NAMES[idx]
		_warrior.texture = _dir_textures[_facing]


func _update_camera_follow(_delta: float) -> void:
	# Camera follows the warrior (translation -> exercises the sub-pixel headline).
	_target = Vector3(_warrior.position.x, PIVOT_Y, _warrior.position.z)
	var b := _camera.global_transform.basis
	var right := b.x.normalized()
	var up := b.y.normalized()
	var fwd := -b.z.normalized()

	if not _snap:
		_pivot.position = _target
		_set_subpixel_offset(Vector2.ZERO)
		return

	# Decompose desired position onto the camera's screen axes, snap the two screen
	# components to whole texels, keep depth (forward) continuous.
	var a := _target.dot(right)
	var c := _target.dot(up)
	var d := _target.dot(fwd)
	var a_s: float = round(a / _world_per_texel) * _world_per_texel
	var c_s: float = round(c / _world_per_texel) * _world_per_texel
	_pivot.position = right * a_s + up * c_s + fwd * d

	# Fractional remainder in texels -> sub-pixel display offset.
	var frac := Vector2((a - a_s) / _world_per_texel, (c - c_s) / _world_per_texel)
	_set_subpixel_offset(frac if _subpixel else Vector2.ZERO)


func _set_subpixel_offset(frac_texels: Vector2) -> void:
	# Snapping the camera back by `frac` texels shifts the projected world forward on
	# screen; offset the blit by -frac (in screen px) to cancel it -> the composited
	# image slides smoothly by the true sub-texel amount while the RT pixels stay
	# crisp and stable. Sign verified empirically: a screen-right pan must yield a
	# smooth +1px/frame composited shift (see docs/gen capture analysis).
	var off := Vector2(-frac_texels.x, frac_texels.y) * float(UPSCALE)
	_display.position = Vector2(-PAD * UPSCALE, -PAD * UPSCALE) + off


func _run_capture(args: Array) -> void:
	# Pan the camera along the screen-RIGHT axis in known sub-texel steps so the
	# headline can be measured: how does the composited image (and the low-res RT)
	# respond to motion smaller than one texel?
	var frames := 6
	var step := 0.25      # pan: screen-right texels/frame.  orbit: degrees/frame.
	var motion := "pan"   # pan (translation headline) | orbit (the residual hard case)
	for a in args:
		if a.begins_with("frames="):
			frames = int(a.trim_prefix("frames="))
		elif a.begins_with("step="):
			step = float(a.trim_prefix("step="))
		elif a.begins_with("motion="):
			motion = a.trim_prefix("motion=")
	get_tree().create_timer(25.0).timeout.connect(func() -> void: get_tree().quit(2))
	var tag := "full"
	if not _snap:
		tag = "baseline"
	elif not _subpixel:
		tag = "snap"
	elif not _outline:
		tag = "subpixel"
	if motion == "orbit":
		tag = "orbit_" + tag

	# World-space screen-right axis (horizontal; roll is 0 so it has no Y component).
	var right := _camera.global_transform.basis.x.normalized()
	var base := Vector3(0.0, WARRIOR_Y, 0.0)

	for i in range(frames):
		if motion == "orbit":
			# Warrior stationary; sweep yaw. A pure orbit never translates the follow
			# target, so the snap/sub-pixel machinery is a structural no-op here --
			# this captures the residual reprojection crawl the headline cannot touch.
			_warrior.position = base
			_yaw = 45.0 + step * float(i)
			_pivot.rotation_degrees.y = _yaw
		else:
			# Advance the follow target by `step` texels along screen-right -> a precise
			# sub-texel pan, independent of yaw and of world axes.
			_warrior.position = base + right * (step * float(i) * _world_per_texel)
		_update_camera_follow(0.0)
		for _f in range(4):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		# COMPOSITED screen viewport (the sub-pixel offset lives in this blit).
		var err := _screen_viewport.get_texture().get_image().save_png(
			"res://docs/gen/t3_%s_%d.png" % [tag, i])
		if err != OK:
			push_warning("pixelart_t3_test: capture failed (%d)" % err)
		# Low-res RT (pre-blit): proves whether the camera snapped to the same texel
		# grid (RT identical) or sub-pixel-jittered (RT changes).
		_post_viewport.get_texture().get_image().save_png(
			"res://docs/gen/t3_%s_rt%d.png" % [tag, i])
	get_tree().quit(0)
