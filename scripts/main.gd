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

var _rig: IsoRig
var _world: Node3D       # the current ring's terrain builder (RingNWorld)
var _warrior_sync: WarriorSync
var _world_sync: WorldSync

var _enemies_alive := 0
var _run_ended := false

func _ready() -> void:
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
	_spawn_enemies()


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
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		spin += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
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


func _end_run() -> void:
	_run_ended = true
	GameState.advance_clock()

func _on_warrior_died() -> void:
	if _run_ended:
		return  # the run already resolved (extract/death race) — count it once
	_end_run()
	GameState.run_count += 1
	GameState.grief_reserve = max(GameState.grief_reserve - 1, 0)
	GameState.reset_ring()  # placeholder progression: death ends the run (back to Ring 1)
	get_tree().change_scene_to_file("res://scenes/base.tscn")

func _on_warrior_extracted() -> void:
	if _run_ended:
		return  # the run already resolved (extract/death race) — count it once
	_end_run()
	GameState.extractions += 1
	GameState.advance_ring()  # placeholder progression: extraction pushes one ring deeper
	get_tree().change_scene_to_file("res://scenes/base.tscn")

func _on_enemy_died() -> void:
	_enemies_alive -= 1
	if _enemies_alive == 0 and not _run_ended:
		_on_run_cleared()

func _on_run_cleared() -> void:
	$HUD.show_status("AREA CLEAR", Color(0.753, 0.627, 0.941, 1))

func _spawn_enemies() -> void:
	var last_song := GameState.is_last_song()
	var mix: Array = SPAWN_MIX.get(GameState.current_ring, SPAWN_MIX[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + GameState.current_ring  # deterministic layout per ring
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
			e.enemy_died.connect(_on_enemy_died)
			_enemies_alive += 1
			if last_song:
				e.force_amplify()
