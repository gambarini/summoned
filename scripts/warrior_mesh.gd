extends Node3D
class_name WarriorMesh

## The Summoned Warrior as a low-poly, cel-shaded 3D mesh — the redesign locked in
## `docs/WARRIOR_3D_REDESIGN_STUDY.md` (armored knight read as a burning song-being).
## Procedurally built from primitives (the codebase convention; see ring*_world.gd),
## cel-shaded via `IsoRig.solid_material()` + the palette snap, so it reads as the same
## hand-pixelled style as the world and rotates correctly with the camera.
##
## Scope: this builds the **body** only — armour, tattered cape, surcoat + burning hem,
## helm/cowl + glowing eyes, sword, and a dark chest socket for the Hollow. The dynamic
## glowing accents (the stress-gated Hollow ember/pull, notation drift, ground pulses)
## stay owned by `WarriorSync`, which floats them at the chest socket / warrior position.
##
## Animation is procedural (no skeleton): the legs, sword-arm, and cape hang off pivot
## nodes that `WarriorSync` rotates each frame (walk cycle, attack swing, cape sway).
##
## Front faces local +Z; feet at local y=0. The caller positions + rotates the root
## (face the movement/aim direction in world — true 3D, not camera-facing).

# Chest socket centre + hem level (local units) — exposed so WarriorSync can anchor the
# dynamic Hollow and per-ring hem tint to the same spots the body reserves.
const CHEST_Y := 2.00
const CHEST_Z := 0.22       # socket front face, local +Z
const HEM_Y := 0.86
const TOTAL_HEIGHT := 2.94   # helm crest top; ~matches the billboard's pixel_size scale

# Animation throws (radians).
const LEG_SWING := 0.5
const KNEE_WALK := 0.55      # knee flex amplitude through the walk cycle (rad)
# Whole-body strike (the kinetic chain: hips/shoulders drive, the arm only leads). The
# torso pivot coils on the windup and whips through on the strike; legs brace.
const WAIST_Y := 1.15        # where the lean folds — the belt line (see _apply_pose's pivot re-seat)
const STANCE := 1.5          # fore/aft leg brace as a fraction of LEG_SWING (deep lunge)
const STANCE_WIDEN := 0.42   # rad (~24°) lateral foot splay — a wide planted power stance
const BODY_SINK := 0.16      # how far the body drops into the cut (local units)

# Grounding (procedural, IK-ish). Rotating the hips fore/aft swings the feet on an arc, so
# a split stance used to leave BOTH soles floating above the plateau (worst in the thrust
# lunge: ~0.3 units of air). Every frame _finalize_feet() measures how far the SUPPORT leg
# (the least-lifted one) has risen and lowers the whole figure by that much (pose_drop,
# subtracted from the root height by WarriorSync) — the planted sole returns to the ground
# while the swing/rear foot keeps its clearance. Ankles counter-rotate so planted feet sit
# flat; a leg trailing behind rolls onto the ball of the foot instead (toe-down heel-off —
# the push-off / lunge-drive read). During walk this doubles as the step rhythm for free:
# the body dips as the legs split and rises as they pass — true double-support bounce.
const THIGH_LEN := 0.52
const SHIN_LEN := 0.52          # knee pivot to sole (shin + foot)
const PLANT_COMP := 0.8         # fraction of the support-leg lift the body drop compensates
const MAX_POSE_DROP := 0.4
const LUNGE_KNEE_FRONT := 0.8   # front knee bend per rad of stance split — the lunging leg loads
const LUNGE_KNEE_REAR := 0.25   # rear knee stays near-straight — the drive leg
const TOE_OFF := 0.35           # trailing-leg toe-down per rad of hip-back angle (heel-off)
const REAR_BLEND := 0.2         # rad of hip-back over which the ankle blends flat -> ball-of-foot
const WALK_TWIST := 0.12        # shoulder counter-rotation against the hips at full walk

