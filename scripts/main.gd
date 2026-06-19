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

# Per-ring enemy spawn tables (sim-space px; the bounds are universal, so positions
# are ring-independent). Keyed by GameState.current_ring; missing keys fall back to
# Ring 1's set. Spawns live here, not on the terrain builders — the builders own
# only terrain + palette + environment (Phase 5).
const SPAWNS := {
	1: [
		[EnemyScene,        Vector2(80, 50)],
		[EnemyScene,        Vector2(400, 50)],
		[EnemyScene,        Vector2(80, 220)],
		[EnemyFleerScene,   Vector2(400, 220)],
		[EnemyPhaserScene,  Vector2(240, 40)],
	],
	2: [
		[EnemyScene,        Vector2(90, 60)],
		[EnemyFleerScene,   Vector2(390, 60)],
		[EnemyFleerScene,   Vector2(90, 210)],
		[EnemyPhaserScene,  Vector2(400, 210)],
		[EnemyPhaserScene,  Vector2(240, 50)],
		[EnemyScene,        Vector2(240, 230)],
	],
	3: [
		[EnemyScene,        Vector2(80, 50)],
		[EnemyPhaserScene,  Vector2(400, 50)],
		[EnemyPhaserScene,  Vector2(80, 220)],
		[EnemyFleerScene,   Vector2(400, 220)],
		[EnemyScene,        Vector2(240, 40)],
	],
	4: [
		[EnemyScene,        Vector2(90, 60)],
		[EnemyPhaserScene,  Vector2(390, 60)],
		[EnemyFleerScene,   Vector2(90, 210)],
		[EnemyPhaserScene,  Vector2(400, 210)],
		[EnemyFleerScene,   Vector2(240, 50)],
		[EnemyScene,        Vector2(240, 230)],
	],
	5: [
		[EnemyPhaserScene,  Vector2(90, 60)],
		[EnemyPhaserScene,  Vector2(390, 60)],
		[EnemyFleerScene,   Vector2(90, 210)],
		[EnemyFleerScene,   Vector2(390, 210)],
		[EnemyPhaserScene,  Vector2(240, 45)],
		[EnemyScene,        Vector2(150, 135)],
		[EnemyScene,        Vector2(330, 135)],
	],
}

var _rig: IsoRig
var _world: Node3D       # the current ring's terrain builder (RingNWorld)
var _warrior_sync: WarriorSync
var _world_sync: WorldSync

var _enemies_alive := 0
var _run_ended := false

func _ready() -> void:
	# --- 3D presentation rig: scene owns it, configures it per ring, mounts ----
	# the selected ring's terrain builder directly. Per-ring palette/environment
	# must be set BEFORE add_child (the rig builds its pipeline lazily on _ready
	# via _ensure_built). Ring 1 keeps the rig's baked defaults (no override) so
	# its verified render is provably untouched.
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


func _end_run() -> void:
	_run_ended = true
	GameState.advance_clock()

func _on_warrior_died() -> void:
	_end_run()
	GameState.run_count += 1
	GameState.grief_reserve = max(GameState.grief_reserve - 1, 0)
	GameState.reset_ring()  # placeholder progression: death ends the run (back to Ring 1)
	get_tree().change_scene_to_file("res://scenes/base.tscn")

func _on_warrior_extracted() -> void:
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
	var spawns: Array = SPAWNS.get(GameState.current_ring, SPAWNS[1])
	for s in spawns:
		var e := (s[0] as PackedScene).instantiate() as EnemyBase
		add_child(e)
		e.global_position = s[1]
		e.enemy_died.connect(_on_enemy_died)
		_enemies_alive += 1
		if last_song:
			e.force_amplify()
