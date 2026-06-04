extends CharacterBody2D

const SPEED := 100.0
const ACCEL := 10.0   # lerp factor toward target speed — higher = snappier start
const DECEL := 14.0   # lerp factor toward zero — slightly faster stop than start
const MAX_COHERENCE := 10
const RESONANCE_RADIUS := 120.0
const BURST_RADIUS := 80.0
const AttackArcScene := preload("res://scenes/attack_arc.tscn")
const EnemyScript = preload("res://scripts/enemy.gd")

signal coherence_changed(value: int)
signal chain_changed(value: int)
signal warrior_died
signal warrior_extracted
signal resonance_ready(is_ready: bool)

enum State {
	IDLE, MOVE,
	ATTACK_STARTUP, ATTACK_ACTIVE, ATTACK_RECOVERY,
	ECHO_ACTIVE,
	HURT, DYING, SUMMONING
}

# Overlay modifiers — do not gate states, read by visual/audio systems
@export var hollow_stress: int = 0        # 0–3
@export var tribe_coherence_tier: int = 0 # 0=high 1=medium 2=low 3=critical

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _sprite_8dir: Sprite2D = $Sprite8Dir
@onready var _shader_mat: ShaderMaterial = $Sprite8Dir.material as ShaderMaterial

var coherence: int
var chain := 0
var _state: State = State.SUMMONING
var _attack_dir: Vector2 = Vector2.RIGHT
var _was_extracted: bool = false
var _facing_dir: String = "s"
var _idle_pulse: Tween

# ── 8-direction rotation sprites (Pixellab object) ──────────────────────────
# Maps facing_dir → texture filename stem (all 8 dirs have real sprites)
const _DIR_8DIR := {
	"s":  "south",
	"se": "south-east",
	"e":  "east",
	"ne": "north-east",
	"n":  "north",
	"nw": "north-west",
	"w":  "west",
	"sw": "south-west",
}

var _8dir_textures: Dictionary = {}
var _use_8dir: bool = false  # true once all 8 PNGs are found in warrior_8dir/


# ── Animation manifest ───────────────────────────────────────────────────────
# direction → [anim_suffix, flip_h]
# All 8 directions are explicit in warrior_idle_attack.png — no flip needed.
const _DIR_ANIM := {
	"s":  ["s",  false], "se": ["se", false],
	"e":  ["e",  false], "ne": ["ne", false],
	"n":  ["n",  false], "nw": ["nw", false],
	"w":  ["w",  false], "sw": ["sw", false],
}

