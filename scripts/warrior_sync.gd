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
# the mouse aim). Only the warrior-specific heights stay here.
const FEET_Y := 0.5                         # the mesh's feet sit on the plateau top
# HOVER_Y is the warrior's visual *centre* — no longer a billboard position, but
# still the anchor `aim_dir_from_screen` unprojects to find him on screen.
const HOVER_Y := 2.0
const MOVE_EPSILON := 8.0                   # px/s; below this, keep last facing
# Vertical hover bob (ports the warrior's 2D HOVER_SPEED 0.8 / HOVER_PIXELS 1.5;
# amplitude in world units, a touch over the literal px*pixel_size for iso punch).
const BOB_SPEED := 0.8
const BOB_AMPLITUDE := 0.1

# --- Notation drift (warrior's "cloak dissolves into notation" identity) --
# Port of the warrior's 2D GPUParticles2D to 3D: same ParticleProcessMaterial
# shape, with px values rescaled to world units (÷PPU). World-space (local=false)
# so the emitter leaves a debris trail as the warrior moves.
const NOTATION_SHEET := preload("res://assets/sprites/notation_glyphs.png")
const WarriorScript := preload("res://scripts/warrior.gd")
const NOTATION_Y := FEET_Y + WarriorMesh.CHEST_Y   # chest socket, world height
const _PX := 1.0 / SimSpace.PIXELS_PER_UNIT

# --- The Hollow (chest wound) --------------------------------------------
# 3D port of warrior.gd's Hollow: a dark void recess + an additive ember core
# sunk inside it (the dark gap sells the depth) + an inward notation pull. Scale
# with the warrior's live `hollow_stress` (a public @export — no warrior change).
# Visibility is gated on the *displayed* billboard facing (`_facing`), not the
# warrior's sim facing: the wound is painted on the sprite, so it must follow the
# sheet that's actually shown — which also makes it appear/vanish correctly as the
# camera orbits. Param arrays re-authored from warrior.gd's `_HOLLOW_*`.
# The Hollow is pinned to the mesh's chest socket (WarriorMesh.get_chest()), so it sits on
# the breastplate and rides the torso's twist/lean and the death collapse.
const HOLLOW_DISC_PX := 32         # gradient disc resolution, like the 2D sprite
const HOLLOW_VOID_SCALE := 0.72    # dark recess — kept wider than the ember
const HOLLOW_GLOW_SCALE := 0.34    # burning core — tight point sunk in the void
const HOLLOW_BRIGHTNESS := [1.0, 0.85, 0.65, 0.4]   # ember dims as it opens
const HOLLOW_RADIUS := [1.0, 1.2, 1.5, 1.9]         # both discs widen
const HOLLOW_INWARD := [0.0, 0.25, 0.6, 0.9]        # pull amount_ratio
const HOLLOW_PULSE_PERIOD := 1.8   # ember breathing period (s), matches 2D tween
# Visibility per *displayed* facing (front-of-chest wound). WarriorSync's own
# "south"/"north-east" vocabulary; mirrors warrior.gd's `_HOLLOW_DIR_VIS`.
const HOLLOW_DIR_VIS := {
	"south": 1.0, "south-east": 0.6, "south-west": 0.6,
	"east": 0.3, "west": 0.3,
	"north-east": 0.0, "north": 0.0, "north-west": 0.0,
}

# Fixed raw input for programmatic/headless drive (capture harness). The
# `Vector2.INF` sentinel means "read live Input" (the normal play path).
var raw_input_override := Vector2.INF

# Per-ring warm the Hollow ember + hem snap to (the world recolors his fire):
# amber by default, the ring's own warm on 2/3/4, cold pale-white on Still Heart.
const EMBER_TINT_DEFAULT := Color("d4803a")
var _ember_tint := EMBER_TINT_DEFAULT

var _rig: IsoRig
var _warrior: CharacterBody2D
var _mesh: WarriorMesh
# Sim-space direction the mesh is facing (persisted; updated from velocity while
# moving, held when idle). The mesh rotates to this world-absolute heading; the
# camera-relative `_facing` (for the Hollow gate) is derived from it every frame.
var _face_dir := Vector2(0.0, 1.0)
var _facing := "south"
var _bob_phase := 0.0
var _bob_y := 0.0  # current hover offset; the Hollow node rides this too
# Procedural animation state (drives the mesh's leg/sword/cape pivots).
var _walk_phase := 0.0
var _walk_amt := 0.0
var _gait_n: float = 0.0   # body speed / the warrior's base SPEED (0 .. sprint ratio)
var _atk := 0.0      # strike progress, windup -> landing (0..1)
var _coil := 0.0     # windup progress, swing start -> cocked pose (0..1)
var _stance_k := 1.0 # idle bladed-stance weight (eases out while a swing owns the body)
var _prev_combo_step := 0   # detect a combo step advance to start the next swing
var _hitstop := 0.0   # seconds of swing-freeze remaining after a landed hit (impact feel)
var _relax := 0.0     # guard-return progress (1 = combo-end pose, 0 = idle guard) — Phase C
var _was_attacking := false   # edge-detect the combo end to start the guard return
var _recoil := 0.0   # hurt knockback (0..1), eased
var _dash_lean: float = 0.0   # dash body-lean (0..1), eased
# Form: 1 = whole (idle), 0 = collapsed to nothing. DYING eases it 1->0 (the mesh
# crumples + sinks, the chest wound shrinks with it, the score-debris scatters);
# SUMMONING snaps it to 0 then eases 0->1 (assembles, final pose = idle). The warrior
# always spawns in SUMMONING (warrior.gd), so it starts at 0 and rises on the first run.
var _form := 0.0
var _form_eased := 0.0   # smoothstep(_form) — what the mesh/effects actually use
var _form_sink := 0.0    # world-units the figure drops into the plateau as it collapses
var _prev_vfx := ""
var _prev_state_for_arc := ""   # edge-detect ATTACK_ACTIVE / DASH for their one-shot sfx
var _notation: GPUParticles3D
var _hollow: Node3D
var _hollow_void: MeshInstance3D
var _hollow_void_mat: StandardMaterial3D
var _hollow_ember: MeshInstance3D
var _hollow_ember_mat: StandardMaterial3D
var _hollow_pull: GPUParticles3D
var _hollow_pulse := 0.0
# Placeholder combat audio (combat_sfx.gd, same-session script -> load() + call()).
var _sfx: Node = null


