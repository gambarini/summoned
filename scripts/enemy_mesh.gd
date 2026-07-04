extends Node3D
class_name EnemyMesh

## The base ring enemy ("husk") as a low-poly cel-shaded 3D mesh — the enemy
## placeholders' graduation from the flat Polygon2D billboard to the warrior
## pattern (see threshold_mesh.gd, the first graduated creature). A hunched
## grief-echo stalker: settled and ambiguous while idle, leaning hungrily into
## the chase, rearing up with raised claw-arms while it strikes.
##
## The 2D sim (`enemy.gd`) stays authoritative — this node is pure presentation,
## driven per-frame by `WorldSync` calling `sync_from(body, delta)`. The
## frequency read is preserved by construction: the tell renders ONLY on
## unshaded channels (eye band + chest seam) tinted every frame from the sim's
## `Visual.color` — hidden grey until a Resonance reveal, frequency colour on
## reveal, orange when amplified, white on the hit flash, red on the strike —
## so the F2 gate, the WorldSync pip and every combat flash keep working with
## zero sim-logic changes.
##
## Subclasses (fleer/phaser) override `_build_geometry` / `_animate` and tune
## the variant knobs in `_init`; build() and the sync_from contract (position,
## facing, tell mirror, death/stagger scale mirror) are shared.
##
## Front faces local +Z; base sits at local y=0 (the root parks on the plateau).

# Ground plane: the ring plateaus' top face (see WarriorSync.FEET_Y).
const GROUND_Y := 0.5

# Husk palette — desaturated plum-charcoals, deliberately clear of the signal
# hues (pink c4547a / lavender c0a0f0 / amplify orange): the body never carries
# meaning, only the tell channels do.
const HUSK_DARK := Color("2e2937")
const HUSK_MID := Color("4b4356")
const HUSK_PALE := Color("6a6076")

# Smoothing rates (per second).
const POSE_RATE := 8.0
const TURN_RATE := 9.0

# Idle breath — the only life it shows while settled.
const BREATH_PERIOD := 2.6
const BREATH_AMP := 0.008

var _body: Node3D
var _tell_mat: StandardMaterial3D
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []

# Variant knobs (subclasses tune in _init, which runs before build()).
var _rest_y: float = 0.36     # body pivot height at neutral
var _lean_max: float = 0.30   # forward pitch at full chase speed (rad)
var _hunch: float = 0.10      # resting forward pitch (rad)
var _gait_freq: float = 9.0   # limb-swing phase rate at full speed (rad/s)
var _bob_amp: float = 0.035   # gait bob amplitude at full speed
var _ref_speed: float = 80.0  # sim px/s that reads as "full speed" (amplified chase)

# Smoothed pose channels.
var _lean: float = 0.0
var _rear: float = 0.0
var _speed_n: float = 0.0
var _gait_t: float = 0.0
var _breath_t: float = 0.0


## Build the body under this node, using `rig` for cel materials.
func build(rig: IsoRig) -> void:
	_tell_mat = StandardMaterial3D.new()
	_tell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tell_mat.albedo_color = Color(0.533, 0.596, 0.659)  # enemy.gd NEUTRAL_COLOR until synced
	_body = Node3D.new()
	_body.position = Vector3(0.0, _rest_y, 0.0)
	add_child(_body)
	_build_geometry(rig)


## Per-frame drive from the authoritative 2D sim (called by WorldSync). Reads
## only the body's public channels: position/velocity/scale, get_state(), and
## the `Visual` placeholder's color (the gated tell) + scale (stagger/amplify).
func sync_from(body: Node2D, delta: float) -> void:
	position = SimSpace.to_world(body.global_position, GROUND_Y)
	var visual: Polygon2D = body.get_node_or_null("Visual") as Polygon2D
	var state: StringName = body.get_state() if body.has_method("get_state") else &"idle"
	var vel: Vector2 = body.velocity if body is CharacterBody2D else Vector2.ZERO

	var k: float = minf(POSE_RATE * delta, 1.0)
	_speed_n = lerpf(_speed_n, clampf(vel.length() / _ref_speed, 0.0, 1.5), k)
	_lean = lerpf(_lean, _lean_max * minf(_speed_n, 1.0), k)
	_rear = lerpf(_rear, 1.0 if state == &"attack" else 0.0, k)
	_gait_t += delta * _gait_freq * _speed_n
	_breath_t += delta

	if vel.length_squared() > 4.0:
		_face_2d_angle(vel.angle(), delta, TURN_RATE)

	_animate(body, state, delta)

	if visual != null:
		# The tell — enemy.gd already gates this colour (hidden grey / revealed
		# frequency / amplified orange / flashes), so mirroring it verbatim
		# preserves the read rules and the WorldSync pip untouched.
		_tell_mat.albedo_color = visual.color
		# Death shrink (body.scale) + stagger squash / amplify punch
		# (visual.scale) ride along, same as the billboard path. Clamped: a
		# zero basis spams errors.
		var s: Vector2 = body.scale * visual.scale
		scale = Vector3(maxf(s.x, 0.01), maxf(s.y, 0.01), maxf(s.x, 0.01))


