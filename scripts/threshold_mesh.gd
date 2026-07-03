extends Node3D
class_name ThresholdMesh

## The Threshold as a low-poly cel-shaded 3D mesh (warrior pattern; replaces the
## flat Polygon2D billboard WorldSync used to raise for it). A stone-grey ambush
## predator: a low faceted carapace that presses flat into the terrain while Still,
## lifts and tracks the warrior while Assessing, stretches into the lunge while
## Committed, and hunches low while Withdrawn.
##
## The 2D sim (`creature_threshold.gd`) stays authoritative — this node is pure
## presentation, driven per-frame by `WorldSync` calling `sync_from(body, delta)`.
## The F2 read gate is preserved by construction: the emotional tell renders only
## on an unshaded "tell" channel (eye slit + carapace crack) tinted every frame
## from the sim's `Visual.color`, which creature.gd already keeps at the hidden
## grey until a Resonance pulse reveals it (and flashes white on a correct hit).
## The stone body itself never carries the tell, so an unread Threshold stays
## terrain-ambiguous — exactly the creature's design.
##
## Front faces local +Z; base sits at local y=0 (the caller parks the root on the
## plateau top). Built procedurally from primitives via `IsoRig.solid_material()`.

# Ground plane: the ring plateaus' top face (see WarriorSync.FEET_Y).
const GROUND_Y := 0.5

# Stone palette — deliberately near-terrain neutrals (the Still read is "cold
# negative space"), kept clear of the signal hues c0a0f0 / c4547a.
const STONE_DARK := Color("2b303c")
const STONE_MID := Color("49505f")
const STONE_BASE := Color("363c49")

# Pose throws.
const BODY_REST_Y := 0.10    # body pivot height at neutral
const LIFT_RISE := 0.26      # how far the carapace rises at full lift
const FLAT_SQUASH := 0.30    # vertical squash while pressed flat (Still)
const FLAT_WIDEN := 0.10     # footprint widens as it presses down
const STRETCH_Z := 0.38      # forward stretch of the committed lunge
const PITCH_STRETCH := 0.20  # nose-down pitch into the lunge (rad)
const LEG_BASE_ROLL := 0.6   # resting outward leg angle (rad)
const LEG_SPLAY_ROLL := 0.5  # extra splay at full alertness (rad)

# Smoothing rates (per second). The commit snap is fast — the lunge is "a single
# fast, costly" motion; everything else eases like stone deciding to move.
const POSE_RATE := 6.0
const COMMIT_RATE := 14.0
const TURN_RATE := 7.0
const COMMIT_TURN_RATE := 14.0

# Breathing pulse while Assessing — the only idle life it shows, and only then.
const PULSE_PERIOD := 1.1
const PULSE_AMP := 0.05

var _body: Node3D
var _tell_mat: StandardMaterial3D
var _legs: Array[Node3D] = []
var _leg_sides: Array[float] = []

# Smoothed pose channels.
var _lift: float = 0.0
var _stretch: float = 0.0
var _flatten: float = 1.0
var _splay: float = 0.0
var _pulse_t: float = 0.0


## Build the body under this node, using `rig` for cel materials.
func build(rig: IsoRig) -> void:
	var dark: Material = rig.solid_material(STONE_DARK)
	var mid: Material = rig.solid_material(STONE_MID)
	var base_mat: Material = rig.solid_material(STONE_BASE)
	_tell_mat = StandardMaterial3D.new()
	_tell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tell_mat.albedo_color = Color(0.533, 0.596, 0.659)  # creature.gd HIDDEN_COLOR until synced

	# Everything poseable hangs off one body pivot (lift/flatten/stretch).
	_body = Node3D.new()
	_body.position = Vector3(0.0, BODY_REST_Y, 0.0)
	add_child(_body)

	# Base skirt — the ground-contact ring the carapace sits on.
	_cone(0.50, 0.58, 0.14, Vector3(0.0, 0.06, 0.0), base_mat)
	# Carapace — a low 6-facet cone; reads as an angular boulder from the iso camera.
	_cone(0.16, 0.60, 0.38, Vector3(0.0, 0.26, 0.0), dark)
	# Spine ridge slab along the top, offset back.
	_box(Vector3(0.30, 0.12, 0.52), Vector3(0.0, 0.44, -0.06), mid, 0.0, 6.0)
	# Head wedge, front (+Z), low — an ambusher leads with its face near the ground.
	_box(Vector3(0.30, 0.16, 0.26), Vector3(0.0, 0.14, 0.50), dark, 0.0, -8.0)

	# Tell channel (the ONLY surfaces that carry the emotional read):
	# an eye slit across the head front + a crack seam along the carapace top.
	_box(Vector3(0.22, 0.05, 0.04), Vector3(0.0, 0.17, 0.62), _tell_mat)
	_box(Vector3(0.05, 0.03, 0.46), Vector3(0.0, 0.46, 0.04), _tell_mat, 0.0, 4.0)

	# Four leg stubs under the rim; they splay wider as it wakes.
	for side in [-1.0, 1.0]:
		for z in [0.26, -0.22]:
			var hip: Node3D = Node3D.new()
			hip.position = Vector3(side * 0.40, 0.10, z)
			_body.add_child(hip)
			_box(Vector3(0.09, 0.30, 0.09), Vector3(0.0, -0.15, 0.0), mid, 0.0, 0.0, hip)
			_legs.append(hip)
			_leg_sides.append(side)

	_apply_pose(0.0)