# [sheet_name, row, col_start, col_count, fps, loop]
# warrior_idle_attack.png: 8 rows × 7 cols, 64×64px
#   rows: 0=S 1=SE 2=E 3=NE 4=N 5=NW 6=W 7=SW
#   cols: 0=idle/startup-f1, 1-2=startup, 3-4=active, 5-6=recovery
const _ANIM_MANIFEST := {
	# Idle — 1 static frame per direction (col 0)
	"idle_s":       ["warrior_idle_attack", 0, 0, 1, 4.4,  true],
	"idle_se":      ["warrior_idle_attack", 1, 0, 1, 4.4,  true],
	"idle_e":       ["warrior_idle_attack", 2, 0, 1, 4.4,  true],
	"idle_ne":      ["warrior_idle_attack", 3, 0, 1, 4.4,  true],
	"idle_n":       ["warrior_idle_attack", 4, 0, 1, 4.4,  true],
	"idle_nw":      ["warrior_idle_attack", 5, 0, 1, 4.4,  true],
	"idle_w":       ["warrior_idle_attack", 6, 0, 1, 4.4,  true],
	"idle_sw":      ["warrior_idle_attack", 7, 0, 1, 4.4,  true],
	# Attack startup — cols 0-2 (3 frames, starts from idle pose)
	"startup_s":    ["warrior_idle_attack", 0, 0, 3, 17.0, false],
	"startup_se":   ["warrior_idle_attack", 1, 0, 3, 17.0, false],
	"startup_e":    ["warrior_idle_attack", 2, 0, 3, 17.0, false],
	"startup_ne":   ["warrior_idle_attack", 3, 0, 3, 17.0, false],
	"startup_n":    ["warrior_idle_attack", 4, 0, 3, 17.0, false],
	"startup_nw":   ["warrior_idle_attack", 5, 0, 3, 17.0, false],
	"startup_w":    ["warrior_idle_attack", 6, 0, 3, 17.0, false],
	"startup_sw":   ["warrior_idle_attack", 7, 0, 3, 17.0, false],
	# Attack active — cols 3-4 (2 frames, hitbox fires here)
	"active_s":     ["warrior_idle_attack", 0, 3, 2, 24.0, false],
	"active_se":    ["warrior_idle_attack", 1, 3, 2, 24.0, false],
	"active_e":     ["warrior_idle_attack", 2, 3, 2, 24.0, false],
	"active_ne":    ["warrior_idle_attack", 3, 3, 2, 24.0, false],
	"active_n":     ["warrior_idle_attack", 4, 3, 2, 24.0, false],
	"active_nw":    ["warrior_idle_attack", 5, 3, 2, 24.0, false],
	"active_w":     ["warrior_idle_attack", 6, 3, 2, 24.0, false],
	"active_sw":    ["warrior_idle_attack", 7, 3, 2, 24.0, false],
	# Attack recovery — cols 5-6 (2 frames)
	"recovery_s":   ["warrior_idle_attack", 0, 5, 2, 5.0,  false],
	"recovery_se":  ["warrior_idle_attack", 1, 5, 2, 5.0,  false],
	"recovery_e":   ["warrior_idle_attack", 2, 5, 2, 5.0,  false],
	"recovery_ne":  ["warrior_idle_attack", 3, 5, 2, 5.0,  false],
	"recovery_n":   ["warrior_idle_attack", 4, 5, 2, 5.0,  false],
	"recovery_nw":  ["warrior_idle_attack", 5, 5, 2, 5.0,  false],
	"recovery_w":   ["warrior_idle_attack", 6, 5, 2, 5.0,  false],
	"recovery_sw":  ["warrior_idle_attack", 7, 5, 2, 5.0,  false],
	# Universal — not yet created, will fail gracefully if missing
	"hurt":         ["warrior_hurt_v1",       0, 0, 2, 8.6,  false],
	"dying":        ["warrior_dying_v1",      0, 0, 6, 2.4,  false],
	"summoning":    ["warrior_summoning_v1",  0, 0, 6, 2.4,  false],
}

var _inactive: bool:
	get: return _state == State.DYING or _state == State.SUMMONING or _was_extracted

var low_health: bool:
	get: return coherence > 0 and coherence <= MAX_COHERENCE / 4

func _ready() -> void:
	coherence = GameState.starting_coherence()
	_setup_sprite_frames()
	_load_8dir_textures()
	$StartupTimer.timeout.connect(func(): _change_state(State.ATTACK_ACTIVE))
	$ActiveTimer.timeout.connect(func(): _change_state(State.ATTACK_RECOVERY))
	$RecoveryTimer.timeout.connect(_on_recovery_expired)
	$HurtTimer.timeout.connect(func(): _change_state(State.IDLE))
	$DyingTimer.timeout.connect(func(): warrior_died.emit())
	$SummoningTimer.timeout.connect(func(): _change_state(State.IDLE))
	$ResonanceCooldown.timeout.connect(func(): resonance_ready.emit(true))
	_change_state(State.SUMMONING)

func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_update_move_state()
	# Keep 8dir texture in sync with facing during idle/move
	if _use_8dir and _state in [State.IDLE, State.MOVE]:
		_refresh_8dir()

func _unhandled_input(event: InputEvent) -> void:
	match _state:
		State.DYING, State.SUMMONING, State.HURT, State.ATTACK_STARTUP, State.ATTACK_ACTIVE:
			return
		_:
			pass
	if event.is_action_pressed("attack"):
		_try_attack()
	elif event.is_action_pressed("resonance") and $ResonanceCooldown.is_stopped():
		_do_resonance()
	elif event.is_action_pressed("extract"):
		_do_extract()

