extends Node2D

## Ring 1 run scene. **Option B (hybrid):** the 2D sim is the source of truth —
## the warrior's `CharacterBody2D`, enemy bodies + `Area2D` hitboxes, the boundary
## `Walls`, and `game_state.gd`'s run loop are unchanged from the 2D build. The
## *presentation* is the low-res 3D iso rig: `Ring1` 3D terrain under an `IsoRig`,
## the warrior as a synced billboard (`WarriorSync`), enemies + attack arcs as
## synced billboards (`WorldSync`). The HUD stays a 2D `CanvasLayer` on top.
##
## Phase 4 of `docs/MIGRATION_3D.md`: this scene owns + injects the shared rig.

const EnemyScene       := preload("res://scenes/enemy.tscn")
const EnemyFleerScene  := preload("res://scenes/enemy_fleer.tscn")
const EnemyPhaserScene := preload("res://scenes/enemy_phaser.tscn")
const EnemyBase        := preload("res://scripts/enemy.gd")
const ThresholdScript  := preload("res://scripts/creature_threshold.gd")  # F1 test creature

const ROT_SPEED := 90.0  # deg/sec free camera orbit (Q/E), pitch stays locked

# Per-ring enemy TYPE MIX (sampled per spawn). At explore-scale the old fixed
# single-screen positions would all clump near SIM_ORIGIN, so spawns are now
# scattered procedurally across the SimSpace box (see _spawn_enemies) in pockets
# the warrior finds while exploring. Each ring keeps its character through the mix
# (Ring 1 grunt-heavy, Ring 5 phaser-heavy) and through its terrain/palette; the
# bounds stay universal. Missing keys fall back to Ring 1.
const SPAWN_MIX := {
	1: [EnemyScene, EnemyScene, EnemyScene, EnemyFleerScene, EnemyPhaserScene],
	2: [EnemyScene, EnemyScene, EnemyFleerScene, EnemyFleerScene, EnemyPhaserScene],
	3: [EnemyScene, EnemyPhaserScene, EnemyPhaserScene, EnemyFleerScene],
	4: [EnemyScene, EnemyPhaserScene, EnemyFleerScene, EnemyFleerScene, EnemyPhaserScene],
	5: [EnemyPhaserScene, EnemyPhaserScene, EnemyFleerScene, EnemyScene],
}

# Enemy pockets scattered across the arena. Counts scale with the play area so the
# bigger box stays a fight rather than an empty walk; each pocket is a small cluster
# the warrior clears as they sweep the ring.
const POCKETS_PER_RING := 7        # cluster count, spread across the box
const PER_POCKET := Vector2i(2, 4) # min..max enemies per cluster
const POCKET_RADIUS := 90.0        # px spread within a cluster
const HOME_SAFE_RADIUS := 260.0    # px around the summon point kept clear of spawns
const SPAWN_MARGIN := 140.0        # px inset from the walls so nothing spawns in a corner

# --- Extraction gate (F3): progression is a place you *reach* ----------------
# One resonant beacon in the ring; standing within GATE_ACTIVATION_RADIUS of it arms
# the `extract` action (warrior.can_extract), so descending a ring means crossing the
# arena to the gate rather than pressing F anywhere. Reach-only + far from the summon
# point (avoidance-first: no must-clear). Rings may override the spot via
# extraction_point(); default is the centre of the far (north) edge. This closes the
# progression loop; it does NOT make combat mandatory — that's C3 (structured gen).
const GATE_MARGIN := 160.0            # px inset from the far wall
const GATE_ACTIVATION_RADIUS := 70.0  # px around the gate that arms extraction
const GATE_PULSE_SPEED := 2.2         # rad/s beacon breathing
const GATE_COLOR := Color(0.627, 0.502, 0.878, 1.0)        # resonance purple, idle
const GATE_COLOR_BRIGHT := Color(0.820, 0.745, 1.0, 1.0)   # brightened while in range

