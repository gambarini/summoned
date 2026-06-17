extends Node
class_name WarriorSync

## Phase 2 hybrid binding: the warrior's 2D `CharacterBody2D` stays the source of
## truth (Option B); this drives a camera-facing 3D billboard from it each frame.
##
## - Position: `Vector2(x,y)` sim px -> `Vector3(x,0,y)` world units (the
##   transform below is ring-specific, so it lives here, not on the reusable rig).
## - Facing: the 8-dir sheet picked from the body's *velocity* relative to camera
##   yaw (via the rig's pure-math helper) — so the sprite faces correctly at any
##   orbit angle.
## - Input: a camera-relative provider injected into the warrior, so "up" is
##   always away-from-camera as the camera rotates.
## - The 2D body is hidden (`visible = false` on the root) — physics, timers,
##   combat, and signals keep running; only the 2D *presentation* is suppressed,
##   which also defers effects-as-3D (the notation/Hollow nodes) to Phase 2b.

# --- sim<->world transform ----------------------------------------------
# The transform itself lives in `SimSpace` (shared with the enemy/arc sync and
# the mouse aim). Only the warrior-specific hover height stays here.
const HOVER_Y := 2.0                        # billboard height on the plateau top
const MOVE_EPSILON := 8.0                   # px/s; below this, keep last facing
# Vertical hover bob (ports the warrior's 2D HOVER_SPEED 0.8 / HOVER_PIXELS 1.5;
# amplitude in world units, a touch over the literal px*pixel_size for iso punch).
const BOB_SPEED := 0.8
const BOB_AMPLITUDE := 0.1

const DIR_NAMES := [
	"north", "north-east", "east", "south-east",
	"south", "south-west", "west", "north-west",
]

# --- Notation drift (warrior's "cloak dissolves into notation" identity) --
# Port of the warrior's 2D GPUParticles2D to 3D: same ParticleProcessMaterial
# shape, with px values rescaled to world units (÷PPU). World-space (local=false)
# so the emitter leaves a debris trail as the warrior moves.
const NOTATION_SHEET := preload("res://assets/sprites/notation_glyphs.png")
const NOTATION_Y := 1.7            # chest height on the billboard
const _PX := 1.0 / SimSpace.PIXELS_PER_UNIT

# Fixed raw input for programmatic/headless drive (capture harness). The
# `Vector2.INF` sentinel means "read live Input" (the normal play path).
var raw_input_override := Vector2.INF

var _rig: IsoRig
var _warrior: CharacterBody2D
var _billboard: Sprite3D
var _dir_textures := {}
var _facing := "south"
var _bob_phase := 0.0
var _bob_y := 0.0  # current hover offset; a future Hollow node rides this too
var _notation: GPUParticles3D


## Current 8-dir sheet name (for verification / debugging).
func get_facing() -> String:
	return _facing


## The billboard's world position — output of the sim->world transform.
func get_billboard_position() -> Vector3:
	return _billboard.position


## Camera-relative attack aim (Phase 3). The 2D cursor no longer maps to the
## world, so convert the screen cursor into a sim-space direction: undo the
## display's letterbox (window px -> render px), find the warrior's position in
## that same viewport space, and feed the on-screen delta to the proven
## `camera_relative_dir()` — for an ortho camera, screen direction maps faithfully
## to ground direction, so no hand-rolled ground raycast is needed. `screen_pos`
## is in root-viewport (window) coordinates.
func aim_dir_from_screen(screen_pos: Vector2) -> Vector2:
	var cam := _rig.get_camera()
	var render_size := Vector2(_rig.render_size)
	var win := get_viewport().get_visible_rect().size
	# Inverse of the display TextureRect's KEEP_ASPECT_CENTERED letterbox.
	var fit := minf(win.x / render_size.x, win.y / render_size.y)
	var offset := (win - render_size * fit) * 0.5
	var vp_pos := (screen_pos - offset) / fit
	var warrior_vp := cam.unproject_position(SimSpace.to_world(_warrior.global_position, HOVER_Y))
	return _rig.camera_relative_dir(vp_pos - warrior_vp)