func _handle_movement(delta: float) -> void:
	var dir := _read_dir()
	if dir.length() > 0.1 and _state in [State.IDLE, State.MOVE, State.ECHO_ACTIVE]:
		_facing_dir = _vector_to_dir(dir)
	match _state:
		State.DYING, State.SUMMONING, State.HURT, State.ATTACK_STARTUP:
			velocity = Vector2.ZERO
		State.ECHO_ACTIVE:
			var target := dir * (SPEED * 0.4)
			velocity = velocity.lerp(target, ACCEL * delta)
		_:
			if dir.length() > 0.1:
				velocity = velocity.lerp(dir * SPEED, ACCEL * delta)
			else:
				velocity = velocity.lerp(Vector2.ZERO, DECEL * delta)
	move_and_slide()

func _read_dir() -> Vector2:
	return Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	).normalized()

func _update_move_state() -> void:
	if _state not in [State.IDLE, State.MOVE]:
		return
	# Base on input, not velocity — so shader tween fires at the right moment
	# regardless of lerp lag
	if _read_dir().length() > 0.1:
		if _state != State.MOVE:
			_change_state(State.MOVE)
	else:
		if _state != State.IDLE:
			_change_state(State.IDLE)

func _change_state(new_state: State) -> void:
	if _state == State.DYING:
		return
	_exit_state(_state)
	_state = new_state
	_enter_state(_state)

func _exit_state(old: State) -> void:
	match old:
		State.MOVE:
			_tween_move_intensity(0.0, 0.25)
		State.ECHO_ACTIVE:
			pass
		State.ATTACK_RECOVERY:
			# Leaving recovery early means a follow-up attack is chaining off
			# this one — cancel the expiry timer but KEEP the chain so the
			# combo builds. The chain only resets when recovery actually
			# expires (_on_recovery_expired) or the warrior is hurt.
			$RecoveryTimer.stop()

func _enter_state(new: State) -> void:
	match new:
		State.IDLE:
			if _use_8dir:
				_show_8dir()
			else:
				_show_anim()
				_play_dir("idle")
			_start_idle_pulse()
		State.MOVE:
			if _use_8dir:
				_show_8dir()
			else:
				_show_anim()
				_play_dir("move")
			_start_idle_pulse()
			_tween_move_intensity(1.0, 0.18)
		State.ATTACK_STARTUP:
			_show_anim()
			_stop_idle_pulse()
			$AttackCooldown.start()
			_attack_dir = (get_global_mouse_position() - global_position).normalized()
			if _attack_dir == Vector2.ZERO:
				_attack_dir = Vector2.RIGHT
			_facing_dir = _vector_to_dir(_attack_dir)
			_play_dir("startup")
			$StartupTimer.start()
		State.ATTACK_ACTIVE:
			_show_anim()
			_spawn_attack_arc()
			_play_dir("active")
			$ActiveTimer.start()
		State.ATTACK_RECOVERY:
			_show_anim()
			_play_dir("recovery")
			_start_idle_pulse()
			$RecoveryTimer.start()
		State.ECHO_ACTIVE:
			_show_anim()
			_stop_idle_pulse()
			var data: Array = _DIR_ANIM[_facing_dir]
			_sprite.flip_h = data[1]
			_sprite.play("idle_" + data[0])
			create_tween().tween_property(_sprite, "modulate:a", 0.65, 0.3)
		State.HURT:
			_show_anim()
			_reset_chain()
			_stop_idle_pulse()
			_sprite.play("hurt")
			var flash := create_tween().set_loops(3)
			flash.tween_property(_sprite, "modulate:a", 0.2, 0.038)
			flash.tween_property(_sprite, "modulate:a", 1.0, 0.038)
			$HurtTimer.start()
		State.DYING:
			_show_anim()
			_stop_idle_pulse()
			_sprite.play("dying")
			create_tween().tween_property(_sprite, "modulate:a", 0.0, 2.2).set_delay(0.3)
			$DyingTimer.start()
		State.SUMMONING:
			_show_anim()
			_stop_idle_pulse()
			_sprite.modulate.a = 0.0
			_sprite.play("summoning")
			create_tween().tween_property(_sprite, "modulate:a", 1.0, 0.6)
			$SummoningTimer.start()