## Per-frame drive from the authoritative 2D sim (called by WorldSync). Reads only
## the creature's public channels: position/velocity/scale, `get_state()`, and the
## `Visual` placeholder's color (the F2-gated tell) + rotation (the Assessing aim).
func sync_from(body: Node2D, delta: float) -> void:
	position = SimSpace.to_world(body.global_position, GROUND_Y)
	var visual: Polygon2D = body.get_node_or_null("Visual") as Polygon2D
	var state: StringName = body.get_state() if body.has_method("get_state") else &"still"

	# Pose targets per emotional state.
	var t_lift: float = 0.0
	var t_stretch: float = 0.0
	var t_flatten: float = 1.0
	var t_splay: float = 0.0
	match state:
		&"assessing":
			t_lift = 0.55
			t_flatten = 0.0
			t_splay = 0.6
		&"committed":
			t_lift = 0.35
			t_stretch = 1.0
			t_flatten = 0.0
			t_splay = 1.0
		&"withdrawn":
			t_lift = 0.15
			t_flatten = 0.5
			t_splay = 0.3

	var rate: float = COMMIT_RATE if state == &"committed" else POSE_RATE
	var k: float = minf(rate * delta, 1.0)
	_lift = lerpf(_lift, t_lift, k)
	_stretch = lerpf(_stretch, t_stretch, k)
	_flatten = lerpf(_flatten, t_flatten, k)
	_splay = lerpf(_splay, t_splay, k)

	# Facing: Assessing tracks the sim's aim (Visual.rotation points at the warrior —
	# "the read points"); Committed faces the lunge; Withdrawn backs away still
	# watching the threat (face AGAINST the retreat velocity); Still holds its yaw.
	var vel: Vector2 = body.velocity if body is CharacterBody2D else Vector2.ZERO
	match state:
		&"assessing":
			if visual != null:
				_face_2d_angle(visual.rotation, delta, TURN_RATE)
		&"committed":
			if vel.length_squared() > 1.0:
				_face_2d_angle(vel.angle(), delta, COMMIT_TURN_RATE)
		&"withdrawn":
			if vel.length_squared() > 1.0:
				_face_2d_angle((-vel).angle(), delta, TURN_RATE)

	# Breathing pulse, Assessing-only (gated smoothly by the lift channel).
	_pulse_t += delta
	var pulse: float = 0.0
	if state == &"assessing":
		pulse = sin(_pulse_t * TAU / PULSE_PERIOD) * PULSE_AMP
	_apply_pose(pulse)

	if visual != null:
		# The tell — creature.gd already gates this color behind the Resonance
		# pulse (hidden grey / revealed tell / white hit-flash), so mirroring it
		# verbatim preserves F2 and the WorldSync pip logic untouched.
		_tell_mat.albedo_color = visual.color
		# Death shrink (body.scale) + amplify punch (visual.scale) ride along,
		# same as the billboard path. Clamped: a zero basis spams errors.
		var s: Vector2 = body.scale * visual.scale
		scale = Vector3(maxf(s.x, 0.01), maxf((s.x + s.y) * 0.5, 0.01), maxf(s.y, 0.01))


# ── Internals ────────────────────────────────────────────────────────────────

func _apply_pose(pulse: float) -> void:
	if _body == null:
		return
	var lift: float = clampf(_lift + pulse, 0.0, 1.2)
	_body.position.y = BODY_REST_Y + LIFT_RISE * lift
	_body.rotation.x = -PITCH_STRETCH * _stretch
	var widen: float = 1.0 + FLAT_WIDEN * _flatten
	_body.scale = Vector3(
		widen,
		1.0 - FLAT_SQUASH * _flatten,
		widen * (1.0 + STRETCH_Z * _stretch)
	)
	for i in _legs.size():
		_legs[i].rotation.z = _leg_sides[i] * (LEG_BASE_ROLL + LEG_SPLAY_ROLL * _splay)


# 2D sim angle (y-down px space) -> world yaw for a +Z-front body: a 2D direction
# theta maps to world (cos t, 0, sin t), and +Z-front forward is (sin yaw, 0, cos yaw),
# so yaw = PI/2 - theta.
func _face_2d_angle(theta: float, delta: float, rate: float) -> void:
	rotation.y = lerp_angle(rotation.y, PI / 2.0 - theta, minf(rate * delta, 1.0))


func _box(size: Vector3, pos: Vector3, mat: Material, roll := 0.0, pitch := 0.0, parent: Node = null) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(pitch, 0.0, roll)
	(parent if parent else _body).add_child(mi)
	return mi


# A low faceted cone (6 radial segments) — the angular-boulder read.
func _cone(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = h
	c.radial_segments = 6
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.y = 30.0  # facet edge forward — a corner, not a flat wall
	_body.add_child(mi)