## Current 8-dir sheet name (for verification / debugging).
func get_facing() -> String:
	return _facing


## Assembled fraction 0..1 (for verification): 0 collapsed, 1 whole. Drops on death,
## rises on summon.
func form_amount() -> float:
	return _form


# Coherence (tribe despair) spectrum, read live from the warrior. tier: 0 whole .. 3 raw.
func _coherence_tier() -> int:
	return clampi(_warrior.tribe_coherence_tier, 0, 3)

# Normalised 0 (whole / concept-1) .. 1 (raw / concept-2) for the continuous drives.
func _coherence_raw() -> float:
	return _coherence_tier() / 3.0


## Current notation emission ratio (for verification): rises with rawness.
func notation_ratio() -> float:
	return _notation.amount_ratio if _notation else 0.0


## The mesh's world position (feet) — output of the sim->world transform.
func get_billboard_position() -> Vector3:
	return _mesh.position


## World height of the chest socket, tracking the collapse: the mesh scales the chest
## from local CHEST_Y by its current vertical form-scale and the whole figure sinks, so
## the Hollow and notation emitter stay glued to the falling chest instead of floating at
## the full-height anchor. At idle (scale.y=1, sink=0) this is exactly FEET_Y + CHEST_Y.
func _chest_world_y() -> float:
	return FEET_Y + _bob_y - _form_sink + WarriorMesh.CHEST_Y * _mesh.scale.y


## Whether the Hollow is currently shown (for verification). Tracks the displayed
## billboard facing — false when a back sheet is up (the wound is front-of-chest).
func hollow_shown() -> bool:
	return _hollow != null and _hollow.visible


## Camera-relative attack aim (Phase 3). The 2D cursor no longer maps to the
## world, so convert the screen cursor into a sim-space direction: undo the
## display's letterbox (window px -> render px), find the warrior's position in
## that same viewport space, and feed the on-screen delta to the proven
## `camera_relative_dir()` — for an ortho camera, screen direction maps faithfully
## to ground direction, so no hand-rolled ground raycast is needed. `screen_pos`
## is in root-viewport (window) coordinates.
func aim_dir_from_screen(screen_pos: Vector2) -> Vector2:
	var render_size := Vector2(_rig.render_size)
	var win := get_viewport().get_visible_rect().size
	# Inverse of the display's KEEP_ASPECT_CENTERED letterbox: cursor -> render-space.
	var fit := minf(win.x / render_size.x, win.y / render_size.y)
	var offset := (win - render_size * fit) * 0.5
	var vp_pos := (screen_pos - offset) / fit
	# Locate the warrior in the SAME displayed render-space — the rig undoes the padded
	# viewport (unproject returns padded coords) + the live sub-pixel blit offset, so
	# the aim origin matches the cursor space under the t3 pipeline.
	var warrior_vp := _rig.world_to_render(SimSpace.to_world(_warrior.global_position, HOVER_Y))
	return _rig.camera_relative_dir(vp_pos - warrior_vp)


func setup(rig: IsoRig, warrior: CharacterBody2D, ember_tint := EMBER_TINT_DEFAULT) -> void:
	_rig = rig
	_warrior = warrior
	_ember_tint = ember_tint

	# The warrior is now a low-poly cel-shaded mesh (redesign — see
	# docs/WARRIOR_3D_REDESIGN_STUDY.md), not a billboard. It faces its world-space
	# movement direction (true 3D) and rotates correctly under the orbiting camera.
	_mesh = WarriorMesh.new()
	_mesh.name = "WarriorMesh"
	rig.add_world_child(_mesh)
	_mesh.build(rig, ember_tint)
	# Spawn collapsed: the warrior always starts in SUMMONING, so assemble from nothing.
	# (setup runs _sync_position once before the first _animate; without this he'd flash
	# at full size for that frame.)
	_mesh.set_form(0.0)

	# The mesh is the warrior now: suppress all 2D presentation in one line
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
	_warrior.melee_hit.connect(_on_melee_hit)   # landed-hit hitstop (presentation-only)

	# Placeholder combat audio: procedural synth blips (swing/hit/dash), presentation-
	# side like the hitstop — the sim emits the same signals it always did.
	_sfx = load("res://scripts/combat_sfx.gd").new()
	_sfx.name = "CombatSfx"
	add_child(_sfx)

	_setup_notation()  # the drifting-score-debris identity, as 3D particles
	_setup_strike_vfx()  # the blade trail (the dissonance waves are made per arc)
	_setup_hollow()    # the burning chest wound (gated on facing + stress)
	_sync_position()  # place the mesh before the first frame
	_sync_facing()    # orient + seed the camera-relative facing for the gate


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


