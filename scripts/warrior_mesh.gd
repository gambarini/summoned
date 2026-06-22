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
const ARM_RAISE := 2.5       # sword from resting point-down to a forward strike (big reach)
const SWING_YAW := 2.0       # horizontal slash sweep amplitude (rad) for the combo swings (wide)
# Whole-body strike (the kinetic chain: hips/shoulders drive, the arm only leads). The
# torso pivot coils on the windup (t<0) and whips through on the strike (t>0); legs brace.
const TORSO_TWIST := 0.75    # rad (~43°) hip->shoulder rotation through a slash (wide whip)
const TORSO_LEAN := 0.28     # rad (~16°) forward torso commit on the strike
const STANCE := 1.5          # fore/aft leg brace as a fraction of LEG_SWING (deep lunge)
const STANCE_WIDEN := 0.42   # rad (~24°) lateral foot splay — a wide planted power stance
const BODY_SINK := 0.16      # how far the body drops into the cut (local units)

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
var _torso: Node3D     # upper-body pivot — the whole torso twists/leans into a strike
var _arm: Node3D       # sword shoulder pivot (child of _torso)
var _sword_tip: Node3D # blade-tip socket (WarriorSync anchors the slash arc here)
var _cape: Node3D
var _cape_l: MeshInstance3D
var _cape_r: MeshInstance3D


## Build the body under this node, using `rig` for cel materials. `hem_tint` is the
## per-ring warm (or cold, on Still Heart) the burning hem snaps to — see WarriorSync.
func build(rig: IsoRig, hem_tint := EMBER_COL) -> void:
	_rig = rig
	var armor := rig.solid_material(ARMOR_DARK)
	var lit := rig.solid_material(ARMOR_MID)
	var coat := rig.solid_material(SURCOAT)
	var blade := rig.solid_material(BLADE_COL)
	var hem := _unshaded(hem_tint)

	# Legs on hip pivots (walk + attack stance). Lit plate (greaves) so the stance reads
	# against the dark body; the surcoat below is shortened so the legs actually show.
	_leg_l = _pivot(Vector3(-0.16, 0.95, 0.04))
	_box(Vector3(0.22, 0.95, 0.26), Vector3(0.0, -0.48, 0.0), lit, 0.0, 0.0, _leg_l)
	_leg_r = _pivot(Vector3(0.16, 0.95, 0.04))
	_box(Vector3(0.22, 0.95, 0.26), Vector3(0.0, -0.48, 0.0), lit, 0.0, 0.0, _leg_r)

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
	_arm = _pivot(Vector3(0.40, 1.55, 0.12), _torso)
	_box(Vector3(0.14, 1.62, 0.06), Vector3(0.0, -0.92, 0.0), blade, 0.0, 0.0, _arm)   # blade (longer + wider so it reads clearly)
	_box(Vector3(0.32, 0.08, 0.10), Vector3(0.0, -0.05, 0.0), lit, 0.0, 0.0, _arm)     # crossguard
	_box(Vector3(0.07, 0.13, 0.07), Vector3(0.0, 0.05, 0.0), armor, 0.0, 0.0, _arm)    # pommel
	_box(Vector3(0.16, 0.22, 0.18), Vector3(-0.02, -0.11, 0.0), armor, 0.0, 0.0, _arm) # gauntlet
	# Blade-tip socket: the far end of the 1.30-tall blade (centre y -0.77, so tip at
	# -1.42). The slash arc spawns here in WarriorSync, riding the swing as the arm turns.
	_sword_tip = Node3D.new()
	_sword_tip.position = Vector3(0.0, -1.73, 0.0)
	_arm.add_child(_sword_tip)


# --- Procedural pose API (driven by WarriorSync) -----------------------------

## Walk cycle: opposite-phase leg swings, scaled by `amount` (0 idle .. 1 moving).
func set_walk(phase: float, amount: float) -> void:
	var s := sin(phase) * LEG_SWING * amount
	if _leg_l: _leg_l.rotation.x = s
	if _leg_r: _leg_r.rotation.x = -s


## Attack swing: `t` 0 (rest) .. 1 (full forward strike). Negative = windup back. `step`
## picks the swing: 0 slash, 1 reverse slash, 2 thrust. The cut is a kinetic chain — the
## torso (hips->shoulders) coils on the windup and whips through on the strike, the body
## leans and sinks into it, the legs brace, and the arm only LEADS on top. A slash and its
## reverse whip the body opposite ways (reusing momentum); the thrust drives straight in.
func set_attack(t: float, step := 0) -> void:
	if _torso == null:
		return
	var ts := clampf(t, 0.0, 1.0)   # strike portion only (drop the small negative windup dip)
	match step:
		1:  # reverse slash — body whips the opposite way to the basic slash
			_torso.rotation.y = -TORSO_TWIST * t
			_torso.rotation.x = TORSO_LEAN * t
			_torso.position.y = -BODY_SINK * ts
			_arm.rotation.x = -t * ARM_RAISE * 0.95
			_arm.rotation.y = -SWING_YAW * t
			_arm.rotation.z = 0.0
			_apply_stance(-ts)
		2:  # thrust finisher — hips square, drive straight in: deep lean + sink, no twist
			_torso.rotation.y = 0.0
			_torso.rotation.x = TORSO_LEAN * 1.6 * t
			_torso.position.y = -BODY_SINK * 1.5 * ts
			_arm.rotation.x = -t * ARM_RAISE * 1.1
			_arm.rotation.y = 0.0
			_arm.rotation.z = t * 0.18
			_apply_stance(ts)
		_:  # slash — torso whips through, the blade leads the cut across the body
			_torso.rotation.y = TORSO_TWIST * t
			_torso.rotation.x = TORSO_LEAN * t
			_torso.position.y = -BODY_SINK * ts
			_arm.rotation.x = -t * ARM_RAISE * 0.95
			_arm.rotation.y = SWING_YAW * t
			_arm.rotation.z = 0.0
			_apply_stance(ts)

# Brace the legs into the strike (one forward, one back — a planted lunge stance), ADDED on
# top of the walk pose set_walk() already wrote this frame, so it composes without fighting it.
func _apply_stance(amount: float) -> void:
	# Fore/aft lunge (signed — alternates the lead foot per swing).
	if _leg_l: _leg_l.rotation.x += LEG_SWING * STANCE * amount
	if _leg_r: _leg_r.rotation.x -= LEG_SWING * STANCE * amount
	# Lateral foot splay (unsigned) — a wide planted power stance that reads clearly from the
	# iso camera even with the surcoat. This is the big "reads harder" win for the legs.
	var widen := STANCE_WIDEN * absf(amount)
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