var _rig: IsoRig
var _world: Node3D       # the current ring's terrain builder (RingNWorld)
var _warrior_sync: WarriorSync
var _world_sync: WorldSync

# Counts only what can actually hurt the warrior (clear_tracker.gd asks each spawn's
# is_hostile()), so the clear banner cannot fire while a Threshold is still hunting —
# and clearing a ring never means killing the peaceful Pale Herd.
var _clear: RefCounted = null
var _run_ended := false

var _gate_pos: Vector2
var _gate_root: Node3D
var _gate_pad_mat: StandardMaterial3D
var _gate_shaft_mat: StandardMaterial3D
var _gate_phase: float = 0.0
var _gate_prompt_shown: bool = false

func _ready() -> void:
	# Roll this run's map seed FIRST: the ring world build + enemy spawns both derive
	# from it, so every summon explores a fresh layout (GameState.lock_seed pins it).
	GameState.roll_run_seed()

	# Charge the summoning before anything reads the tribe's state: an exhausted grief
	# reserve pays for the ceremony out of Anthe (an extra clock tick) instead of failing.
	GameState.begin_summon()

	# --- Walls: rebuild the boundary box from the shared SimSpace bounds, so the
	# arena size is the single PLAY_SCALE knob (the .tscn's legacy 480x270 box is
	# replaced at runtime). Symmetric about SIM_ORIGIN, so the warrior start + all
	# spawns stay put and only the extents grow. ---
	_rebuild_walls()

	# --- 3D presentation rig: scene owns it, configures it per ring, mounts ----
	# the selected ring's terrain builder directly. Per-ring palette/environment
	# must be set BEFORE add_child (the rig builds its pipeline lazily on _ready
	# via _ensure_built). Every ring now supplies apply_environment() (Ring 1's is
	# the atmosphere pass: fog ramp + dropped ambient, see ring1_world.gd).
	_rig = load("res://scenes/iso_rig.tscn").instantiate()
	# Higher internal resolution for sharper ground/decal definition (the dusty-rock
	# recipe). Warrior is a 3D mesh (scales cleanly); enemy + notation sprites are the
	# one thing to watch at this res. See memory ground_texture_spike.
	_rig.render_size = Vector2i(480, 270)
	_world = _make_ring_world(GameState.current_ring)
	if _world.has_method("palette"):
		_rig.palette = _world.palette()
	if _world.has_method("apply_environment"):
		_world.apply_environment(_rig)
	add_child(_rig)
	_world.build(_rig)
	_rig.add_world_child(_world)

	# --- Hybrid bindings: 2D bodies drive 3D billboards -----------------------
	_warrior_sync = WarriorSync.new()
	add_child(_warrior_sync)
	# The world recolors the warrior's fire: each ring tints his ember/hem to a
	# palette-present warm (cold pale-white on Still Heart) so it never snaps to pink.
	var ember_tint := WarriorSync.EMBER_TINT_DEFAULT
	if _world.has_method("ember_tint"):
		ember_tint = _world.ember_tint()
	# The tribe reforms him whole or raw from its current grief reserve (GDD §03): this
	# drives the warrior's coherence spectrum (cape tatter / Hollow size / notation
	# density). Set at summon, held all run — re-derived each run as grief shifts.
	$Warrior.tribe_coherence_tier = GameState.coherence_tier()
	_warrior_sync.setup(_rig, $Warrior, ember_tint)
	# setup() places the mesh (its _sync_position), so centre the follow camera on the
	# warrior now — the first rendered frame is already framed, no startup jump.
	_rig.set_follow_target(_warrior_sync.get_billboard_position())

	_world_sync = WorldSync.new()
	add_child(_world_sync)
	_world_sync.setup(_rig)

	# --- Run loop (unchanged from the 2D build) -------------------------------
	$HUD.bind($Warrior)
	$Warrior.warrior_died.connect(_on_warrior_died)
	$Warrior.warrior_extracted.connect(_on_warrior_extracted)
	if GameState.is_last_song():
		$HUD.show_status("LAST SONG", Color("#C4547A"))
	_clear = load("res://scripts/clear_tracker.gd").new()
	_clear.cleared.connect(_on_run_cleared)
	_spawn_enemies()
	_spawn_test_creatures()
	_setup_extraction_gate()