# --- Swing keyframes ----------------------------------------------------------
# Every pose is a flat array (the P_* field order below). Heading convention: the blade's
# direction in the ground plane is ~(arm_yaw + torso_twist) off body-forward, positive
# toward the sword side (local +X, where the grip hangs). The combo is authored so the
# blade CROSSES THE AIM (heading 0) at peak swing speed and LANDS front-side — never
# parked behind the body, which is what used to make a cut read as aimed somewhere else.
#
# Each swing is three keys: START (a snapshot of whatever pose the figure is in when the
# swing begins — the guard, or the previous swing's landing), WINDUP (the cocked
# anticipation pose, reached during ATTACK_STARTUP) and END (the landing, reached during
# ATTACK_ACTIVE and held through recovery). Chained swings therefore flow into each other
# with no reset: forehand cut -> backhand cut -> overhead chop -> lunging thrust.
#
# Fields: arm_pitch, arm_yaw, arm_roll, torso_twist, torso_lean, sink, stance, widen,
# arm_extend, load. arm_pitch -PI/2 levels the blade forward (0 hangs it point-down,
# below -PI/2 raises it). arm_extend drives the grip along body-forward. load 0..1 hands
# the legs from the idle crouch (0) to the braced strike lunge (1).
const P_STANCE := 6
const P_WIDEN := 7
const P_LOAD := 9
const THRUST_EXTEND := 0.6   # how far the thrust drives the sword grip forward (local units)
# Thrust lean: the arm rides the leaning torso, so the arm pitch subtracts the same angle
# to keep the point level in WORLD space (driving at the target, not into the ground).
const THRUST_LEAN := 0.22
const SWING_WINDUPS := [
	# 0 forehand: blade cocked out to the sword side, shoulders coiled back.
	[-1.45,  1.15, 0.0,  0.60, -0.02,  0.06,  -0.5, 0.30,          -0.10, 0.35],
	# 1 backhand: the forehand's follow-through winds on further across the body.
	[-1.45, -1.20, 0.0, -0.65,  0.06,  0.08,  -0.6, 0.35,           0.0,  0.35],
	# 2 overhead: blade raised up and back over the head, body rocked back onto the heel.
	[-3.35, -0.30, 0.0,  0.18, -0.14, -0.04,  -0.3, 0.25,          -0.05, 0.25],
	# 3 thrust: point toward the target, grip drawn back, sword shoulder coiled.
	[-1.62, -0.25, 0.0,  0.55, -0.06,  0.04,  -0.45, 0.30,         -0.40, 0.35],
]
const STRIKE_ENDS := [
	# 0 forehand lands across on the off side, in front (heading ~ -1.2).
	[-1.52, -0.70, 0.0, -0.50,  0.14,  BODY_SINK,  -0.9, STANCE_WIDEN,  0.10, 1.0],
	# 1 backhand lands out on the sword side, stepping through (heading ~ +1.3).
	[-1.55,  0.85, 0.0,  0.45,  0.12,  0.12,        0.7, 0.38,          0.10, 1.0],
	# 2 chop: blade driven down the aim line, tip to the ground in front.
	[-1.30, -0.25, 0.0,  0.0,   0.24,  0.22,       -1.0, STANCE_WIDEN,  0.15, 1.0],
	# 3 thrust: hips square, lunge, the point drives out along the aim (finisher).
	[-PI / 2 - THRUST_LEAN, -0.17, 0.0, -0.08, THRUST_LEAN, BODY_SINK, 1.0, STANCE_WIDEN * 0.5, THRUST_EXTEND, 1.0],
]

# Idle guard — squared up to the facing, blade held out in front and angled up, two hands
# on the hilt. At ~30 px tall the blade pointing along the facing is the clearest read of
# where the warrior is turned (the old side-on fencer's stance, sword cocked straight up
# over the shoulder, left the chest ~47° off the facing and read as facing the camera).
# IDLE_STANCE is negative so the off-side foot leads, a short natural stagger.
const IDLE_ARM_PITCH := -2.0   # blade forward and ~24° up — tip at head height, ahead
const IDLE_ARM_YAW := -0.45    # angle the tip in across the centerline
const IDLE_TORSO_TWIST := 0.12 # a touch of blading — off shoulder slightly forward
const IDLE_TORSO_LEAN := 0.06  # slight forward weight — alert, not hunched
const IDLE_ARM_EXTEND := 0.15  # hands carried a little in front of the body
const IDLE_STANCE := -0.35     # fore/aft stagger: off-side foot ahead
const IDLE_WIDEN := 0.14       # lateral foot splay — planted, not straddled
const IDLE_KNEE_LEAD := 0.40   # lead (front) knee bent — a contained crouch
const IDLE_KNEE_REAR := 0.20   # rear knee softer (that leg drives back, nearer straight)