# ── 8-dir sprite helpers ─────────────────────────────────────────────────────

func _load_8dir_textures() -> void:
	var stems: Array = _DIR_8DIR.values()
	# Deduplicate (all 8 are unique for Pixellab object sprites)
	var found := 0
	for stem in stems:
		var path := "res://assets/sprites/warrior_8dir/%s.png" % stem
		if ResourceLoader.exists(path):
			_8dir_textures[stem] = load(path)
			found += 1
	_use_8dir = (found == stems.size())
	if not _use_8dir:
		push_warning("Warrior: only %d/8 8dir sprites found — using legacy sheets" % found)


func _show_8dir() -> void:
	_sprite.hide()
	_sprite_8dir.modulate.a = 1.0
	_refresh_8dir()
	_sprite_8dir.show()

func _refresh_8dir() -> void:
	var stem: String = _DIR_8DIR[_facing_dir]
	var tex = _8dir_textures.get(stem)
	if tex:
		_sprite_8dir.texture = tex

func _show_anim() -> void:
	_sprite_8dir.hide()
	_sprite.modulate.a = 1.0
	_sprite.show()

# ── Animation helpers ────────────────────────────────────────────────────────

func _vector_to_dir(v: Vector2) -> String:
	if v.length() < 0.1:
		return _facing_dir
	var a := rad_to_deg(v.angle())  # 0=E, 90=S, -90=N in Godot's coordinate system
	if   a >= -22.5  and a <  22.5:  return "e"
	elif a >=  22.5  and a <  67.5:  return "se"
	elif a >=  67.5  and a < 112.5:  return "s"
	elif a >= 112.5  and a < 157.5:  return "sw"
	elif a >= -67.5  and a < -22.5:  return "ne"
	elif a >= -112.5 and a < -67.5:  return "n"
	elif a >= -157.5 and a < -112.5: return "nw"
	return "w"

func _play_dir(base: String) -> void:
	var data: Array = _DIR_ANIM[_facing_dir]
	_sprite.flip_h = data[1]
	_sprite.play(base + "_" + data[0])

func _tween_move_intensity(target: float, duration: float) -> void:
	if _shader_mat == null:
		return
	var current := _shader_mat.get_shader_parameter("move_intensity") as float
	create_tween().tween_method(
		func(v: float): _shader_mat.set_shader_parameter("move_intensity", v),
		current, target, duration
	)

func _start_idle_pulse() -> void:
	if _idle_pulse:
		_idle_pulse.kill()
	var target: Node = _sprite_8dir if _use_8dir else _sprite
	_idle_pulse = create_tween().set_loops()
	_idle_pulse.tween_property(target, "modulate:a", 0.75, 0.45).set_ease(Tween.EASE_IN_OUT)
	_idle_pulse.tween_property(target, "modulate:a", 1.0, 0.45).set_ease(Tween.EASE_IN_OUT)

func _stop_idle_pulse() -> void:
	if _idle_pulse:
		_idle_pulse.kill()
		_idle_pulse = null

# ── Combat ───────────────────────────────────────────────────────────────────

func _try_attack() -> void:
	if not $AttackCooldown.is_stopped():
		return
	if _state in [State.IDLE, State.MOVE, State.ATTACK_RECOVERY, State.ECHO_ACTIVE]:
		_change_state(State.ATTACK_STARTUP)

func _spawn_attack_arc() -> void:
	var arc := AttackArcScene.instantiate()
	get_parent().add_child(arc)
	arc.global_position = global_position
	arc.set_direction(_attack_dir)
	arc.hit_target.connect(_on_hit)
	if chain == 4:
		_do_burst()