func setup(rig: IsoRig, warrior: CharacterBody2D) -> void:
	_rig = rig
	_warrior = warrior

	for d in DIR_NAMES:
		_dir_textures[d] = load("res://assets/sprites/warrior_8dir/%s.png" % d)

	_billboard = Sprite3D.new()
	_billboard.name = "WarriorBillboard"
	_billboard.texture = _dir_textures[_facing]
	_billboard.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_billboard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_billboard.shaded = false
	_billboard.pixel_size = 0.045
	rig.add_world_child(_billboard)

	# The billboard is the warrior now: suppress all 2D presentation in one line
	# (a hidden root Node2D isn't drawn even when children set visible=true), and
	# stop the 2D camera fighting the display. Physics/combat are untouched.
	_warrior.visible = false
	var cam := _warrior.get_node_or_null("Camera2D")
	if cam:
		cam.enabled = false

	# Camera-relative input: "up" stays away-from-camera at any yaw.
	_warrior.input_provider = Callable(self, "_camera_dir")
	# Camera-relative attack aim from the live cursor (the 2D mouse no longer maps
	# to the world). A test harness may override this with a synthetic cursor.
	_warrior.attack_dir_provider = Callable(self, "_aim_live")

	# Ability shockwaves (resonance/burst) become flat 3D ground discs instead of
	# 2D rings drawn over the iso view (Phase 2b).
	_warrior.suppress_world_vfx = true
	_warrior.ground_pulse.connect(_on_ground_pulse)

	_setup_notation()  # the drifting-score-debris identity, as 3D particles
	_sync_position()  # place the billboard before the first frame


# --- Ability shockwave VFX (resonance / burst) ---------------------------
const PULSE_Y := 0.55          # just above the plateau top (0.5) to avoid z-fight
const PULSE_DURATION := 0.34
const PULSE_FROM := 0.2        # start scale (fraction of the ring's full radius)
const PULSE_TO := 1.3          # end scale
const PULSE_THICKNESS := 0.16  # ring band as a fraction of radius
# Translucent on a grey plateau + the palette snap = a faint filled disc washes
# back to grey. A concentrated, brighter ring survives the snap and reads as a
# shockwave; bump the (intentionally subtle) 2D alpha to a floor that holds up.
const PULSE_MIN_ALPHA := 0.85

# Spawn a self-animating flat ring at the pulse centre — own scale+alpha tween,
# then frees itself. No 2D node is ever created, so nothing flashes over the view.
func _on_ground_pulse(center: Vector2, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _make_ground_ring(radius / SimSpace.PIXELS_PER_UNIT, PULSE_THICKNESS)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var start_a := maxf(color.a, PULSE_MIN_ALPHA)
	mat.albedo_color = Color(color.r, color.g, color.b, start_a)
	ring.material_override = mat
	ring.position = SimSpace.to_world(center, PULSE_Y)
	_rig.add_world_child(ring)

	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(PULSE_TO, 1.0, PULSE_TO), PULSE_DURATION) \
		.from(Vector3(PULSE_FROM, 1.0, PULSE_FROM))
	# Hold bright while it expands (reads as a shockwave; a translucent ring that
	# fades the whole way re-blends to grey under the palette snap), fade only late.
	t.tween_property(mat, "albedo_color:a", 0.0, PULSE_DURATION * 0.5) \
		.from(start_a).set_delay(PULSE_DURATION * 0.5)
	t.chain().tween_callback(ring.queue_free)