# --- Palette (snaps to the active ring palette in the post pass) -------------
const ARMOR_DARK := Color("241a33")   # deep indigo plate -> dark blue-grey
const ARMOR_MID  := Color("4a4560")   # lit plate / pauldrons -> mid
const SURCOAT    := Color("2e2440")   # cloak / surcoat
const VOID_COL   := Color("0d0a1e")   # the chest socket -> darkest
const EMBER_COL  := Color("c89a5e")   # warm hem (palette-present warm; per-ring tint in WarriorSync)
const EYE_COL    := Color("cbd2d3")   # pale glowing eyes
# Blade: a light cool steel — lightened for visibility, but still a NEUTRAL grey, kept clear
# of the harmonic signal hue c0a0f0 (a near-white blade snaps to it; blockout finding §8.4).
const BLADE_COL  := Color("9aa6ba")

# Cape side-strip rest pose (whole) + how far they splay/droop into a tattered fringe
# at full rawness (coherence spectrum, concept-1 -> concept-2). The base widens (x-shift
# + droop), not just the angle, so the tatter is distinct from the animated sway.
const CAPE_L_BASE := Vector3(-0.31, -1.05, 0.0)
const CAPE_R_BASE := Vector3(0.31, -0.98, -0.01)
const CAPE_L_ROLL := 7.0
const CAPE_R_ROLL := -6.0
const CAPE_SPLAY_DEG := 32.0   # extra outward roll at full raw (fans the fringe)
const CAPE_SPLAY_X := 0.24     # extra outward shift — widens the silhouette base
const CAPE_DROOP_Y := 0.22     # side strips sag lower as he frays

var _rig: IsoRig
var _leg_l: Node3D
var _leg_r: Node3D
var _knee_l: Node3D    # knee pivot (child of the _leg_l hip) — bends for the crouch + walk flex
var _knee_r: Node3D
var _ankle_l: Node3D   # ankle pivot (child of the knee) — keeps planted soles flat / rolls to the ball
var _ankle_r: Node3D
var _torso: Node3D     # upper-body pivot — the whole torso twists/leans into a strike
var _arm: Node3D       # sword shoulder pivot (child of _torso)
var _arm_base_pos: Vector3  # _arm's rest position — the thrust drives the grip forward from here
var _cur_pose: Array = []   # the pose array applied last frame (what the figure is showing now)
var _swing_from: Array = [] # START key of the current swing (snapshot at begin_swing)
var _relax_from: Array = [] # snapshot at combo end, for the guard-return settle
var _left_arm: Node3D  # off-hand guard arm (held forward as a blocking hand)
var _sword_tip: Node3D # blade-tip socket (WarriorSync's blade trail samples it)
var _sword_mid: Node3D # outer-blade socket — the trail's inner edge
var _chest: Node3D     # chest-socket anchor (the Hollow's world position)
var _cape: Node3D
var _cape_l: MeshInstance3D
var _cape_r: MeshInstance3D
var _last_walk_amt: float = 0.0   # cached from set_walk() so set_attack() can relax the idle stance while moving
var _last_walk_phase: float = 0.0 # cached walk phase — drives the shoulder counter-sway in set_attack()
var _pose_drop := 0.0             # support-leg grounding drop (read by WarriorSync via pose_drop())