# --- Strike read: the dissonance wave + the blade trail ------------------
# The hit is the 2D AttackArc's HitArea: a wedge that spawns just ahead of the warrior and
# TRAVELS forward along the aim (attack_arc.gd). The old 3D slash was a crescent parented
# to the sword tip, so it rode the blade into the follow-through and drew beside or behind
# him while the real wedge flew out in front, undrawn — the player could not see where a
# swing was going to land. Now two layers split the job:
#   * the WAVE mirrors every live player AttackArc — its exact hit polygon, position,
#     rotation and scale, every frame — as a lavender crescent at cut height. What is drawn
#     bright is exactly what can hit; it dims the moment the arc's hit window closes.
#   * the TRAIL is a short ribbon swept by the blade (tip -> mid-blade) through the strike,
#     so the swing's path reads at ~30 px tall where the limb motion alone does not.
# Enemy arcs stay WorldSync's; the warrior flags his own with `skip_world_mirror`.
const SLASH_COLOR := Color(0.627, 0.502, 0.878)   # #a080e0 — the dissonance/notation hue
const WAVE_Y := 0.9          # height above the feet the wave is drawn at (a body-height cut plane)
const WAVE_INNER := 0.35     # band inner edge, as a fraction of the hit radius (a crescent, not a pie)
const WAVE_ALPHA := 0.9
const WAVE_INNER_ALPHA := 0.2    # the band fades toward its inner edge — a slash streak
const WAVE_REVEAL := 0.06    # s the crescent takes to sweep open, in the swing's direction
const WAVE_FADE := 0.08      # s to vanish once the arc's hit window has closed
const TRAIL_LIFE := 0.06     # s a trail sample lives — a smear behind the tip, not a fan
const TRAIL_COLOR := Color("cbd2d3")   # pale steel — the palette's lightest, distinct from the wave
const TRAIL_ALPHA := 0.7

var _waves := {}             # AttackArc (Node2D) -> wave record (see _make_wave)
var _trail: MeshInstance3D
var _trail_pts: Array = []   # [age, tip: Vector3, mid: Vector3], newest last


func _setup_strike_vfx() -> void:
	_trail = MeshInstance3D.new()
	_trail.name = "BladeTrail"
	_trail.material_override = _strike_material(BaseMaterial3D.BLEND_MODE_MIX)
	_rig.add_world_child(_trail)


