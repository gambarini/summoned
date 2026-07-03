extends Node3D
class_name PaleWalkerMesh

## A Pale Herd walker as a low-poly cel-shaded 3D mesh (warrior pattern; see
## threshold_mesh.gd for the first creature built this way). Tall at the shoulder,
## narrow, long-legged — an almost-white grazer with rose patterning along the neck
## and flanks, visual organs set wide and high. It orients; it does not look at
## things directly.
##
## The 2D sim (`creature_pale_walker.gd`) stays authoritative — this is pure
## presentation, driven per-frame by WorldSync calling `sync_from(body, delta)`.
##
## Two separate signal channels, by design:
##  - The **Resonance tell** (F2-gated) renders ONLY on the unshaded neck-membrane
##    strip, tinted per-frame from the sim's `Visual.color` — hidden grey until a
##    pulse reveals it, white on a correct hit, no creature.gd changes needed.
##  - The **hum** is diegetic and always visible, carried by the membrane's
##    GEOMETRY: a slow deep breathing pulse while Calm, an irregular flutter while
##    Uneasy, and a hard contraction while Scattered — "the silence is the first
##    tell". Posing (head height, crouch, gallop) is likewise ungated, exactly like
##    the Threshold's lift/stretch.
##
## Front faces local +Z; base sits at local y=0 on the plateau top.

const GROUND_Y := 0.5

# Pale-grazer palette — near-white body, rose patterning (GDD), dark hooves/eyes.
# Kept clear of the signal hues c0a0f0 / c4547a.
const PALE := Color("d9d4cc")
const PALE_DIM := Color("beb8b0")
const ROSE := Color("c79a9f")
const DARK := Color("514c56")

# Proportions (world units) — legs carry a compact body well off the ground.
const SHOULDER_Y := 1.08     # body pivot height — clearly above the warrior's shoulder
const BODY_SIZE := Vector3(0.30, 0.28, 0.78)
const LEG_LEN := 0.98
const NECK_LEN := 0.55

# Pose throws.
const GRAZE_PITCH := 2.2     # neck rotation.x at full graze (head swung to the ground)
const ALERT_PITCH := 0.15    # near-vertical neck at full alert
const RUN_PITCH := 1.25      # neck stretched forward in the scatter sprint
const CROUCH_DROP := 0.16    # body drop when pressed low (Uneasy)
const CROUCH_LEG := 0.85     # leg scale.y at full crouch (legs fold, no floor clip)
const GALLOP_BODY_PITCH := 0.12  # nose-down body pitch at full sprint (rad)

# Legs.
const SWING_AMP := 0.55      # max leg swing (rad)
const SWING_SPEED_REF := 80.0    # sim px/s at which the swing reaches full amplitude
const PHASE_RATE := 0.10     # leg-phase rad per sim px travelled
const PHASE_RATE_MAX := 14.0 # cap so the sprint doesn't strobe

# Smoothing rates (per second). The scatter snap is fast — fragmentation is
# instant; grazing eases like a slow animal deciding nothing is wrong.
const POSE_RATE := 5.0
const SCATTER_RATE := 13.0
const TURN_CALM := 3.0
const TURN_UNEASY := 6.0
const TURN_SCATTER := 11.0

# The hum (membrane geometry animation).
const HUM_CALM_PERIOD := 1.7   # slow, deep, warm
const HUM_CALM_AMP := 0.24
const HUM_FLUTTER_AMP := 0.11  # fast irregular stutter while Uneasy
const MEMBRANE_CONTRACTED := 0.5  # membrane girth at zero hum (Scattered — silence)

var _body: Node3D
var _neck: Node3D
var _head: Node3D
var _membrane: MeshInstance3D
var _tell_mat: StandardMaterial3D
var _legs: Array[Node3D] = []
var _leg_phase_off: Array[float] = []

# Smoothed pose channels.
var _head_pitch: float = 1.0   # current neck rotation.x
var _crouch: float = 0.0
var _run: float = 0.0
var _hum: float = 1.0          # 1 = membrane open/humming, 0 = contracted silence
var _leg_phase: float = 0.0
var _hum_t: float = 0.0