## Build the body under this node, using `rig` for cel materials. `hem_tint` is the
## per-ring warm (or cold, on Still Heart) the burning hem snaps to — see WarriorSync.
func build(rig: IsoRig, hem_tint := EMBER_COL) -> void:
	_rig = rig
	var armor := rig.solid_material(ARMOR_DARK)
	var lit := rig.solid_material(ARMOR_MID)
	var coat := rig.solid_material(SURCOAT)
	var blade := rig.solid_material(BLADE_COL)
	var hem := _unshaded(hem_tint)

	# Legs: thigh + knee pivot + shin + foot, so the knees can BEND for a proper crouched
	# fighting stance (the guard-chart read). Lit plate greaves; surcoat shortened so they show.
	# Hip pivot at y=0.95; thigh 0.52 -> knee at -0.52; shin 0.46 + a flat foot -> sole ~y=0.
	_leg_l = _pivot(Vector3(-0.17, 0.95, 0.04))                                          # hip
	_box(Vector3(0.22, 0.52, 0.26), Vector3(0.0, -0.26, 0.0), lit, 0.0, 0.0, _leg_l)     # thigh
	_knee_l = _pivot(Vector3(0.0, -0.52, 0.0), _leg_l)                                   # knee
	_box(Vector3(0.20, 0.46, 0.22), Vector3(0.0, -0.23, 0.0), lit, 0.0, 0.0, _knee_l)    # shin
	_ankle_l = _pivot(Vector3(0.0, -0.46, 0.0), _knee_l)                                 # ankle
	_box(Vector3(0.24, 0.12, 0.34), Vector3(0.0, 0.0, 0.06), armor, 0.0, 0.0, _ankle_l)  # foot
	_leg_r = _pivot(Vector3(0.17, 0.95, 0.04))
	_box(Vector3(0.22, 0.52, 0.26), Vector3(0.0, -0.26, 0.0), lit, 0.0, 0.0, _leg_r)
	_knee_r = _pivot(Vector3(0.0, -0.52, 0.0), _leg_r)
	_box(Vector3(0.20, 0.46, 0.22), Vector3(0.0, -0.23, 0.0), lit, 0.0, 0.0, _knee_r)
	_ankle_r = _pivot(Vector3(0.0, -0.46, 0.0), _knee_r)                                 # ankle
	_box(Vector3(0.24, 0.12, 0.34), Vector3(0.0, 0.0, 0.06), armor, 0.0, 0.0, _ankle_r)  # foot

	# Surcoat skirt (shorter, raised so the legs read) + burning hem band at its new base.
	_cyl(0.26, 0.50, 0.85, Vector3(0.0, 1.28, 0.0), coat)
	_cyl(0.46, 0.54, 0.22, Vector3(0.0, HEM_Y, 0.0), hem)

	# Upper body hangs off a torso pivot at the body's base (origin), so an attack rotates the
	# WHOLE upper body — hips/shoulders coil on the windup and whip through on the strike —
	# instead of only the sword arm. Pivot at origin keeps every child's local position
	# unchanged (a Y-twist is pivot-height-independent; the lean tips the torso over the feet).
	_torso = _pivot(Vector3.ZERO)

	# Tattered cape on a back pivot UNDER the torso (twists + whips with the body). The two
	# side strips are captured so set_coherence() can splay/droop them: whole at high
	# coherence, fanned into a ragged fringe as the tribe's despair reforms him rawer.
	_cape = _pivot(Vector3(0.0, 2.0, -0.20), _torso)
	_box(Vector3(0.56, 1.74, 0.05), Vector3(0.0, -0.96, -0.02), coat, 0.0, 8.0, _cape)
	_cape_l = _box(Vector3(0.16, 1.34, 0.04), CAPE_L_BASE, coat, CAPE_L_ROLL, 9.0, _cape)
	_cape_r = _box(Vector3(0.14, 1.50, 0.04), CAPE_R_BASE, coat, CAPE_R_ROLL, 7.0, _cape)

	# Torso / breastplate + chest plate + dark Hollow socket (all under the torso pivot)
	_box(Vector3(0.60, 0.74, 0.40), Vector3(0.0, 1.98, 0.0), armor, 0.0, 0.0, _torso)
	_box(Vector3(0.34, 0.48, 0.10), Vector3(0.0, 2.04, 0.20), lit, 0.0, 0.0, _torso)
	_disc_z(0.30, Vector3(0.0, CHEST_Y, CHEST_Z), _unshaded(VOID_COL), _torso)  # the socket
	# Hollow anchor on the socket's face: rides the torso's twist/lean/sink and the form
	# collapse, so WarriorSync's wound sits ON the chest rather than at the body centre.
	_chest = Node3D.new()
	_chest.position = Vector3(0.0, CHEST_Y, CHEST_Z)
	_torso.add_child(_chest)
	# Pauldrons (angled, prominent)
	_box(Vector3(0.34, 0.30, 0.42), Vector3(-0.44, 2.22, 0.0), lit, -18.0, 0.0, _torso)
	_box(Vector3(0.34, 0.30, 0.42), Vector3(0.44, 2.22, 0.0), lit, 18.0, 0.0, _torso)
	# Neck + helm/cowl with crest, brow, dark face recess + glowing eyes
	_box(Vector3(0.18, 0.14, 0.18), Vector3(0.0, 2.42, 0.0), armor, 0.0, 0.0, _torso)
	_box(Vector3(0.40, 0.46, 0.40), Vector3(0.0, 2.70, 0.0), armor, 0.0, 0.0, _torso)
	_box(Vector3(0.10, 0.16, 0.30), Vector3(0.0, 2.96, -0.02), lit, 0.0, 0.0, _torso)   # crest fin
	_box(Vector3(0.42, 0.07, 0.06), Vector3(0.0, 2.88, 0.18), lit, 0.0, 0.0, _torso)    # brow ridge
	_box(Vector3(0.28, 0.30, 0.06), Vector3(0.0, 2.70, 0.20), _unshaded(VOID_COL), 0.0, 0.0, _torso)  # face recess
	_box(Vector3(0.09, 0.10, 0.04), Vector3(-0.08, 2.72, 0.23), _unshaded(EYE_COL), 0.0, 0.0, _torso)
	_box(Vector3(0.09, 0.10, 0.04), Vector3(0.08, 2.72, 0.23), _unshaded(EYE_COL), 0.0, 0.0, _torso)

	# Sword on a shoulder pivot UNDER the torso, so the torso twist carries the arm + blade.
	# Long two-hand handle: the grip pivot (arm origin) sits between the two hands.
	_arm = _pivot(Vector3(0.40, 1.55, 0.12), _torso)
	_arm_base_pos = _arm.position
	_box(Vector3(0.14, 2.30, 0.06), Vector3(0.0, -1.26, 0.0), blade, 0.0, 0.0, _arm)   # blade (long — top stays at the crossguard, tip extends down)
	_box(Vector3(0.36, 0.08, 0.12), Vector3(0.0, -0.11, 0.0), lit, 0.0, 0.0, _arm)     # crossguard
	_box(Vector3(0.08, 0.11, 0.08), Vector3(0.0, 0.34, 0.0), armor, 0.0, 0.0, _arm)    # pommel
	# TWO-HANDED grip: right hand high on the handle, left (off) hand below it. Both are
	# children of the sword, so the grip stays locked to the hilt through every swing.
	_box(Vector3(0.16, 0.21, 0.18), Vector3(-0.02, 0.17, 0.0), armor, 0.0, 0.0, _arm)  # right hand (upper)
	_box(Vector3(0.16, 0.21, 0.18), Vector3(-0.02, 0.00, 0.0), armor, 0.0, 0.0, _arm)  # left hand (lower)
	# Blade-tip socket: the far end of the blade. The slash arc spawns here in WarriorSync,
	# riding the swing as the arm turns.
	_sword_tip = Node3D.new()
	_sword_tip.position = Vector3(0.0, -2.41, 0.0)
	_arm.add_child(_sword_tip)
	_sword_mid = Node3D.new()
	_sword_mid.position = Vector3(0.0, -1.7, 0.0)   # outer third of the blade
	_arm.add_child(_sword_mid)

	# Off (left) forearm bridging back toward the body from the lower hand. Parented to the
	# sword so it tracks the hilt through every swing (the grip always reads two-handed).
	_left_arm = _pivot(Vector3(-0.04, 0.0, 0.05), _arm)
	_box(Vector3(0.14, 0.52, 0.14), Vector3(0.0, 0.26, 0.0), lit, 0.0, 0.0, _left_arm)  # forearm
	_left_arm.rotation_degrees = Vector3(18.0, 0.0, 78.0)   # swing the forearm out toward the body