func _strike_material(blend: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	# Vertex colours are authored as sRGB hex; read as linear they brighten, and the palette
	# snap turned the lavender wave into the ground's own pale grey.
	mat.vertex_color_is_srgb = true
	return mat


# Mirror the warrior's live AttackArcs as waves; free a wave with its arc.
func _sync_waves(delta: float) -> void:
	for arc in _waves.keys():
		if not is_instance_valid(arc):
			_waves[arc]["mi"].queue_free()
			_waves.erase(arc)
	for arc in get_tree().get_nodes_in_group("attack_arcs"):
		if not arc.has_meta("skip_world_mirror"):
			continue
		if not _waves.has(arc):
			_waves[arc] = _make_wave(arc)
		_update_wave(arc, _waves[arc], delta)


func _make_wave(arc: Node2D) -> Dictionary:
	var mi := MeshInstance3D.new()
	# Mix, not additive: on the pale rings an additive lavender saturated to white and
	# snapped to the ground's own pale grey.
	mi.material_override = _strike_material(BaseMaterial3D.BLEND_MODE_MIX)
	_rig.add_world_child(mi)
	# The hit polygon is the outer arc (STEPS+1 points, -half -> +half) then the inner arc
	# reversed; the wave is drawn off its outer arc, so its reach IS the hit reach.
	var shape := arc.get_node("HitArea/HitShape") as CollisionPolygon2D
	var poly := shape.polygon
	var outer := poly.slice(0, floori(poly.size() * 0.5))
	# Reveal direction follows the swing: arc-local +angle is the warrior's off side, so the
	# forehand (step 0: sword side -> off side) opens from the -half end, the backhand from
	# the +half end, and the chop/thrust open from the centre out.
	var step: int = _warrior.vfx_combo_step()
	var mode := 0 if step == 0 else (1 if step == 1 else 2)
	return {"mi": mi, "outer": outer, "mode": mode, "age": 0.0, "closed": -1.0}


func _update_wave(arc: Node2D, w: Dictionary, delta: float) -> void:
	w["age"] += delta
	var area := arc.get_node("HitArea") as Area2D
	if not area.monitoring and w["closed"] < 0.0:
		w["closed"] = w["age"]
	var a := WAVE_ALPHA
	if w["closed"] >= 0.0:
		a *= clampf(1.0 - (w["age"] - w["closed"]) / WAVE_FADE, 0.0, 1.0)
	var mi: MeshInstance3D = w["mi"]
	if a <= 0.0:
		mi.visible = false
		return
	mi.visible = true
	mi.position = SimSpace.to_world(arc.global_position, FEET_Y + WAVE_Y)
	mi.rotation = Vector3(0.0, -arc.global_rotation, 0.0)
	var sc := arc.global_scale
	mi.scale = Vector3(sc.x, 1.0, sc.y)
	mi.mesh = _wave_mesh(w["outer"], w["mode"], clampf(w["age"] / WAVE_REVEAL, 0.0, 1.0), a)


# The crescent band in the arc's local frame (sim px -> world units), revealed up to `r`.
func _wave_mesh(outer: PackedVector2Array, mode: int, r: float, a: float) -> ArrayMesh:
	var n := outer.size() - 1
	var lo := 0
	var hi := n
	match mode:
		0: hi = int(ceil(n * r))                       # opens -half -> +half
		1: lo = n - int(ceil(n * r))                   # opens +half -> -half
		_:
			var half := int(ceil(n * 0.5 * r))         # opens from the centre out
			lo = floori(n * 0.5) - half
			hi = floori(n * 0.5) + half
	lo = clampi(lo, 0, n)
	hi = clampi(hi, 0, n)
	if hi - lo < 1:
		return null
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var edge := Color(SLASH_COLOR, a)
	var inner := Color(SLASH_COLOR, a * WAVE_INNER_ALPHA)
	for i in range(lo, hi + 1):
		var p := outer[i] / SimSpace.PIXELS_PER_UNIT
		verts.append(Vector3(p.x, 0.0, p.y) * WAVE_INNER)
		verts.append(Vector3(p.x, 0.0, p.y))
		cols.append(inner)
		cols.append(edge)
	return _strip_mesh(verts, cols)


# Sample the blade while the strike is live; age out old samples; rebuild the ribbon.
func _update_trail(delta: float, s: String) -> void:
	for p in _trail_pts:
		p[0] += delta
	while not _trail_pts.is_empty() and _trail_pts[0][0] > TRAIL_LIFE:
		_trail_pts.pop_front()
	if s == "ATTACK_ACTIVE" and _hitstop <= 0.0:
		_trail_pts.append([0.0, _mesh.get_sword_tip().global_position,
			_mesh.get_sword_mid().global_position])
	if _trail_pts.size() < 2:
		_trail.mesh = null
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for p in _trail_pts:
		var a: float = TRAIL_ALPHA * (1.0 - p[0] / TRAIL_LIFE)
		verts.append(p[2])
		verts.append(p[1])
		cols.append(Color(TRAIL_COLOR, a * 0.3))
		cols.append(Color(TRAIL_COLOR, a))
	_trail.mesh = _strip_mesh(verts, cols)


# Triangles for a strip of (inner, outer) vertex pairs.
func _strip_mesh(verts: PackedVector3Array, cols: PackedColorArray) -> ArrayMesh:
	var indices := PackedInt32Array()
	for i in range(floori(verts.size() * 0.5) - 1):
		var b := i * 2
		indices.append(b); indices.append(b + 1); indices.append(b + 2)
		indices.append(b + 1); indices.append(b + 3); indices.append(b + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
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


# --- The Hollow (chest wound, 3D port) -----------------------------------

func _setup_hollow() -> void:
	_hollow = Node3D.new()
	_hollow.name = "Hollow"
	_rig.add_world_child(_hollow)

	# Void: dark radial disc, normal blend — carves a recess into the chest.
	_hollow_void = MeshInstance3D.new()
	_hollow_void.name = "HollowVoid"
	_hollow_void_mat = _disc_material(_make_radial_void_tex(), BaseMaterial3D.BLEND_MODE_MIX, 2)
	_hollow_void.mesh = _disc_mesh(_hollow_void_mat)
	_hollow.add_child(_hollow_void)

	# Ember: smaller additive core sunk inside the void (dark gap = depth).
	_hollow_ember = MeshInstance3D.new()
	_hollow_ember.name = "HollowEmber"
	_hollow_ember_mat = _disc_material(_make_radial_glow_tex(), BaseMaterial3D.BLEND_MODE_ADD, 3)
	_hollow_ember.mesh = _disc_mesh(_hollow_ember_mat)
	_hollow.add_child(_hollow_ember)

	# Pull: notation motes drawn inward toward the wound (more under stress). A
	# sphere shell (not the 2D planar ring) so the pull reads from any camera yaw.
	_hollow_pull = GPUParticles3D.new()
	_hollow_pull.name = "HollowPull"
	_hollow_pull.amount = 16
	_hollow_pull.lifetime = 0.85
	_hollow_pull.local_coords = true     # motes belong to the wound, follow it
	_hollow_pull.amount_ratio = 0.0      # set per stress each frame

	var pquad := QuadMesh.new()
	pquad.size = Vector2(0.45, 0.45)
	var pgm := StandardMaterial3D.new()
	pgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pgm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pgm.albedo_texture = NOTATION_SHEET
	pgm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pgm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pgm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pgm.billboard_keep_scale = true
	pgm.particles_anim_h_frames = 4
	pgm.particles_anim_v_frames = 1
	pgm.particles_anim_loop = false
	pgm.no_depth_test = true
	pgm.render_priority = 3
	pquad.material = pgm
	_hollow_pull.draw_pass_1 = pquad

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 22.0 * _PX
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.radial_accel_min = -55.0 * _PX
	pm.radial_accel_max = -35.0 * _PX    # negative = pulled toward the wound
	pm.tangential_accel_min = 8.0 * _PX
	pm.tangential_accel_max = 18.0 * _PX # slight inward spiral
	pm.scale_min = 0.28
	pm.scale_max = 0.42
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.color_ramp = _build_hollow_pull_ramp()
	_hollow_pull.process_material = pm
	_hollow.add_child(_hollow_pull)

	_update_hollow(0.0)


# A camera-facing disc quad sharing one billboard material. `no_depth_test` keeps
# the wound drawn over the body sprite (a billboard at the same chest depth);
# `render_priority` orders void (1) under ember (2).
func _disc_mesh(mat: StandardMaterial3D) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (HOLLOW_DISC_PX * _PX)
	quad.material = mat
	return quad


func _disc_material(tex: Texture2D, blend: int, priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.no_depth_test = true
	mat.render_priority = priority
	return mat


func _update_hollow(delta: float) -> void:
	if _hollow == null:
		return
	# Pinned to the mesh's chest socket (on the breastplate, following the torso's twist,
	# lean and collapse). At the old body-centre anchor the no-depth-test disc drew over his
	# flank in profile, so a side-on warrior read as facing the camera.
	_hollow.position = _mesh.get_chest().global_position
	var s := clampi(_warrior.hollow_stress, 0, 3)
	var f: float = HOLLOW_DIR_VIS.get(_facing, 1.0)
	# The wound shrinks with the body as he collapses and is gone once he's a flat heap.
	var shown := f > 0.0 and _form_eased > 0.04
	_hollow.visible = shown
	if shown:
		# Form-scale glues the wound to the collapsing body; coherence widens it (the
		# Hollow gapes at low coherence — concept-2) on top of the momentary stress.
		var fs := _form_eased * (1.0 + HOLLOW_COHERENCE_GAIN * _coherence_raw())
		_hollow_void.scale = Vector3.ONE * (HOLLOW_VOID_SCALE * HOLLOW_RADIUS[s] * fs)
		_hollow_ember.scale = Vector3.ONE * (HOLLOW_GLOW_SCALE * HOLLOW_RADIUS[s] * fs)
		# Void alpha = facing factor (fades the recess on side facings, like 2D).
		_hollow_void_mat.albedo_color.a = f
		# Ember = stress brightness * facing * breathing pulse (0.6..1.0).
		_hollow_pulse += delta
		var pulse := 0.8 + 0.2 * sin(_hollow_pulse * (TAU / HOLLOW_PULSE_PERIOD))
		_hollow_ember_mat.albedo_color.a = HOLLOW_BRIGHTNESS[s] * f * pulse
	_hollow_pull.amount_ratio = HOLLOW_INWARD[s]
	_hollow_pull.emitting = shown and HOLLOW_INWARD[s] > 0.0


# Ember core: hot #F0E8D8 center → the per-ring warm (`_ember_tint`) → faint cold
# #7B4EA0 rim. Tight falloff so the bright part stays inside the void, leaving the
# dark recess gap. The tint is chosen per ring to snap cleanly to that ring's palette
# (amber/gold on warm rings; cold pale-white on Still Heart) — no more pink ember.
func _make_radial_glow_tex() -> GradientTexture2D:
	# Tint-dominant: the ember is mostly `_ember_tint` (a palette-present hue), so the
	# additive core snaps to that exact warm/cold on every ring — no white centre to
	# mis-snap to pink on a palette without a pale slot (Ring 2/3/4). A faint pale
	# pinprick at the very centre only (snaps to the ring's lightest where one exists).
	# Pure tint, no white core: a bright near-white centre snaps unpredictably (to pink
	# on palettes without a pale slot, and even over the dark socket on Ring 1's additive
	# blend). The ember is the per-ring tint throughout, brightest at centre by alpha, so
	# every pixel lands on that palette-present warm/cold — never the dissonant pink.
	var t := _ember_tint
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 0.78, 1.0])
	grad.colors = PackedColorArray([
		Color(t.r, t.g, t.b, 1.0),
		Color(t.r, t.g, t.b, 0.7),
		Color(0.483, 0.306, 0.627, 0.12),  # faint cold rim
		Color(0.483, 0.306, 0.627, 0.0),
	])
	return _radial_tex(grad)


# The absence: opaque #0D0A1E core fading to transparent — the hole the ember
# burns inside of. Normal-blended so it deepens the chest to near-black.
func _make_radial_void_tex() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.051, 0.039, 0.118, 1.0),
		Color(0.051, 0.039, 0.118, 0.92),
		Color(0.051, 0.039, 0.118, 0.4),
		Color(0.051, 0.039, 0.118, 0.0),
	])
	return _radial_tex(grad)