# Flat annulus (ring band) in the XZ plane, outer radius in world units; `thickness`
# is the band width as a fraction of the radius. Triangle strip between two circles.
func _make_ground_ring(radius: float, thickness: float, steps := 40) -> ArrayMesh:
	var inner := radius * (1.0 - thickness)
	var verts := PackedVector3Array()
	for i in range(steps + 1):
		var a := (float(i) / steps) * TAU
		var dx := cos(a)
		var dz := sin(a)
		verts.append(Vector3(dx * inner, 0.0, dz * inner))
		verts.append(Vector3(dx * radius, 0.0, dz * radius))
	var indices := PackedInt32Array()
	for i in range(steps):
		var b := i * 2
		indices.append(b); indices.append(b + 1); indices.append(b + 2)
		indices.append(b + 1); indices.append(b + 3); indices.append(b + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Attack aim from the live mouse cursor (root-viewport coords).
func _aim_live() -> Vector2:
	return aim_dir_from_screen(get_viewport().get_mouse_position())


# --- Notation drift particles (3D port) ----------------------------------

func _setup_notation() -> void:
	_notation = GPUParticles3D.new()
	_notation.name = "NotationDrift"
	_notation.amount = 24
	_notation.lifetime = 1.4
	_notation.randomness = 0.5
	_notation.preprocess = 1.4          # field already populated when the warrior appears
	_notation.local_coords = false      # world space -> movement leaves a debris trail
	_notation.amount_ratio = 0.32       # NOTATION_IDLE_RATIO(0.4) * tier0(0.8)

	# Each particle is a billboarded quad locked to one of the 4 glyph frames.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_texture = NOTATION_SHEET
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	gm.billboard_keep_scale = true
	gm.particles_anim_h_frames = 4
	gm.particles_anim_v_frames = 1
	gm.particles_anim_loop = false
	quad.material = gm
	_notation.draw_pass_1 = quad

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.7, 0.3)     # over the cloak silhouette
	pm.direction = Vector3(0.0, 1.0, 0.0)                # notation rises off the form
	pm.spread = 40.0
	pm.gravity = Vector3(0.0, 8.0 * _PX, 0.0)            # gentle upward drift
	pm.initial_velocity_min = 3.0 * _PX
	pm.initial_velocity_max = 9.0 * _PX
	pm.damping_min = 2.0 * _PX
	pm.damping_max = 6.0 * _PX                           # notes decelerate and hang
	pm.scale_min = 0.3
	pm.scale_max = 0.55                                  # small score debris
	pm.scale_curve = _build_notation_scale_curve()       # shrink as they dissolve
	pm.angle_min = -25.0
	pm.angle_max = 25.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0                       # slow continuous spin
	pm.tangential_accel_min = -6.0 * _PX
	pm.tangential_accel_max = 6.0 * _PX                  # gentle curl around the form
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 4.0 * _PX
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.4
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0                             # random frame across the strip
	pm.color_ramp = _build_notation_ramp()
	_notation.process_material = pm

	_notation.position = SimSpace.to_world(_warrior.global_position, NOTATION_Y)
	_rig.add_world_child(_notation)
	_notation.emitting = true


func _build_notation_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


func _build_notation_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.7))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


# Camera-relative sim-space move direction from raw input (live or overridden).
func _camera_dir() -> Vector2:
	var raw := raw_input_override
	if raw == Vector2.INF:
		raw = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return _rig.camera_relative_dir(raw)


# Visual sync runs after physics, so it reads the body's post-move state.
func _process(delta: float) -> void:
	# Hover bob (presentation only): advance + apply in IDLE/MOVE, freeze still
	# otherwise so attacks/hurt/death sit put — matching the 2D rule.
	if _warrior.vfx_hover_active():
		_bob_phase += BOB_SPEED * delta
		_bob_y = sin(_bob_phase) * BOB_AMPLITUDE
	else:
		_bob_y = 0.0
	_sync_position()
	_sync_facing()
	# World-space emitter follows the warrior; emitted glyphs stay put -> trail.
	if _notation:
		_notation.position = SimSpace.to_world(_warrior.global_position, NOTATION_Y)


func _sync_position() -> void:
	_billboard.position = SimSpace.to_world(_warrior.global_position, HOVER_Y + _bob_y)


func _sync_facing() -> void:
	var v := _warrior.velocity
	if v.length() < MOVE_EPSILON:
		return  # keep last facing while idle
	var dir_name := _rig.facing_name(Vector2(v.x, v.y))
	if dir_name != "" and dir_name != _facing:
		_facing = dir_name
		_billboard.texture = _dir_textures[_facing]