# --- Procedural pose API (driven by WarriorSync) -----------------------------

## Walk cycle: opposite-phase leg swings, scaled by `amount` (0 idle .. 1 moving).
## `stride` widens the swing (and the knee flex with it) over the base LEG_SWING walk —
## WarriorSync opens it up at the run so the feet keep up with the fast pace.
func set_walk(phase: float, amount: float, stride := 1.0) -> void:
	_last_walk_amt = amount
	_last_walk_phase = phase
	amount *= stride
	var s := sin(phase) * LEG_SWING * amount
	if _leg_l: _leg_l.rotation.x = s
	if _leg_r: _leg_r.rotation.x = -s
	# Knees flex through the cycle. Set absolutely here (reset each frame) so the idle/strike
	# crouch bend in set_attack composes on top with += , exactly like the hip stagger does.
	if _knee_l: _knee_l.rotation.x = (0.5 - 0.5 * cos(phase)) * KNEE_WALK * amount
	if _knee_r: _knee_r.rotation.x = (0.5 - 0.5 * cos(phase + PI)) * KNEE_WALK * amount


## Idle guard: the resting pose between combos (and every walking frame). Composes over
## this frame's set_walk(): the guard's leg stagger relaxes while moving so the gait stays
## clean.
func set_guard() -> void:
	if _torso == null:
		return
	_apply_pose(_guard_pose())


## Start a new swing from EXACTLY the pose on screen now — the guard for a fresh attack,
## the previous swing's landing for a chained one, or wherever a guard-return settle had
## got to. WarriorSync calls this on every swing start, so no swing ever pops to a
## hard-coded start pose.
func begin_swing() -> void:
	_swing_from = _cur_pose.duplicate() if not _cur_pose.is_empty() else _guard_pose()