func _radial_tex(grad: Gradient) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = HOLLOW_DISC_PX
	tex.height = HOLLOW_DISC_PX
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


# Notation (#A080E0) fades in, then shifts to the wound's heat (#F0E8D8) as it is
# consumed near the centre.
func _build_hollow_pull_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.85, 1.0])
	grad.colors = PackedColorArray([
		Color(0.627, 0.502, 0.878, 0.0),
		Color(0.627, 0.502, 0.878, 0.85),
		Color(0.941, 0.910, 0.847, 0.8),
		Color(0.941, 0.910, 0.847, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


# Camera-relative sim-space move direction from raw input (live or overridden).
func _camera_dir() -> Vector2:
	var raw := raw_input_override
	if raw == Vector2.INF:
		raw = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return _rig.camera_relative_dir(raw)


# Visual sync runs after physics, so it reads the body's post-move state.
func _process(delta: float) -> void:
	_animate(delta)   # updates _walk_phase/_walk_amt/_atk + the leg/sword/cape pivots
	# Hover bob. The walk boost is modest now — the footfall rhythm comes from the mesh's
	# pose_drop() grounding (the body dips as the legs split, rises as they pass), so this
	# slow sine no longer has to fake the step read; it stays the song-being's float.
	if _warrior.vfx_hover_active():
		_bob_phase += BOB_SPEED * (1.0 + _walk_amt) * delta
		_bob_y = sin(_bob_phase) * BOB_AMPLITUDE * (1.0 + _walk_amt * 0.8)
	else:
		_bob_y = 0.0
	_sync_facing(delta)
	_sync_position()
	# World-space emitter follows the warrior; emitted glyphs stay put -> trail. The
	# emitter rides the collapsing chest so the death disperse comes off the figure.
	if _notation:
		_notation.position = SimSpace.to_world(_warrior.global_position, _chest_world_y())
	_update_hollow(delta)


# The strike lunge is now REAL sim motion (warrior.gd's ATTACK_STEP_SPEED) — the mesh
# just tracks the body, so the old visual-only LUNGE_PX offset (which drew the figure
# 12px ahead of its own hitbox) is gone. Hurt recoil remains presentation-only.
const RECOIL_PX := 6.0   # backward jolt on hurt

func _sync_position() -> void:
	# Hurt jolts the figure backward (sim px, presentation-only).
	var push: float = -_recoil * RECOIL_PX
	var sim := _warrior.global_position + _face_dir * push
	# _form_sink drops him into the plateau on death (and lifts him out of it on summon).
	# pose_drop() is the mesh's per-frame grounding — the support-leg lift of the CURRENT
	# pose (idle crouch, walk split, strike lunge alike) — so the planted sole stays on the
	# plateau through every stance instead of only the fixed idle case the old CROUCH_DROP
	# covered. It also gives the walk its true per-step dip (lowest at double support).
	_mesh.position = SimSpace.to_world(sim, FEET_Y + _bob_y - _form_sink - _mesh.pose_drop())


# Procedural animation: walk cycle from velocity, sword swing from the attack states,
# cape sway from both. No skeleton — these rotate the mesh's leg/arm/cape pivots.
# Gait (roadmap 43): cadence tracks the body's speed against the warrior's OWN base SPEED
# (read from the sim — the old copied REF_SPEED 100 went stale the moment the pace knob
# moved), up to the sprint ratio, and the stride opens up with speed so the feet keep up
# with the fast pace instead of skating. The old 9 rad/s cadence clamped at 1.4x left
# the legs visibly behind the body at a run.
const WALK_FREQ := 13.0      # rad/s leg cadence at base SPEED (scales with speed up to the sprint)
const WALK_STRIDE := 1.3     # leg swing x the mesh's LEG_SWING at base SPEED (1.0 = the old walk)
const WALK_BLEND := 10.0     # 1/s gait fade in/out — ~0.1s, keeping pace with the 0.08s accel
# Per-phase swing pacing. STARTUP: an exponential draw into the windup — any finite
# move_toward rate either arrives early and freezes (a dead hold that reads as input lag)
# or reacts sluggishly to the press; the exponential pulls hard on the press frame and keeps
# creeping deeper through the whole 0.16s startup (~90% of the coil by its end). ACTIVE:
# STRIKE_RATE plays the whip in ~0.08s, inside the 0.11s active window — fast but visible,
# shaped by the mesh's _ease_strike curve (fastest at ~62%, where the blade crosses the
# aim). RECOVERY holds the landing (see _animate).
const WINDUP_EASE := 14.0     # 1/s exponential draw into the windup pose
const STRIKE_RATE := 12.0
const CAPE_STRIKE_FLARE := 0.10   # extra cape flare at full strike (was 0.22 — read as a slab)
const HITSTOP_DURATION := 0.07   # seconds the swing freezes at the contact pose on a landed hit
const RELAX_RATE := 6.0      # guard-return settle speed (combo end -> idle guard), ~0.17s
const REF_SPEED := WarriorScript.SPEED   # warrior px/s at full (unsprinted) move
# Dash read: the figure pitches into the dash direction (rotation about the local X,
# post-yaw, pivoting at the feet) so the burst reads as a committed lunge, not fast
# sliding. The lean snaps in hard and settles out softer; the cape flares with it, and
# the notation emitter runs at full ratio for the dash — the world-space emitter turns
# that into a glyph streak along the path (the cloak shredding under the burst).
const DASH_LEAN := 0.42       # rad forward pitch at full lean (~24°)
const DASH_LEAN_IN := 16.0    # lean arrival rate (1/s) — reaches full in ~0.06s
const DASH_LEAN_OUT := 7.0    # settle-back rate (1/s)
const DASH_CAPE_FLARE := 0.30
# Subtle forward commitment while striding: the body pitches a few degrees into the walk
# (same axis as the dash lean; they compose). Standing bolt upright while the legs cycled
# read as a statue sliding on rails. Scales with the gait (floored at GAIT_FLOOR so the
# slow mid-swing drift keeps the old 0.07 lean): ~6° at the run, ~7° at the sprint.
const WALK_LEAN := 0.10
const GAIT_FLOOR := 0.7
# Death/summon form arc. FORM_RATE traverses 0<->1 in ~2.2s so the collapse/assemble
# completes just under the 2.5s Dying/Summoning timers (no pop when the timer fires).
const FORM_RATE := 0.45
const FORM_SINK_DEPTH := 0.6   # how far the heap settles below the feet at full collapse
# Notation disperse on death: while the chest is still up, throw a full cloud of
# score-debris (the song scattering); once he's crumpled past this, stop emitting so the
# world-space glyphs hang and fade where they were, not as a fountain from underground.
const NOTATION_DISPERSE_UNTIL := 0.5  # _form_eased below which death emission cuts off
# Coherence spectrum (whole<->raw, concept-1<->concept-2), driven by the warrior's
# `tribe_coherence_tier` (0 high .. 3 critical). Rawer = denser score-debris + a wider
# Hollow + a more tattered cape (the cape splay lives on the mesh). The 2D build's
# `_NOTATION_TIER_SCALE` is widened here so the density delta reads at iso scale.
const NOTATION_RATIO_BY_TIER := [0.30, 0.45, 0.65, 0.85]
const HOLLOW_COHERENCE_GAIN := 0.30   # Hollow radius x(1 .. 1.30) from whole -> raw

## A melee swing landed a CORRECT hit — freeze the swing briefly so the impact reads as force
## (consumed in _animate). Presentation-only; wired from warrior.gd's `melee_hit` in setup().
## Gated to the strike pose (active/recovery): a hit that arrives after the state moved on
## (the arc's fade frames landing as the NEXT swing winds up) must not freeze the wrong pose.
func _on_melee_hit() -> void:
	# The crunch plays for EVERY landed hit (a stale hit still connected); only the
	# pose-freeze below is gated to the strike pose.
	if _sfx:
		_sfx.call("play_hit")
	var s: String = _warrior.vfx_state()
	if s == "ATTACK_ACTIVE" or s == "ATTACK_RECOVERY":
		_hitstop = HITSTOP_DURATION


func _animate(delta: float) -> void:
	var s: String = _warrior.vfx_state()
	var attacking := s == "ATTACK_STARTUP" or s == "ATTACK_ACTIVE" or s == "ATTACK_RECOVERY"
	var speed := _warrior.velocity.length()
	_gait_n = clampf(speed / REF_SPEED, 0.0, WarriorScript.RUN_MULTIPLIER)
	# No gait while a swing owns the legs: the strike's forward step (real sim velocity) and
	# the steerable drift used to start the walk cycle mid-swing — legs scissoring and the
	# cape streaming as if running under every cut. The swing's braced lunge carries the step.
	if speed > MOVE_EPSILON and not attacking:
		_walk_phase += delta * WALK_FREQ * _gait_n
		_walk_amt = move_toward(_walk_amt, 1.0, delta * WALK_BLEND)
	else:
		_walk_amt = move_toward(_walk_amt, 0.0, delta * WALK_BLEND)
	# Stride opens from the old walk swing (slow mid-swing drift) to WALK_STRIDE at the run.
	_mesh.set_walk(_walk_phase, _walk_amt, lerpf(1.0, WALK_STRIDE, minf(_gait_n, 1.0)))

	var cs: int = _warrior.vfx_combo_step()
	if s == "ATTACK_ACTIVE" and _prev_state_for_arc != "ATTACK_ACTIVE":
		if _sfx:
			_sfx.call("play_swing", cs)
	elif s == "DASH" and _prev_state_for_arc != "DASH":
		if _sfx:
			_sfx.call("play_dash")
	_prev_state_for_arc = s
	# A new swing starts on the attack edge (fresh from idle/move/dash) or when a chained
	# press advances the combo step. The mesh snapshots the pose on screen as the swing's
	# START, so it coils from exactly there — the guard, the previous landing, or a
	# half-finished guard return — and nothing ever pops.
	if attacking and (not _was_attacking or cs != _prev_combo_step):
		_mesh.begin_swing()
		_coil = 0.0
		_atk = 0.0
		_hitstop = 0.0
		_relax = 0.0
	_prev_combo_step = cs
	# Guard return: when a combo ends, ease the figure from its EXACT final pose back to the
	# idle guard instead of snapping.
	if _was_attacking and not attacking:
		_mesh.begin_guard_return()
		_relax = 1.0
	_was_attacking = attacking
	match s:
		"ATTACK_STARTUP":
			# Anticipation: an exponential draw into the windup — a hard reactive pull on the
			# press frame that keeps creeping deeper, so the coil never sits static.
			_coil = lerpf(_coil, 1.0, 1.0 - exp(-WINDUP_EASE * delta))
			_mesh.set_attack(0.0, cs, _coil)
		"ATTACK_ACTIVE", "ATTACK_RECOVERY":
			if _hitstop > 0.0:
				# Hitstop: hold the contact pose for a beat on a landed hit (set by
				# _on_melee_hit) so the strike reads as force meeting resistance.
				_hitstop -= delta
			else:
				# Drive the whip, then HOLD the landing through recovery: a chained swing
				# snapshots that landing as its start, so the combo flows without resets.
				_atk = move_toward(_atk, 1.0, delta * STRIKE_RATE)
			_mesh.set_attack(_atk, cs, _coil)
		_:
			if _relax > 0.0:
				_relax = move_toward(_relax, 0.0, delta * RELAX_RATE)
				_mesh.set_guard_return(_relax)
			else:
				_mesh.set_guard()
	_sync_waves(delta)
	_update_trail(delta, s)

	# Hurt: a snappy backward jolt (applied as a position recoil in _sync_position).
	_recoil = move_toward(_recoil, 1.0 if s == "HURT" else 0.0, delta * 16.0)

	# Dash: pitch the body into the burst (fast in, soft out). This owns the mesh's
	# rotation.x; the yaw in _sync_facing owns rotation.y — they compose (YXZ order,
	# so the pitch is about the post-yaw local X, always along the dash heading).
	var dashing := s == "DASH"
	_dash_lean = move_toward(_dash_lean, 1.0 if dashing else 0.0,
			delta * (DASH_LEAN_IN if dashing else DASH_LEAN_OUT))
	var stride_k: float = maxf(_gait_n, GAIT_FLOOR)
	_mesh.rotation.x = DASH_LEAN * _dash_lean + WALK_LEAN * _walk_amt * stride_k

	# Cape trails when moving (streaming further at the sprint) and flares a little on the
	# strike and hard on the dash burst. The mesh cancels most of the torso lean, so this
	# is the cape's angle off vertical, not off the (possibly deeply leaning) back.
	var strike_k := clampf(_atk, 0.0, 1.0) if attacking else 0.0
	_mesh.set_cape(0.06 + _walk_amt * 0.30 * stride_k + strike_k * CAPE_STRIKE_FLARE \
			+ _dash_lean * DASH_CAPE_FLARE)
	# Coherence tatter (per-frame so a mid-run tier change re-poses the cape, not just
	# at summon) — composes with the sway above (that rotates the parent pivot).
	_mesh.set_coherence(_coherence_raw())

	# The idle bladed-stance turn fades out while a swing (or its guard return) owns the
	# body, so strikes square up to the aim.
	var guard_k := 0.0 if (attacking or _relax > 0.0) else 1.0
	_stance_k = move_toward(_stance_k, guard_k, delta * STANCE_BLEND)

	_animate_form(s, delta)


# Death-collapse / summon-assemble. Entering SUMMONING snaps the form to nothing so it
# rises from zero; DYING eases it to nothing (crumple + sink); every other state holds
# whole. Smoothstepped so death accelerates into the fall and summon settles into idle.
func _animate_form(s: String, delta: float) -> void:
	if s != _prev_vfx:
		if s == "SUMMONING":
			_form = 0.0   # reassemble from nothing (re-summon restarts the arc)
		_prev_vfx = s
	var target := 0.0 if s == "DYING" else 1.0
	_form = move_toward(_form, target, delta * FORM_RATE)
	_form_eased = smoothstep(0.0, 1.0, _form)
	_form_sink = (1.0 - _form_eased) * FORM_SINK_DEPTH
	_mesh.set_form(_form_eased)
	_update_notation_emission(s)


# Notation emission per state: a disperse cloud over the first half of the collapse,
# then cut off; the idle rate otherwise (also restores it when a re-summon follows death).
func _update_notation_emission(s: String) -> void:
	if _notation == null:
		return
	if s == "DYING":
		var dispersing := _form_eased > NOTATION_DISPERSE_UNTIL
		_notation.amount_ratio = 1.0
		_notation.emitting = dispersing
	elif s == "DASH":
		# Full-cloud shed for the dash: world-space particles stay where they were
		# emitted, so this reads as a glyph streak carved along the dash path.
		_notation.amount_ratio = 1.0
		_notation.emitting = true
	else:
		# Density rises with rawness (low coherence = more shredded score).
		_notation.amount_ratio = NOTATION_RATIO_BY_TIER[_coherence_tier()]
		_notation.emitting = true


# Idle bladed-stance yaw: how far the WHOLE body turns while standing. Positive draws the
# sword side back and the off side forward. Kept small (it was 0.5 — with the torso twist
# the chest sat ~47° off the facing and he read as facing the camera, not his heading);
# faded out as he moves or strikes so he squares up to act. The Hollow gate keys off
# `_face_dir`, not this visual yaw.
const STANCE_YAW := 0.2
const STANCE_BLEND := 6.0    # 1/s the stance turn fades in/out around a swing
# How fast (rad-ease/s) the body pivots to face the aim on an attack: ~90% of the turn
# in 0.15s — the whole windup reads as the body coiling onto the cursor. The old 30
# converged in ~2 frames and read as a facing snap, not a turn.
const TURN_RATE := 14.0

# The mesh faces its WORLD-absolute movement heading (true 3D) — EXCEPT while attacking,
# when it turns to the mouse-driven aim so the body, and the swing arc that sweeps across
# it, centre on the cursor rather than the last-move heading. `_facing` (the camera-relative
# 8-dir name driving the Hollow gate) is re-derived from that heading EVERY frame, so
# orbiting the camera while idle correctly hides the front-of-chest wound when his back
# turns to us.
func _sync_facing(delta := 0.0) -> void:
	var v := _warrior.velocity
	if v.length() >= MOVE_EPSILON:
		_face_dir = Vector2(v.x, v.y).normalized()
	# While attacking, turn to the aim (cursor) and hold it through the combo/recovery — the
	# aim is the centre the swing sweeps across, so the body must square to it, not the heading.
	var s: String = _warrior.vfx_state()
	var attacking := s == "ATTACK_STARTUP" or s == "ATTACK_ACTIVE" or s == "ATTACK_RECOVERY"
	if attacking:
		var adir: Vector2 = _warrior.vfx_attack_dir()
		if adir.length() > 0.01:
			_face_dir = adir.normalized()
	# +Z is the mesh's front; rotate it onto (face_dir.x, face_dir.y) in world (x,z), then
	# add the idle bladed-stance turn (full when standing, gone when moving/striking).
	var blade := (1.0 - _walk_amt) * _stance_k
	var target_y := atan2(_face_dir.x, _face_dir.y) + STANCE_YAW * blade
	# Ease the pivot into an attack so the body visibly turns to the cursor; snap otherwise
	# (movement facing stays instant, as before).
	if attacking and delta > 0.0:
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_y, clampf(TURN_RATE * delta, 0.0, 1.0))
	else:
		_mesh.rotation.y = target_y
	var dir_name := _rig.facing_name(_face_dir)
	if dir_name != "":
		_facing = dir_name
