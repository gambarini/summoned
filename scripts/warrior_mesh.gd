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
const ARM_RAISE := 2.5       # sword from resting point-down to a forward strike (big reach)
const SWING_YAW := 2.0       # horizontal slash sweep amplitude (rad) for the combo swings (wide)
# Whole-body strike (the kinetic chain: hips/shoulders drive, the arm only leads). The
# torso pivot coils on the windup (t<0) and whips through on the strike (t>0); legs brace.
const TORSO_TWIST := 0.75    # rad (~43°) hip->shoulder rotation through a slash (wide whip)
const TORSO_LEAN := 0.28     # rad (~16°) forward torso commit on the strike
const STANCE := 1.5          # fore/aft leg brace as a fraction of LEG_SWING (deep lunge)
const STANCE_WIDEN := 0.42   # rad (~24°) lateral foot splay — a wide planted power stance
const BODY_SINK := 0.16      # how far the body drops into the cut (local units)

# Per-step strike END waypoints — the pose the blade/body LANDS in at the peak (w=1) of
# each swing. Each swing sweeps from the PREVIOUS step's landing (step 0 from the guard,
# step N from STRIKE_ENDS[N-1]), so the blade flows across the body in a continuous combo:
# [0] left->right cut, [1] rise to overhead, [2] overhead chop, [3] a committed lunging
# THRUST that drives the point forward at the target (the finisher). The chain loops (a
# 5th press re-cocks from the guard). Fields:
#   arm_pitch, arm_yaw, arm_roll, torso_twist, torso_lean, sink, stance, widen, arm_extend.
# arm_extend (local +Z, body-forward) is 0 for the cuts — only the thrust drives the grip out.
const THRUST_EXTEND := 0.6   # how far the thrust drives the sword grip forward (local units)
const STRIKE_ENDS := [
	[-1.6, -1.9, 0.0, -0.78,  0.26, BODY_SINK,       -1.0, STANCE_WIDEN,       0.0],  # 0 horizontal slash (lands left)
	[-2.9, -0.4, 0.0,  0.20, -0.06, -0.05,            0.4, STANCE_WIDEN * 0.6, 0.0],  # 1 rises to overhead
	[ 0.20, 0.0, 0.0,  0.0,   TORSO_LEAN * 1.5, BODY_SINK * 1.5, -0.8, STANCE_WIDEN, 0.0],  # 2 overhead chop down
	# 3 — lunging THRUST: blade levelled forward (pitch ~ -1.5 swings the hanging blade to +Z),
	# hips square (no twist — drive straight in), deep forward lean + lunge, the point extends out.
	[-1.5,  0.0, 0.0,  0.0,   TORSO_LEAN * 1.6, BODY_SINK,        1.2, STANCE_WIDEN * 0.5, THRUST_EXTEND],  # 3 thrust finisher
]

# Combat-ready idle guard — the t=0 endpoint of set_attack(). Instead of standing limp
# with the sword hanging point-down, the warrior holds a guard: blade raised toward the
# threat, shoulders bladed, weight forward, feet planted. The tuned strike poses blend
# OUT from this guard (lerp by the strike weight), so at full strike every channel still
# lands on its original value — the attack is untouched, only the rest pose changed.
# A bladed, orthodox fighting stance: body turned side-on (left shoulder + foot lead), the
# sword cocked high-and-back over the right shoulder, gripped TWO-HANDED (both gauntlets on
# the hilt). The WHOLE body turning side-on is done by WarriorSync.STANCE_YAW
# (it yaws the entire mesh so legs + hips + torso blade together); this torso twist only
# adds a small extra shoulder draw on top, kept low so the strike whip keeps its full range.
# IDLE_STANCE is negative so the LEFT foot leads and the right trails.
const IDLE_ARM_PITCH := -2.6   # sword cocked high (tip up/back over the right shoulder)
const IDLE_ARM_YAW := -0.5     # angle the blade back to the right — wound up to strike
const IDLE_TORSO_TWIST := 0.32 # shoulders blade MORE than the hips (chart: upper body turned, chest still toward the enemy)
const IDLE_TORSO_LEAN := 0.10  # slight forward weight — alert, NOT hunched over
const IDLE_STANCE := -0.7      # fore/aft stagger: left foot ahead, right foot driven back
const IDLE_WIDEN := 0.18       # lateral foot splay — a planted, braced stance
const IDLE_KNEE_LEAD := 0.48   # lead (front) knee bent — a contained crouch, not a deep squat
const IDLE_KNEE_REAR := 0.22   # rear knee softer (that leg drives back, nearer straight)

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
var _torso: Node3D     # upper-body pivot — the whole torso twists/leans into a strike
var _arm: Node3D       # sword shoulder pivot (child of _torso)
var _arm_base_pos: Vector3  # _arm's rest position — the thrust drives the grip forward from here
var _relax_from := {}       # captured pose at combo end, for the guard-return settle (Phase C)
var _left_arm: Node3D  # off-hand guard arm (held forward as a blocking hand)
var _sword_tip: Node3D # blade-tip socket (WarriorSync anchors the slash arc here)
var _cape: Node3D
var _cape_l: MeshInstance3D
var _cape_r: MeshInstance3D
var _last_walk_amt: float = 0.0   # cached from set_walk() so set_attack() can relax the idle stance while moving


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
	_box(Vector3(0.24, 0.12, 0.34), Vector3(0.0, -0.46, 0.06), armor, 0.0, 0.0, _knee_l) # foot
	_leg_r = _pivot(Vector3(0.17, 0.95, 0.04))
	_box(Vector3(0.22, 0.52, 0.26), Vector3(0.0, -0.26, 0.0), lit, 0.0, 0.0, _leg_r)
	_knee_r = _pivot(Vector3(0.0, -0.52, 0.0), _leg_r)
	_box(Vector3(0.20, 0.46, 0.22), Vector3(0.0, -0.23, 0.0), lit, 0.0, 0.0, _knee_r)
	_box(Vector3(0.24, 0.12, 0.34), Vector3(0.0, -0.46, 0.06), armor, 0.0, 0.0, _knee_r)

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

	# Off (left) forearm bridging back toward the body from the lower hand. Parented to the
	# sword so it tracks the hilt through every swing (the grip always reads two-handed).
	_left_arm = _pivot(Vector3(-0.04, 0.0, 0.05), _arm)
	_box(Vector3(0.14, 0.52, 0.14), Vector3(0.0, 0.26, 0.0), lit, 0.0, 0.0, _left_arm)  # forearm
	_left_arm.rotation_degrees = Vector3(18.0, 0.0, 78.0)   # swing the forearm out toward the body


