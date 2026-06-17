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

var _rig: IsoRig
var _ring1: Ring1
var _warrior_sync: WarriorSync
var _world_sync: WorldSync

var _enemies_alive := 0
var _run_ended := false

func _ready() -> void:
	# --- 3D presentation rig: scene owns it and injects it into Ring1 ---------
	_rig = load("res://scenes/iso_rig.tscn").instantiate()
	add_child(_rig)
	_ring1 = load("res://scenes/ring1.tscn").instantiate()
	_ring1.rig = _rig  # inject before it enters the tree (shared rig)
	add_child(_ring1)

	# --- Hybrid bindings: 2D bodies drive 3D billboards -----------------------
	_warrior_sync = WarriorSync.new()
	add_child(_warrior_sync)
	_warrior_sync.setup(_rig, $Warrior)

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
	get_tree().change_scene_to_file("res://scenes/base.tscn")

func _on_warrior_extracted() -> void:
	_end_run()
	GameState.extractions += 1
	get_tree().change_scene_to_file("res://scenes/base.tscn")

func _on_enemy_died() -> void:
	_enemies_alive -= 1
	if _enemies_alive == 0 and not _run_ended:
		_on_run_cleared()

func _on_run_cleared() -> void:
	$HUD.show_status("AREA CLEAR", Color(0.753, 0.627, 0.941, 1))

func _spawn_enemies() -> void:
	var last_song := GameState.is_last_song()
	var spawns := [
		[EnemyScene,        Vector2(80, 50)],
		[EnemyScene,        Vector2(400, 50)],
		[EnemyScene,        Vector2(80, 220)],
		[EnemyFleerScene,   Vector2(400, 220)],
		[EnemyPhaserScene,  Vector2(240, 40)],
	]
	for s in spawns:
		var e := (s[0] as PackedScene).instantiate() as EnemyBase
		add_child(e)
		e.global_position = s[1]
		e.enemy_died.connect(_on_enemy_died)
		_enemies_alive += 1
		if last_song:
			e.force_amplify()