## Build the body under this node, using `rig` for cel materials.
func build(rig: IsoRig) -> void:
	var pale: Material = rig.solid_material(PALE)
	var pale_dim: Material = rig.solid_material(PALE_DIM)
	var rose: Material = rig.solid_material(ROSE)
	var dark: Material = rig.solid_material(DARK)
	_tell_mat = StandardMaterial3D.new()
	_tell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tell_mat.albedo_color = Color(0.533, 0.596, 0.659)  # creature.gd HIDDEN_COLOR until synced

	_body = Node3D.new()
	_body.position = Vector3(0.0, SHOULDER_Y, 0.0)
	add_child(_body)

	# Torso — compact, pressed low, longer than it is wide.
	_box(BODY_SIZE, Vector3.ZERO, pale)
	# Rose patterning along the flanks (diegetic colour, NOT the tell channel).
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.02, 0.14, 0.50), Vector3(side * 0.155, 0.01, -0.04), rose)
	# Rump wedge + tail stub.
	_box(Vector3(0.24, 0.20, 0.16), Vector3(0.0, 0.05, -0.44), pale_dim)
	_box(Vector3(0.07, 0.16, 0.07), Vector3(0.0, -0.02, -0.53), rose, 0.0, 18.0)

	# Neck pivot at the front shoulder; everything head-ward hangs off it so one
	# rotation.x channel swings graze <-> alert <-> stretched-run.
	_neck = Node3D.new()
	_neck.position = Vector3(0.0, 0.10, 0.34)
	_body.add_child(_neck)
	_box(Vector3(0.11, NECK_LEN, 0.11), Vector3(0.0, NECK_LEN * 0.5, 0.0), pale, 0.0, 0.0, _neck)
	# Rose patterning up the neck sides.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.015, 0.40, 0.08), Vector3(side * 0.058, NECK_LEN * 0.45, 0.0), rose, 0.0, 0.0, _neck)

	# The resonant organ: a thin iridescent membrane along the underside (throat
	# side, local +Z) of the neck. The ONLY surface carrying the Resonance tell.
	_membrane = _box(Vector3(0.05, 0.38, 0.045), Vector3(0.0, NECK_LEN * 0.42, 0.075), _tell_mat, 0.0, 0.0, _neck)

	# Head at the top of the neck — small, counter-pitched so the face stays
	# roughly level as the neck swings.
	_head = Node3D.new()
	_head.position = Vector3(0.0, NECK_LEN, 0.0)
	_neck.add_child(_head)
	_box(Vector3(0.16, 0.14, 0.28), Vector3(0.0, 0.04, 0.06), pale, 0.0, 0.0, _head)
	_box(Vector3(0.10, 0.08, 0.12), Vector3(0.0, 0.0, 0.22), pale_dim, 0.0, 0.0, _head)  # muzzle
	# Visual organs set WIDE and HIGH — near-total periphery, no forward focus.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.035, 0.05, 0.07), Vector3(side * 0.085, 0.10, 0.05), dark, 0.0, 0.0, _head)

	# Four long thin legs; diagonal pairs share a swing phase.
	for side: float in [-1.0, 1.0]:
		for z: float in [0.30, -0.30]:
			var hip: Node3D = Node3D.new()
			hip.position = Vector3(side * 0.11, -BODY_SIZE.y * 0.5 + 0.02, z)
			_body.add_child(hip)
			_box(Vector3(0.065, LEG_LEN, 0.065), Vector3(0.0, -LEG_LEN * 0.5, 0.0), pale_dim, 0.0, 0.0, hip)
			_box(Vector3(0.07, 0.08, 0.075), Vector3(0.0, -LEG_LEN + 0.03, 0.01), dark, 0.0, 0.0, hip)  # hoof
			_legs.append(hip)
			_leg_phase_off.append(0.0 if (side > 0.0) == (z > 0.0) else PI)

	_apply_pose()