func _on_hit(area: Area2D) -> void:
	# The arc itself owns the hit window: it lives for its full sweep and
	# dedupes per-enemy, so accept hits for the entire travel (not just the
	# brief ATTACK_ACTIVE frame). Only reject while the warrior is gone.
	if _inactive:
		return
	var parent = area.get_parent()
	if not parent.has_method("receive_hit"):
		return
	var result: int = parent.receive_hit(EnemyScript.Freq.DISSONANT)
	if result == EnemyScript.HitResult.CORRECT:
		chain = min(chain + 1, 4)
		chain_changed.emit(chain)
	else:
		_reset_chain()

func _on_recovery_expired() -> void:
	_reset_chain()
	_change_state(State.IDLE)

func _reset_chain() -> void:
	chain = 0
	chain_changed.emit(chain)

func take_damage(amount: int) -> void:
	if _state in [State.HURT, State.DYING, State.SUMMONING] or _was_extracted:
		return
	coherence = max(coherence - amount, 0)
	coherence_changed.emit(coherence)
	if coherence == 0:
		_change_state(State.DYING)
	else:
		_change_state(State.HURT)

# ── Resonance / burst / extract ──────────────────────────────────────────────

func _do_resonance() -> void:
	$ResonanceCooldown.start()
	resonance_ready.emit(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= RESONANCE_RADIUS:
			enemy.reveal(1.5)
	var ring := Polygon2D.new()
	ring.color = Color(0.627, 0.502, 0.878, 0.35)
	ring.polygon = _build_circle(RESONANCE_RADIUS, 20)
	get_parent().add_child(ring)
	ring.global_position = global_position
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.2, 1.2), 0.35).from(Vector2(0.2, 0.2))
	tween.tween_property(ring, "modulate:a", 0.0, 0.35).from(1.0)
	tween.chain().tween_callback(ring.queue_free)

func _do_burst() -> void:
	chain = 0
	chain_changed.emit(chain)
	var ring := Polygon2D.new()
	ring.color = Color(0.627, 0.502, 0.878, 0.6)
	ring.polygon = _build_circle(BURST_RADIUS, 20)
	get_parent().add_child(ring)
	ring.global_position = global_position
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.4, 1.4), 0.3).from(Vector2(0.1, 0.1))
	tween.tween_property(ring, "modulate:a", 0.0, 0.3).from(0.8)
	tween.chain().tween_callback(ring.queue_free)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= BURST_RADIUS:
			enemy.receive_hit(EnemyScript.Freq.DISSONANT)

func _do_extract() -> void:
	if _state in [State.DYING, State.SUMMONING]:
		return
	_was_extracted = true
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_callback(warrior_extracted.emit)

func _build_circle(r: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := (float(i) / steps) * TAU
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

# ── Sprite sheet setup (legacy) ───────────────────────────────────────────────

func _setup_sprite_frames() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name in _ANIM_MANIFEST:
		var m: Array = _ANIM_MANIFEST[anim_name]
		var sheet_path: String = "res://assets/sprites/%s.png" % m[0]
		var row: int = m[1]
		var col_start: int = m[2]
		var col_count: int = m[3]
		var fps: float = m[4]
		var loop: bool = m[5]
		var tex: Texture2D = load(sheet_path)
		var cols: int = _sheet_cols(m[0])
		var rows: int = _sheet_rows(m[0])
		var frame_w: int = tex.get_width() / cols
		var frame_h: int = tex.get_height() / rows
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, loop)
		for c in range(col_start, col_start + col_count):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(c * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame(anim_name, atlas)
	_sprite.sprite_frames = frames

func _sheet_cols(sheet_name: String) -> int:
	match sheet_name:
		"warrior_idle_attack":  return 7
		"warrior_hurt_v1":      return 2
		"warrior_dying_v1":     return 6
		"warrior_summoning_v1": return 6
	return 1

func _sheet_rows(sheet_name: String) -> int:
	match sheet_name:
		"warrior_idle_attack":  return 8
		"warrior_hurt_v1":      return 1
		"warrior_dying_v1":     return 1
		"warrior_summoning_v1": return 1
	return 1