# --- Procedural pose API (driven by WarriorSync) -----------------------------

## Walk cycle: opposite-phase leg swings, scaled by `amount` (0 idle .. 1 moving).
func set_walk(phase: float, amount: float) -> void:
	_last_walk_amt = amount
	var s := sin(phase) * LEG_SWING * amount
	if _leg_l: _leg_l.rotation.x = s
	if _leg_r: _leg_r.rotation.x = -s
	# Knees flex through the cycle. Set absolutely here (reset each frame) so the idle/strike
	# crouch bend in set_attack composes on top with += , exactly like the hip stagger does.
	if _knee_l: _knee_l.rotation.x = (0.5 - 0.5 * cos(phase)) * KNEE_WALK * amount
	if _knee_r: _knee_r.rotation.x = (0.5 - 0.5 * cos(phase + PI)) * KNEE_WALK * amount


## Attack swing: `t` 0 (rest / combat guard) .. 1 (full strike). `step` picks the swing —
## 0 left->right, 1 right->top, 2 top->down, 3 back-left — and each swing sweeps from the
## PREVIOUS step's landing pose (step 0 from the guard) to this step's, so a chained combo
## reads as one continuous flourish whipping across the body instead of four resets. The
## cut is a kinetic chain: the torso (hips->shoulders) drives, the body leans/sinks, the
## legs brace, and the arm only LEADS on top. (WarriorSync zeroes the swing param on each
## step change so the new swing starts clean from its windup, completing the prior arc.)
func set_attack(t: float, step := 0) -> void:
	if _torso == null:
		return
	# w 0 = the swing's START pose (idle guard for step 0), 1 = its END (the landing).
	var w := clampf(t, 0.0, 1.0)
	# Weight curve: the pose progress is eased, not linear — a slow coil that whips through its
	# fastest at ~STRIKE_PEAK, crests just past the landing (STRIKE_OVERSHOOT follow-through),
	# then settles back to exactly 1.0. `we` exceeds 1.0 near the crest; the lerps extrapolate
	# past the landing for the overshoot, then snap back. This is what gives the constant-rate
	# swing its weight — a linear lerp reads weightless.
	var we := _ease_strike(w)
	var leg_idle := 1.0 - _last_walk_amt
	# Sweep from the previous swing's landing to this swing's — the heart of the cross-body flow.
	var a := _swing_waypoint(step - 1, leg_idle)   # START (guard for step 0)
	var b := _swing_waypoint(step, leg_idle)        # END (this swing's landing)
	_arm.rotation.x = lerpf(a[0], b[0], we)
	_arm.rotation.y = lerpf(a[1], b[1], we)
	_arm.rotation.z = lerpf(a[2], b[2], we)
	_torso.rotation.y = lerpf(a[3], b[3], we)
	_torso.rotation.x = lerpf(a[4], b[4], we)
	_torso.position.y = lerpf(-a[5], -b[5], we)   # positive sink = body drops into the cut
	# Thrust extension: drive the sword grip forward along body-forward (local +Z). 0 for the
	# cuts, so this is the rest position otherwise; only the finisher thrust drives it out.
	_arm.position = _arm_base_pos + Vector3(0.0, 0.0, lerpf(a[8], b[8], we))
	# Legs: the guard plants a persistent splay (relaxed while walking); the fore/aft lunge
	# is strike-only. Both fold into the single _apply_stance call, sweeping with the swing.
	_apply_stance(lerpf(a[6], b[6], we), lerpf(a[7], b[7], we))
	# Knees bend into the crouch at idle (lead knee deeper); straighten as he moves or strikes.
	# Added on top of the walk flex set_walk() wrote this frame. WarriorSync drops the hips by
	# CROUCH_DROP to keep the soles planted, so this reads as a sink, not floating feet.
	var crouch := leg_idle * (1.0 - w)
	if _knee_l: _knee_l.rotation.x += IDLE_KNEE_LEAD * crouch
	if _knee_r: _knee_r.rotation.x += IDLE_KNEE_REAR * crouch