# Replace the boundary walls with a box derived from SimSpace.box_min/max_px(), so
# the playable arena tracks the one PLAY_SCALE knob. Four thick StaticBody2D-child
# rectangles just outside each edge; the warrior's CharacterBody2D collides with them.
func _rebuild_walls() -> void:
	var walls := $Walls as StaticBody2D
	for c in walls.get_children():
		c.queue_free()
	var lo := SimSpace.box_min_px()
	var hi := SimSpace.box_max_px()
	var centre := SimSpace.SIM_ORIGIN
	var w := hi.x - lo.x
	var h := hi.y - lo.y
	var t := 20.0  # wall thickness (px)
	var specs := [
		["Left",   Vector2(lo.x - t * 0.5, centre.y), Vector2(t, h + 2.0 * t)],
		["Right",  Vector2(hi.x + t * 0.5, centre.y), Vector2(t, h + 2.0 * t)],
		["Top",    Vector2(centre.x, lo.y - t * 0.5), Vector2(w + 2.0 * t, t)],
		["Bottom", Vector2(centre.x, hi.y + t * 0.5), Vector2(w + 2.0 * t, t)],
	]
	for s in specs:
		var cs := CollisionShape2D.new()
		cs.name = s[0]
		cs.position = s[1]
		var rect := RectangleShape2D.new()
		rect.size = s[2]
		cs.shape = rect
		walls.add_child(cs)


# Instantiate the terrain builder for a ring (Node3D with build(rig); rings 2+ also
# expose palette()/apply_environment(rig)). Unknown rings fall back to Ring 1.
func _make_ring_world(ring: int) -> Node3D:
	match ring:
		2: return Ring2World.new()
		3: return Ring3World.new()
		4: return Ring4World.new()
		5: return Ring5World.new()
		_: return Ring1World.new()


func _process(delta: float) -> void:
	# Free camera orbit (the iso pitch stays locked inside the rig).
	var spin := 0.0
	if Input.is_action_pressed("orbit_right"):
		spin += 1.0
	if Input.is_action_pressed("orbit_left"):
		spin -= 1.0
	if spin != 0.0:
		_rig.orbit(spin * ROT_SPEED * delta)

	# Path A follow camera: the pivot tracks the warrior each frame, so the world
	# scrolls under a (roughly) centred warrior. This translation is what the rig's
	# texel-snap + sub-pixel offset smooth into crawl-free motion. A 1-frame position
	# lag here is sub-milli-texel at the warrior's speed, so reading last frame's mesh
	# position is fine. Independent movers (enemies/arcs) keep their own sub-texel
	# crawl — the single follow offset only re-centres the warrior (accepted).
	if is_instance_valid(_warrior_sync):
		_rig.set_follow_target(_warrior_sync.get_billboard_position())

	_tick_extraction_gate(delta)


# This scene owns the run's *flow* (the race guard + the scene change); the economy —
# clock tick, grief, ring, tallies, save — lives in GameState.end_run_* so the whole
# cost model reads from one file.
func _end_run() -> void:
	_run_ended = true

func _on_warrior_died() -> void:
	if _run_ended:
		return  # the run already resolved (extract/death race) — count it once
	_end_run()
	GameState.end_run_death()
	get_tree().change_scene_to_file("res://scenes/base.tscn")

func _on_warrior_extracted() -> void:
	if _run_ended:
		return  # the run already resolved (extract/death race) — count it once
	_end_run()
	GameState.end_run_extract()
	get_tree().change_scene_to_file("res://scenes/base.tscn")