## Attack swing `step` (0 forehand, 1 backhand, 2 overhead chop, 3 thrust). `coil` 0..1
## draws the figure from the swing's START (see begin_swing) into its WINDUP during
## ATTACK_STARTUP; `t` 0..1 then drives the strike from wherever the coil got to into the
## END landing, through the _ease_strike weight curve (slow release, fastest at ~62%, a
## small overshoot, settle). The cut is a kinetic chain: the torso twist/lean drives, the
## body sinks, the legs brace and load, and the arm only leads on top.
func set_attack(t: float, step := 0, coil := 0.0) -> void:
	if _torso == null:
		return
	var s := clampi(step, 0, STRIKE_ENDS.size() - 1)
	var from: Array = _swing_from if not _swing_from.is_empty() else _guard_pose()
	var cocked := _lerp_pose(from, SWING_WINDUPS[s], clampf(coil, 0.0, 1.0))
	_apply_pose(_lerp_pose(cocked, STRIKE_ENDS[s], _ease_strike(t)))


func _guard_pose() -> Array:
	var leg_idle := 1.0 - _last_walk_amt
	return [IDLE_ARM_PITCH, IDLE_ARM_YAW, 0.0, IDLE_TORSO_TWIST, IDLE_TORSO_LEAN, 0.0,
		IDLE_STANCE * leg_idle, IDLE_WIDEN * leg_idle, IDLE_ARM_EXTEND, 0.0]


# Per-field lerp of two pose arrays. `k` may exceed 1 (the strike overshoot extrapolates
# past the landing and settles back).
func _lerp_pose(a: Array, b: Array, k: float) -> Array:
	var out := []
	out.resize(a.size())
	for i in a.size():
		out[i] = lerpf(a[i], b[i], k)
	return out


# Write a pose array to the rig. Legs compose ON TOP of this frame's set_walk() (the stance
# adds to the hip swing, the crouch/lunge add to the knee flex), then the grounding pass.
func _apply_pose(p: Array) -> void:
	_cur_pose = p
	var leg_load := clampf(p[P_LOAD], 0.0, 1.0)
	var leg_idle := 1.0 - _last_walk_amt
	_arm.rotation = Vector3(p[0], p[1], p[2])
	# Walking counter-rotation: the shoulders swing against the hips (left leg forward ->
	# right shoulder forward), fading out as a strike takes ownership of the torso.
	_torso.rotation = Vector3(p[4],
		p[3] - sin(_last_walk_phase) * WALK_TWIST * _last_walk_amt * (1.0 - leg_load), 0.0)
	# Re-seat the lean's hinge at the WAIST. The pivot node stays at the origin (so the
	# Y-twist keeps its pivot-height independence), but rotating there would fold a forward
	# lean at the FEET and shear the chest off the planted hips. Offsetting by h - R*h
	# (h = belt point) moves the effective hinge to belt height; `sink` drops on top.
	var waist := Vector3(0.0, WAIST_Y, 0.0)
	_torso.position = waist - _torso.basis * waist + Vector3(0.0, -p[5], 0.0)
	_arm.position = _arm_base_pos + Vector3(0.0, 0.0, p[8])
	_apply_stance(p[P_STANCE], p[P_WIDEN])
	# Load the legs into the split: the leading knee bends over its planted foot, the rear
	# leg stays near-straight as the drive leg — a true lunge instead of two stiff stilts.
	var lunge := absf(p[P_STANCE]) * LEG_SWING * STANCE * leg_load
	if p[P_STANCE] > 0.0:   # sword-side (right) leg leads (positive stance drives the left hip back)
		if _knee_r: _knee_r.rotation.x += lunge * LUNGE_KNEE_FRONT
		if _knee_l: _knee_l.rotation.x += lunge * LUNGE_KNEE_REAR
	elif p[P_STANCE] < 0.0:
		if _knee_l: _knee_l.rotation.x += lunge * LUNGE_KNEE_FRONT
		if _knee_r: _knee_r.rotation.x += lunge * LUNGE_KNEE_REAR
	# Knees bend into the crouch at idle (lead knee deeper); straighten as he moves or loads
	# into a strike. The grounding pass drops the hips so this reads as a sink, not floating.
	var crouch := leg_idle * (1.0 - leg_load)
	if _knee_l: _knee_l.rotation.x += IDLE_KNEE_LEAD * crouch
	if _knee_r: _knee_r.rotation.x += IDLE_KNEE_REAR * crouch
	_finalize_feet()