## Per-frame drive from the authoritative 2D sim (called by WorldSync). Reads only
## public channels: position/velocity/scale, `get_state()`, and the `Visual`
## placeholder's color (the F2-gated tell).
func sync_from(body: Node2D, delta: float) -> void:
	position = SimSpace.to_world(body.global_position, GROUND_Y)
	var visual: Polygon2D = body.get_node_or_null("Visual") as Polygon2D
	var state: StringName = body.get_state() if body.has_method("get_state") else &"calm"
	var vel: Vector2 = body.velocity if body is CharacterBody2D else Vector2.ZERO
	var speed: float = vel.length()

	# Pose targets per emotional state.
	var t_pitch: float = GRAZE_PITCH
	var t_crouch: float = 0.0
	var t_run: float = 0.0
	var t_hum: float = 1.0
	match state:
		&"uneasy":
			t_pitch = ALERT_PITCH   # head snaps up, watching
			t_crouch = 1.0          # body pressed low against the wind
		&"scattered":
			t_pitch = RUN_PITCH     # neck stretched into the sprint line
			t_run = 1.0
			t_hum = 0.0             # the hum STOPS — membrane contracts

	var rate: float = SCATTER_RATE if state == &"scattered" else POSE_RATE
	var k: float = minf(rate * delta, 1.0)
	_head_pitch = lerpf(_head_pitch, t_pitch, k)
	_crouch = lerpf(_crouch, t_crouch, k)
	_run = lerpf(_run, t_run, k)
	_hum = lerpf(_hum, t_hum, k)

	# Legs swing with actual sim travel; amplitude follows speed so grazing steps
	# read slow and the scatter sprint reads as a burst.
	_leg_phase += minf(speed * PHASE_RATE, PHASE_RATE_MAX) * delta
	var swing: float = clampf(speed / SWING_SPEED_REF, 0.0, 1.0) * SWING_AMP

	# Facing follows the sim velocity; a calm walker turns like it has all day.
	if speed > 4.0:
		var turn: float = TURN_CALM
		match state:
			&"uneasy": turn = TURN_UNEASY
			&"scattered": turn = TURN_SCATTER
		rotation.y = lerp_angle(rotation.y, PI / 2.0 - vel.angle(), minf(turn * delta, 1.0))

	_hum_t += delta
	_apply_pose()
	for i in _legs.size():
		_legs[i].rotation.x = sin(_leg_phase + _leg_phase_off[i]) * swing
		_legs[i].scale.y = 1.0 - (1.0 - CROUCH_LEG) * _crouch

	if visual != null:
		# The Resonance tell — creature.gd already gates this colour behind the
		# pulse (hidden grey / revealed tell / white hit-flash); mirror verbatim.
		_tell_mat.albedo_color = visual.color
		# Death shrink (body.scale) + amplify punch (visual.scale) ride along.
		var s: Vector2 = body.scale * visual.scale
		scale = Vector3(maxf(s.x, 0.01), maxf((s.x + s.y) * 0.5, 0.01), maxf(s.y, 0.01))


# ── Internals ────────────────────────────────────────────────────────────────

func _apply_pose() -> void:
	if _body == null:
		return
	# Body: crouch drop + a light gallop bounce, nose-down pitch at full sprint.
	var bounce: float = sin(_leg_phase * 2.0) * 0.04 * _run
	_body.position.y = SHOULDER_Y - CROUCH_DROP * _crouch + bounce
	_body.rotation.x = GALLOP_BODY_PITCH * _run
	_neck.rotation.x = _head_pitch
	_head.rotation.x = -_head_pitch * 0.7  # face stays roughly level

	# The hum: Calm = slow deep pulse, Uneasy = irregular flutter, Scattered =
	# contracted silence. Geometry only — the tell colour stays F2-gated.
	var pulse: float = 0.0
	if _hum > 0.05:
		var calm_w: float = 1.0 - _crouch
		pulse += sin(_hum_t * TAU / HUM_CALM_PERIOD) * HUM_CALM_AMP * calm_w
		pulse += sin(_hum_t * 11.0) * sin(_hum_t * 4.3) * HUM_FLUTTER_AMP * _crouch
	var girth: float = lerpf(MEMBRANE_CONTRACTED, 1.0 + pulse, _hum)
	_membrane.scale = Vector3(girth, 1.0, girth)


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