# ── Variant hooks ─────────────────────────────────────────────────────────────

# The grunt: hunched torso + cowl + jutting head, hanging claw-arms, stub legs.
func _build_geometry(rig: IsoRig) -> void:
	var dark: Material = rig.solid_material(HUSK_DARK)
	var mid: Material = rig.solid_material(HUSK_MID)
	var pale: Material = rig.solid_material(HUSK_PALE)
	# Torso slab (the resting hunch is applied by _animate on the body pivot).
	var torso: MeshInstance3D = _box(Vector3(0.32, 0.40, 0.24), Vector3(0.0, 0.04, 0.0), dark)
	# Shoulder cowl draped over it.
	_box(Vector3(0.42, 0.13, 0.30), Vector3(0.0, 0.235, -0.03), pale, 10.0)
	# Head — low and jutting forward: it leads with its face.
	_box(Vector3(0.18, 0.16, 0.18), Vector3(0.0, 0.27, 0.17), mid, -6.0)
	# Tell channels: eye band across the face + a cracked-core seam on the
	# chest (child of the torso so it rides every pose).
	_box(Vector3(0.15, 0.045, 0.03), Vector3(0.0, 0.285, 0.265), _tell_mat)
	_box(Vector3(0.055, 0.22, 0.025), Vector3(0.0, 0.02, 0.125), _tell_mat, 0.0, torso)
	# Hanging claw-arms; they rise into the strike.
	for side in [-1.0, 1.0]:
		var shoulder: Node3D = Node3D.new()
		shoulder.position = Vector3(side * 0.235, 0.17, 0.02)
		_body.add_child(shoulder)
		_box(Vector3(0.075, 0.34, 0.10), Vector3(0.0, -0.185, 0.02), mid, 0.0, shoulder)
		_arms.append(shoulder)
	# Stub legs.
	for side in [-1.0, 1.0]:
		var hip: Node3D = Node3D.new()
		hip.position = Vector3(side * 0.10, -0.16, -0.01)
		_body.add_child(hip)
		_box(Vector3(0.085, 0.26, 0.09), Vector3(0.0, -0.13, 0.0), dark, 0.0, hip)
		_legs.append(hip)


# Grunt posing: hunch + chase lean; diagonal gait swing; attack rears the body
# back and raises the claws.
func _animate(_sim_body: Node2D, _state: StringName, _delta: float) -> void:
	if _body == null:
		return
	_body.rotation.x = _hunch + _lean - 0.35 * _rear
	var bob: float = absf(sin(_gait_t)) * _bob_amp * minf(_speed_n, 1.0)
	var breath: float = sin(_breath_t * TAU / BREATH_PERIOD) * BREATH_AMP
	_body.position.y = _rest_y + bob + breath + 0.05 * _rear
	var swing: float = sin(_gait_t) * 0.55 * minf(_speed_n, 1.0)
	for i in _legs.size():
		_legs[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
	for i in _arms.size():
		# Raised claws while striking; counter-phase swing while chasing.
		_arms[i].rotation.x = -1.25 * _rear + swing * (1.0 if i == 1 else -1.0) * 0.6 * (1.0 - _rear)


# ── Shared helpers ────────────────────────────────────────────────────────────

# 2D sim angle (y-down px space) -> world yaw for a +Z-front body (see
# threshold_mesh.gd for the derivation).
func _face_2d_angle(theta: float, delta: float, rate: float) -> void:
	rotation.y = lerp_angle(rotation.y, PI / 2.0 - theta, minf(rate * delta, 1.0))


func _box(size: Vector3, pos: Vector3, mat: Material, pitch := 0.0, parent: Node = null) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(pitch, 0.0, 0.0)
	(parent if parent else _body).add_child(mi)
	return mi