# Weight curve for a strike's pose progress. A slow release that accelerates to its fastest
# at ~STRIKE_PEAK, crests just past the landing (the STRIKE_OVERSHOOT follow-through), then
# decelerates back to exactly 1.0. Returns >1.0 briefly near the crest so the pose lerps
# extrapolate past the landing and snap back — the difference between a weighty cut and a
# weightless constant-velocity sweep.
const STRIKE_PEAK := 0.62
const STRIKE_OVERSHOOT := 0.12

func _ease_strike(w: float) -> float:
	w = clampf(w, 0.0, 1.0)
	if w <= STRIKE_PEAK:
		var u := w / STRIKE_PEAK                        # 0..1, accelerating rise to the crest
		return (1.0 + STRIKE_OVERSHOOT) * (u * u)
	var v := (w - STRIKE_PEAK) / (1.0 - STRIKE_PEAK)   # 0..1
	var s := v * v * (3.0 - 2.0 * v)                   # smoothstep settle
	return lerpf(1.0 + STRIKE_OVERSHOOT, 1.0, s)


## Snapshot the EXACT current pose so a combo can settle back to the guard seam-free.
## WarriorSync calls this on the attack->idle edge, then drives set_guard_return.
func begin_guard_return() -> void:
	_relax_from = _cur_pose.duplicate()


## Ease the figure from the captured combo-end pose (r=1) back to the idle guard (r=0), so
## the warrior visibly returns to guard between combos instead of snapping. r=0 lands
## exactly on the guard, so it hands off seamlessly to set_guard().
func set_guard_return(r: float) -> void:
	if _torso == null:
		return
	if _relax_from.is_empty():
		set_guard()
		return
	_apply_pose(_lerp_pose(_guard_pose(), _relax_from, smoothstep(0.0, 1.0, r)))

# Pose the legs: a signed fore/aft lunge (added on top of the walk pose set_walk() wrote
# this frame, so it composes without fighting it) plus an explicit lateral splay. The splay
# is the big "reads harder" win for the legs at iso scale — it carries both the planted idle
# guard and the wide power stance of a strike.
func _apply_stance(stance: float, widen: float) -> void:
	if _leg_l: _leg_l.rotation.x += LEG_SWING * STANCE * stance
	if _leg_r: _leg_r.rotation.x -= LEG_SWING * STANCE * stance
	if _leg_l: _leg_l.rotation.z = -widen
	if _leg_r: _leg_r.rotation.z = widen


# Grounding pass — runs after every pose write (set_attack / set_guard_return), reading the
# FINAL hip/knee rotations of the frame. Measures each leg's sole lift, lowers the figure by
# the support (least-lifted) leg's lift so its sole stays planted on the plateau, and poses
# the ankles: planted/forward feet counter-rotate to sit flat, a leg trailing behind rolls
# onto the ball of the foot (toe-down heel-off). Splayed legs counter-roll so soles never
# tilt sideways with the stance widen.
func _finalize_feet() -> void:
	if _ankle_l == null or _ankle_r == null:
		return
	var lift_l := _leg_lift(_leg_l.rotation.x, _knee_l.rotation.x)
	var lift_r := _leg_lift(_leg_r.rotation.x, _knee_r.rotation.x)
	_pose_drop = clampf(minf(lift_l, lift_r) * PLANT_COMP, 0.0, MAX_POSE_DROP)
	_pose_ankle(_ankle_l, _leg_l, _knee_l)
	_pose_ankle(_ankle_r, _leg_r, _knee_r)


# How far a leg's sole has risen off the ground for these hip/knee bends (straight-line
# segment model: thigh to the knee pivot, shin+foot to the sole).
func _leg_lift(hip: float, knee: float) -> float:
	return THIGH_LEN * (1.0 - cos(hip)) + SHIN_LEN * (1.0 - cos(hip + knee))


func _pose_ankle(ankle: Node3D, leg: Node3D, knee: Node3D) -> void:
	var hip := leg.rotation.x
	var flat := -(hip + knee.rotation.x)   # cancel hip+knee -> sole parallel to the ground
	var ball := hip * TOE_OFF              # trailing leg: toe down, heel driven up
	ankle.rotation.x = lerpf(flat, ball, clampf(hip / REAR_BLEND, 0.0, 1.0))
	ankle.rotation.z = -leg.rotation.z     # counter the stance splay — soles stay level


