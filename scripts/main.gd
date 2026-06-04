extends Node2D

const EnemyScene       := preload("res://scenes/enemy.tscn")
const EnemyFleerScene  := preload("res://scenes/enemy_fleer.tscn")
const EnemyPhaserScene := preload("res://scenes/enemy_phaser.tscn")
const EnemyBase        := preload("res://scripts/enemy.gd")

var _enemies_alive := 0
var _run_ended := false

func _ready() -> void:
	$HUD.bind($Warrior)
	$Warrior.warrior_died.connect(_on_warrior_died)
	$Warrior.warrior_extracted.connect(_on_warrior_extracted)
	if GameState.is_last_song():
		$HUD.show_status("LAST SONG", Color("#C4547A"))
	_spawn_enemies()

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