# Fired by the tracker when the last hostile dies. The banner says HOSTILES rather than
# AREA because that is all it asserts: the peaceful herd may still be grazing nearby,
# and that is not something the player is asked to fix.
func _on_run_cleared() -> void:
	if _run_ended:
		return
	$HUD.show_status("HOSTILES CLEARED", Color(0.753, 0.627, 0.941, 1))

func _spawn_enemies() -> void:
	var last_song := GameState.is_last_song()
	var mix: Array = SPAWN_MIX.get(GameState.current_ring, SPAWN_MIX[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.ring_seed(1000 + GameState.current_ring)  # per-ring character, per-run layout
	var lo := SimSpace.box_min_px() + Vector2(SPAWN_MARGIN, SPAWN_MARGIN)
	var hi := SimSpace.box_max_px() - Vector2(SPAWN_MARGIN, SPAWN_MARGIN)
	for p in range(POCKETS_PER_RING):
		# A cluster centre somewhere in the inset box, clear of the summon point.
		var centre := Vector2.ZERO
		for _try in range(20):
			centre = Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
			if centre.distance_to(SimSpace.SIM_ORIGIN) >= HOME_SAFE_RADIUS:
				break
		var count := rng.randi_range(PER_POCKET.x, PER_POCKET.y)
		for i in range(count):
			var pos := centre + Vector2(
				rng.randf_range(-POCKET_RADIUS, POCKET_RADIUS),
				rng.randf_range(-POCKET_RADIUS, POCKET_RADIUS)
			).limit_length(POCKET_RADIUS)
			pos = pos.clamp(lo, hi)
			var scene := mix[rng.randi_range(0, mix.size() - 1)] as PackedScene
			var e := scene.instantiate() as EnemyBase
			add_child(e)
			e.global_position = pos
			_clear.register(e)
			if last_song:
				e.force_amplify()


# F1 test harness: drop a few Thresholds into Ring 1 at fixed offsets near the summon
# point so the new Creature state machine (Still→Assessing→Committed→Withdrawn + the
# Resonance intervention window) can be watched directly. Kept OFF the random SPAWN_MIX,
# but ON the clear-count: a Threshold lunges for 2 Coherence, so the ring is not clear
# while one is alive. Remove once Thresholds graduate to real spawning (roadmap 4).
func _spawn_test_creatures() -> void:
	if GameState.current_ring != 1:
		return
	var offsets := [Vector2(0, -150), Vector2(-140, -50), Vector2(150, -40)]
	for i in range(offsets.size()):
		var t := ThresholdScript.new()
		t.name = "Threshold%d" % i
		add_child(t)
		t.global_position = SimSpace.SIM_ORIGIN + offsets[i]
		_clear.register(t)
	_spawn_test_herd()


# R1a test harness: one Pale Herd grazing north-west of the summon point — far enough
# out that the warrior walks INTO its detection web rather than spawning inside it.
# Off SPAWN_MIX like the Thresholds, but unlike them it stays off the clear-count —
# every walker is registered and the tracker turns it away on is_hostile(). The herd
# array is handed to every walker (self included) — it IS the collective: any member's
# detection alerts all of them; regrouping counts mates from it.
func _spawn_test_herd() -> void:
	const HERD_SIZE := 7
	const HERD_HOME := Vector2(-320, -240)  # px from SIM_ORIGIN
	const HERD_SPREAD := 60.0
	var walker_script: GDScript = load("res://scripts/creature_pale_walker.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.ring_seed(3000)
	var herd: Array = []
	for i in range(HERD_SIZE):
		var w: CharacterBody2D = walker_script.new() as CharacterBody2D
		w.name = "PaleWalker%d" % i
		add_child(w)
		w.global_position = SimSpace.SIM_ORIGIN + HERD_HOME + Vector2(
			rng.randf_range(-HERD_SPREAD, HERD_SPREAD),
			rng.randf_range(-HERD_SPREAD, HERD_SPREAD))
		herd.append(w)
		_clear.register(w)  # declined: a grazer is not something you must kill to clear
	for w in herd:
		w.set_herd(herd)


# --- Extraction gate (F3) -----------------------------------------------------
# Place the gate (ring override, else the default far-edge point) and build its 3D
# beacon under the rig. Ring 1's gate is active from spawn (reach-only); the single
# seam for a later disarmed-until-objective ring is the proximity gate in
# _tick_extraction_gate (leave can_extract false until the objective clears).
func _setup_extraction_gate() -> void:
	_gate_pos = _default_gate_pos()
	if _world.has_method("extraction_point"):
		_gate_pos = _world.extraction_point()
	_gate_root = _build_gate_beacon(_gate_pos)
	_rig.add_world_child(_gate_root)


# Default extraction point: centre of the far (north) wall, inset so it never lands
# in a wall or spawn corner. Deterministic for the slice; the structured generator
# (C3) will later place it behind decisions.
func _default_gate_pos() -> Vector2:
	return Vector2(SimSpace.SIM_ORIGIN.x, SimSpace.box_min_px().y + GATE_MARGIN)


# A resonant beacon: a flat ground pad + a rising light shaft, both unshaded so they
# read as light through the cel/palette pipeline. Materials are kept for the pulse.
func _build_gate_beacon(sim_pos: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "ExtractionGate"
	root.position = SimSpace.to_world(sim_pos, 0.5)  # plateau top

	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 2.1
	pad_mesh.bottom_radius = 2.1
	pad_mesh.height = 0.12
	pad.mesh = pad_mesh
	pad.position = Vector3(0.0, 0.07, 0.0)  # a hair above the ground, no z-fight
	_gate_pad_mat = _make_gate_material(GATE_COLOR, 0.7)
	pad.material_override = _gate_pad_mat
	root.add_child(pad)

	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.28
	shaft_mesh.bottom_radius = 0.5
	shaft_mesh.height = 4.5
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 2.25, 0.0)  # base sits on the pad, rises up
	_gate_shaft_mat = _make_gate_material(GATE_COLOR, 0.55)
	shaft.material_override = _gate_shaft_mat
	root.add_child(shaft)
	return root


func _make_gate_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	return mat


# Arm extraction while the warrior stands in the gate; drive the beacon pulse and an
# edge-triggered HUD prompt. Proximity is checked here (not via Area2D) to match the
# codebase's distance-gate idiom (warrior.gd _do_resonance) — no collision config.
func _tick_extraction_gate(delta: float) -> void:
	if _gate_root == null or _run_ended:
		return
	_gate_phase += delta
	var in_range: bool = $Warrior.global_position.distance_to(_gate_pos) <= GATE_ACTIVATION_RADIUS
	$Warrior.can_extract = in_range
	_update_gate_visual(in_range)
	if in_range != _gate_prompt_shown:
		_gate_prompt_shown = in_range
		if in_range:
			$HUD.show_status("DESCEND: PRESS F", GATE_COLOR_BRIGHT)
		else:
			$HUD.show_status("", Color.WHITE)


func _update_gate_visual(in_range: bool) -> void:
	if _gate_shaft_mat == null:
		return
	var pulse: float = 0.6 + 0.4 * sin(_gate_phase * GATE_PULSE_SPEED)
	var tint: Color = GATE_COLOR_BRIGHT if in_range else GATE_COLOR
	var shaft_a: float = (0.85 if in_range else 0.5) * pulse
	_gate_shaft_mat.albedo_color = Color(tint.r, tint.g, tint.b, shaft_a)
	var pad_a: float = 0.9 if in_range else 0.6
	_gate_pad_mat.albedo_color = Color(tint.r, tint.g, tint.b, pad_a)