## Vertical grounding drop (local units) for the current pose — how far WarriorSync should
## lower the root so the support foot stays planted. Replaces the old fixed CROUCH_DROP:
## it now covers the idle crouch, the walk split (a true per-step bounce), and the strike
## lunges, all from the same support-leg measurement.
func pose_drop() -> float:
	return _pose_drop

## The blade-tip socket (built in build()) — the outer edge of WarriorSync's blade trail.
func get_sword_tip() -> Node3D:
	return _sword_tip

## The outer-blade socket — the inner edge of the blade trail.
func get_sword_mid() -> Node3D:
	return _sword_mid

## The chest-socket anchor — WarriorSync pins the Hollow to it.
func get_chest() -> Node3D:
	return _chest


# How much of the torso's lean the cape cancels. The cape pivot rides the torso, so a
# forward lean already swings its hem back; stacked with the strike flare, the chop and
# thrust turned it into a horizontal slab (the thrust read as prone). Cancelling most of
# the lean lets it hang with gravity; not all of it, or a deep lean folds it into the legs.
const CAPE_LEAN_CANCEL := 0.7

## Cape sway: trailing angle in radians (positive flares it back), relative to vertical.
## Call after this frame's pose write (it reads the torso lean).
func set_cape(angle: float) -> void:
	if _cape == null:
		return
	var lean := _torso.rotation.x if _torso else 0.0
	_cape.rotation.x = angle - lean * CAPE_LEAN_CANCEL


## Coherence-spectrum tatter: `raw` 0 (whole / concept-1) .. 1 (raw / concept-2). Fans
## the two side cape strips outward and droops them so the silhouette frays as the tribe
## reforms him from deeper despair. Re-poses the strips within the sway pivot, so it
## composes cleanly with set_cape's per-frame sway (which rotates the parent pivot).
func set_coherence(raw: float) -> void:
	raw = clampf(raw, 0.0, 1.0)
	# Roll deltas tilt each strip's BASE outward (negative-z splays the left strip's
	# bottom toward -x, positive-z the right toward +x), reinforcing the x-shift so the
	# silhouette base widens into a fringe rather than the angle merely cancelling it.
	if _cape_l:
		_cape_l.position = CAPE_L_BASE + Vector3(-CAPE_SPLAY_X * raw, -CAPE_DROOP_Y * raw, 0.0)
		_cape_l.rotation_degrees.z = CAPE_L_ROLL - CAPE_SPLAY_DEG * raw
	if _cape_r:
		_cape_r.position = CAPE_R_BASE + Vector3(CAPE_SPLAY_X * raw, -CAPE_DROOP_Y * raw, 0.0)
		_cape_r.rotation_degrees.z = CAPE_R_ROLL + CAPE_SPLAY_DEG * raw


## Assembled fraction: 1 = whole (idle), 0 = collapsed to nothing. Death plays this
## 1->0 (crumple + sink), summon plays it 0->1 (rise + assemble), so the endpoints are
## the idle pose for free. Feet stay planted (children all have local y>=0), so the
## figure deforms toward the ground rather than imploding to a point. The vertical axis
## collapses fully (he crumples flat) while the footprint only shrinks partway, so the
## read survives even where the plateau has no geometry to occlude a sink (blockout §8).
## WarriorSync reads back `scale.y` to keep the Hollow/notation glued to the falling chest.
const FORM_FLAT_SCALE := 0.05   # min vertical scale — a thin heap on the ground
const FORM_MIN_FOOTPRINT := 0.22  # min horizontal scale — a small dark patch, not a dot

func set_form(f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	var sy := lerpf(FORM_FLAT_SCALE, 1.0, f)
	var sxz := lerpf(FORM_MIN_FOOTPRINT, 1.0, f)
	scale = Vector3(sxz, sy, sxz)


# --- Primitive builders ------------------------------------------------------

func _pivot(pos: Vector3, parent: Node = null) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	(parent if parent else self).add_child(n)
	return n


func _box(size: Vector3, pos: Vector3, mat: Material, roll := 0.0, pitch := 0.0, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(pitch, 0.0, roll)
	(parent if parent else self).add_child(mi)
	return mi


func _cyl(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = h
	c.radial_segments = 8  # faceted, reads pixel-chunky
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


# A thin disc facing local +Z (the chest socket) — reads as a hole on the breastplate.
func _disc_z(r: float, pos: Vector3, mat: Material, parent: Node = null) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.04
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = 90.0
	(parent if parent else self).add_child(mi)


# Unshaded bright material (eyes / hem) — pops past the cel banding, still snaps.
func _unshaded(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m