# One end of a swing as a flat pose array (field order matches STRIKE_ENDS). `step` -1 (or
# out of range) is the combat-ready idle guard — the resting pose between combos AND swing
# 0's windup; its leg stagger/splay relaxes by `leg_idle` so the walk cycle stays clean.
func _swing_waypoint(step: int, leg_idle: float) -> Array:
	if step < 0 or step >= STRIKE_ENDS.size():
		return [IDLE_ARM_PITCH, IDLE_ARM_YAW, 0.0, IDLE_TORSO_TWIST, IDLE_TORSO_LEAN,
			0.0, IDLE_STANCE * leg_idle, IDLE_WIDEN * leg_idle, 0.0]
	return STRIKE_ENDS[step]


# Weight curve for a strike's pose progress. A slow coil that accelerates to its fastest at
# ~STRIKE_PEAK, crests just past the landing (the STRIKE_OVERSHOOT follow-through), then
# decelerates back to exactly 1.0. Returns >1.0 briefly near the crest so the pose lerps
# extrapolate past the landing and snap back — the difference between a weighty cut and a
# weightless constant-velocity sweep. (Recovery holds a partial w, so it eases too.)
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


## Snapshot the EXACT current pose so a combo can settle back to the guard seam-free
## (Phase C). WarriorSync calls this on the attack->idle edge, then drives set_guard_return.
func begin_guard_return() -> void:
	if _torso == null:
		return
	_relax_from = {
		"arm_rot": _arm.rotation, "arm_pos": _arm.position,
		"torso_rot": _torso.rotation, "torso_y": _torso.position.y,
		"leg_l": _leg_l.rotation, "leg_r": _leg_r.rotation,
		"knee_l": _knee_l.rotation.x, "knee_r": _knee_r.rotation.x,
	}


## Ease the figure from the captured combo-end pose (r=1) back to the idle guard (r=0), so
## the warrior visibly returns to guard between combos instead of snapping. Establishes the
## live guard pose via set_attack(0,0) — which composes over this frame's set_walk — then
## blends every posed channel back toward the snapshot by r. r=0 lands exactly on the guard,
## so it hands off seamlessly to the normal idle set_attack(0,0).
func set_guard_return(r: float) -> void:
	if _torso == null or _relax_from.is_empty():
		return
	set_attack(0.0, 0)   # write the live idle-guard pose to every posed node
	var k := clampf(r, 0.0, 1.0)
	_arm.rotation = _arm.rotation.lerp(_relax_from["arm_rot"], k)
	_arm.position = _arm.position.lerp(_relax_from["arm_pos"], k)
	_torso.rotation = _torso.rotation.lerp(_relax_from["torso_rot"], k)
	_torso.position.y = lerpf(_torso.position.y, _relax_from["torso_y"], k)
	_leg_l.rotation = _leg_l.rotation.lerp(_relax_from["leg_l"], k)
	_leg_r.rotation = _leg_r.rotation.lerp(_relax_from["leg_r"], k)
	_knee_l.rotation.x = lerpf(_knee_l.rotation.x, _relax_from["knee_l"], k)
	_knee_r.rotation.x = lerpf(_knee_r.rotation.x, _relax_from["knee_r"], k)

# Pose the legs: a signed fore/aft lunge (added on top of the walk pose set_walk() wrote
# this frame, so it composes without fighting it) plus an explicit lateral splay. The splay
# is the big "reads harder" win for the legs at iso scale — it carries both the planted idle
# guard and the wide power stance of a strike.
func _apply_stance(stance: float, widen: float) -> void:
	if _leg_l: _leg_l.rotation.x += LEG_SWING * STANCE * stance
	if _leg_r: _leg_r.rotation.x -= LEG_SWING * STANCE * stance
	if _leg_l: _leg_l.rotation.z = -widen
	if _leg_r: _leg_r.rotation.z = widen

## The blade-tip socket (built in build()) — WarriorSync anchors the slash arc to it.
func get_sword_tip() -> Node3D:
	return _sword_tip


## Cape sway: trailing angle in radians (positive flares it back).
func set_cape(angle: float) -> void:
	if _cape: _cape.rotation.x = angle


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
