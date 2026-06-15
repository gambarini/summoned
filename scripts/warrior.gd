extends CharacterBody2D

const SPEED := 100.0
const ACCEL := 10.0   # lerp factor toward target speed — higher = snappier start
const DECEL := 14.0   # lerp factor toward zero — slightly faster stop than start

# Vertical hover bob + horizontal sway — driven here in GDScript (not the shader)
# so the Hollow nodes ride the same offset and stay welded to the chest. Phase is
# integrated incrementally (_bob_phase += speed * delta) so speed can change with
# movement without the sprite racing through cycles — multiplying an accumulated
# TIME by a changing frequency is what caused the start/stop "jump". Bob only runs
# in IDLE/MOVE, matching the old shader (which only displaced Sprite8Dir).
const HOVER_SPEED := 0.8        # base bob cycle speed (rad/s)
const HOVER_PIXELS := 1.5       # base vertical amplitude (px) at idle
const HOVER_MOVE_SPEED := 0.45  # speed scale added at full move
const HOVER_MOVE_BOB := 0.6     # amplitude scale added at full move
const HOVER_SWAY := 1.2         # horizontal pendulum amplitude (px) at full move
const _BOB_BASE_BODY := Vector2(0, 0)
const _BOB_BASE_HOLLOW := Vector2(0, 4)
var _bob_phase := 0.0
const MAX_COHERENCE := 10
const RESONANCE_RADIUS := 120.0
const BURST_RADIUS := 80.0
const AttackArcScene := preload("res://scenes/attack_arc.tscn")
const EnemyScript = preload("res://scripts/enemy.gd")
const _NOTATION_SHEET := preload("res://assets/sprites/notation_glyphs.png")

# Notation drift — emission ratio at rest vs. moving, and per-coherence-tier
# density multiplier (high · medium · low · critical). See _setup_notation_drift.
const NOTATION_IDLE_RATIO := 0.4
const NOTATION_MOVE_RATIO := 0.8
const _NOTATION_TIER_SCALE := [0.8, 1.0, 1.25, 1.55]

# The Hollow — per hollow_stress (0–3), mirrors HOLLOW_STRESS_PARAMS in WARRIOR.md.
# Rendered as two stacked sprites so it reads as a *hole*, not a lamp: a dark void
# disc (normal blend, carves a recess into the body) with a smaller burning ember
# core (additive) sunk inside it. The dark gap between them sells the depth.
# Brightness = ember alpha (dims as the wound opens); radius = scale of both discs;
# inward = HollowPull emission ratio (more notation devoured under stress).
const _HOLLOW_VOID_SCALE := 0.72   # dark recess — kept wider than the ember
const _HOLLOW_GLOW_SCALE := 0.34   # burning core — tight point sunk inside the void
const _HOLLOW_BRIGHTNESS := [1.0, 0.85, 0.65, 0.4]
const _HOLLOW_RADIUS := [1.0, 1.2, 1.5, 1.9]
const _HOLLOW_INWARD := [0.0, 0.25, 0.6, 0.9]

# The Hollow is a front-of-chest wound — it must not render on the warrior's back.
# Visibility factor per facing (multiplies ember + void alpha). Mirrors the
# "Hollow Visibility Per Direction" table in WARRIOR.md. Applied in IDLE/MOVE only.
const _HOLLOW_DIR_VIS := {
	"s": 1.0, "se": 0.6, "sw": 0.6,
	"e": 0.3, "w": 0.3,
	"ne": 0.0, "n": 0.0, "nw": 0.0,
}

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
@export var hollow_stress: int = 0: set = _set_hollow_stress  # 0–3
@export var tribe_coherence_tier: int = 0 # 0=high 1=medium 2=low 3=critical

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _sprite_8dir: Sprite2D = $Sprite8Dir
@onready var _shader_mat: ShaderMaterial = $Sprite8Dir.material as ShaderMaterial
@onready var _notation: GPUParticles2D = $NotationDrift
@onready var _hollow_glow: Sprite2D = $HollowGlow
@onready var _hollow_void: Sprite2D = $HollowVoid
@onready var _hollow_pull: GPUParticles2D = $HollowPull

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
	_setup_notation_drift()
	_setup_hollow()
	_apply_hollow_stress()
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
	_update_hover(delta)
	_refresh_hollow_facing()

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

# Movement direction in sim space. The 3D iso layer (Phase 2) injects a
# camera-relative provider so "up" stays away-from-camera as the camera orbits;
# unset, this is the original screen-space WASD read (2D behaviour unchanged).
var input_provider: Callable

func _read_dir() -> Vector2:
	if input_provider.is_valid():
		return input_provider.call()
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
	_tween_notation_intensity(target, duration)
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

# Hover bob + sway. Reads the already-tweened move_intensity so the ramp is shared
# with the shader's hem/shimmer. Phase is integrated, never (accumulated time ×
# changing speed), so a speed change only bends the curve forward — no jump. The
# offset is applied to the body sprites AND the Hollow nodes so the wound rides the
# chest; it zeroes outside IDLE/MOVE so attacks/hurt/death sit still as before.
func _update_hover(delta: float) -> void:
	var mi := 0.0
	if _shader_mat:
		mi = _shader_mat.get_shader_parameter("move_intensity") as float
	_bob_phase += HOVER_SPEED * (1.0 + mi * HOVER_MOVE_SPEED) * delta
	var off := Vector2.ZERO
	if _state in [State.IDLE, State.MOVE]:
		off.y = sin(_bob_phase) * (HOVER_PIXELS * (1.0 + mi * HOVER_MOVE_BOB))
		off.x = sin(_bob_phase * 0.65 + 1.0) * (mi * HOVER_SWAY)
	_sprite_8dir.position = _BOB_BASE_BODY + off
	_sprite.position = _BOB_BASE_BODY + off
	_hollow_void.position = _BOB_BASE_HOLLOW + off
	_hollow_glow.position = _BOB_BASE_HOLLOW + off
	_hollow_pull.position = _BOB_BASE_HOLLOW + off

# ── Notation drift particles ──────────────────────────────────────────────────
# "His cloak has no clean edge; it dissolves into drifting notation particles at
# its boundary." (GDD §18). One world-space emitter sheds random glyphs from the
# 4-frame notation sheet. World space = particles stay put as the warrior moves,
# so the movement "trail" of score debris falls out of the same node for free.

func _setup_notation_drift() -> void:
	if _notation == null:
		return
	_notation.texture = _NOTATION_SHEET
	_notation.amount = 24
	_notation.lifetime = 1.4
	_notation.explosiveness = 0.0
	_notation.randomness = 0.5
	_notation.local_coords = false   # world space → movement leaves a debris trail
	_notation.preprocess = 1.4       # field is already populated when the warrior appears
	_notation.amount_ratio = minf(NOTATION_IDLE_RATIO * _notation_tier_scale(), 1.0)

	# Each particle locks onto a random static glyph from the 4-frame strip.
	_notation.material = _make_glyph_material()

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(11.0, 11.0, 0.0)  # over the cloak silhouette
	pm.direction = Vector3(0.0, -1.0, 0.0)              # notation rises off the form
	pm.spread = 40.0
	pm.gravity = Vector3(0.0, -8.0, 0.0)                # gentle upward drift
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.damping_min = 2.0
	pm.damping_max = 6.0                                # notes decelerate and hang
	pm.scale_min = 0.18
	pm.scale_max = 0.32                                 # smaller score debris
	pm.scale_curve = _build_notation_scale_curve()     # shrink as they dissolve
	pm.angle_min = -25.0
	pm.angle_max = 25.0                                 # initial tumble per glyph
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0                      # slow continuous spin
	pm.tangential_accel_min = -6.0
	pm.tangential_accel_max = 6.0                       # gentle curl around the form
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 4.0                  # waft on invisible currents
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.4
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0                            # random frame across the strip
	pm.color_ramp = _build_notation_ramp()
	_notation.process_material = pm
	_notation.emitting = true

func _build_notation_ramp() -> GradientTexture1D:
	# Alpha over particle lifetime: fade in fast, hold, dissolve out.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.9),
		Color(1, 1, 1, 0.7),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex

func _build_notation_scale_curve() -> CurveTexture:
	# Scale over lifetime: pop to full size, then taper to nothing as it dissolves.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.7))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex

func _notation_tier_scale() -> float:
	return _NOTATION_TIER_SCALE[clampi(tribe_coherence_tier, 0, 3)]

func _tween_notation_intensity(move_target: float, duration: float) -> void:
	if _notation == null:
		return
	var ratio := lerpf(NOTATION_IDLE_RATIO, NOTATION_MOVE_RATIO, move_target) * _notation_tier_scale()
	create_tween().tween_property(_notation, "amount_ratio", minf(ratio, 1.0), duration)

# Random-static-glyph material: 4-frame strip, each particle locked to one frame.
func _make_glyph_material() -> CanvasItemMaterial:
	var cmat := CanvasItemMaterial.new()
	cmat.particles_animation = true
	cmat.particles_anim_h_frames = 4
	cmat.particles_anim_v_frames = 1
	cmat.particles_anim_loop = false
	return cmat

# ── The Hollow ────────────────────────────────────────────────────────────────
# "A burning void at the warrior's chest." (GDD §18). Rendered as two stacked
# discs so it reads as a *hole*, not a lamp: HollowVoid is a dark #0D0A1E recess
# (normal blend — additive can't darken) and HollowGlow is a smaller ember core
# (additive) sunk inside it; the dark gap between them sells the depth. HollowPull
# is a local-space emitter that draws notation inward — the wound devouring score.
# All scale with hollow_stress: the ember dims while the void widens, and the
# inward pull strengthens, as the Hollow opens. The whole assembly sits at the
# chest (node y = +4) and is gated by facing (_refresh_hollow_facing) so the wound
# never renders on the warrior's back during IDLE/MOVE.

func _setup_hollow() -> void:
	if _hollow_void:
		# Dark recess, normal blend — actually darkens the chest (additive can't).
		_hollow_void.texture = _make_radial_void(32)
		_hollow_void.centered = true
	if _hollow_glow:
		_hollow_glow.texture = _make_radial_glow(32)
		_hollow_glow.centered = true
		var gmat := CanvasItemMaterial.new()
		gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_hollow_glow.material = gmat
		# Breathing pulse on self_modulate so it multiplies the stress-set modulate.
		var pulse := create_tween().set_loops()
		pulse.tween_property(_hollow_glow, "self_modulate:a", 0.6, 0.9).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_hollow_glow, "self_modulate:a", 1.0, 0.9).set_ease(Tween.EASE_IN_OUT)
	if _hollow_pull:
		_hollow_pull.texture = _NOTATION_SHEET
		_hollow_pull.amount = 16
		_hollow_pull.lifetime = 0.85
		_hollow_pull.local_coords = true   # motes belong to the wound, follow the warrior
		_hollow_pull.material = _make_glyph_material()
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3(0.0, 0.0, 1.0)
		pm.emission_ring_radius = 22.0
		pm.emission_ring_inner_radius = 15.0
		pm.emission_ring_height = 0.0
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 0.0
		pm.radial_accel_min = -55.0
		pm.radial_accel_max = -35.0        # negative = pulled toward the wound
		pm.tangential_accel_min = 8.0
		pm.tangential_accel_max = 18.0     # slight spiral inward
		pm.scale_min = 0.28
		pm.scale_max = 0.42
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.anim_offset_min = 0.0
		pm.anim_offset_max = 1.0
		pm.color_ramp = _build_hollow_pull_ramp()
		_hollow_pull.process_material = pm
		_hollow_pull.emitting = true

func _make_radial_glow(size: int) -> GradientTexture2D:
	# Ember core: a small bright #F0E8D8 center, falling off through warm #D4803A
	# to a faint cold #7B4EA0 rim. Tight falloff so the bright part stays inside
	# the void disc, leaving a dark gap that reads as a recess. Added on top.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.36, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(0.941, 0.910, 0.847, 1.0),   # #F0E8D8 hot core
		Color(0.941, 0.910, 0.847, 0.9),
		Color(0.831, 0.502, 0.227, 0.45),  # #D4803A warm bleed
		Color(0.483, 0.306, 0.627, 0.12),  # #7B4EA0 cold rim, near gone
		Color(0.483, 0.306, 0.627, 0.0),
	])
	return _radial_texture(grad, size)

func _make_radial_void(size: int) -> GradientTexture2D:
	# The absence: opaque #0D0A1E core fading to transparent. Normal-blended so it
	# deepens the body to near-black — the hole the ember burns inside of.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.051, 0.039, 0.118, 1.0),
		Color(0.051, 0.039, 0.118, 0.92),
		Color(0.051, 0.039, 0.118, 0.4),
		Color(0.051, 0.039, 0.118, 0.0),
	])
	return _radial_texture(grad, size)

func _radial_texture(grad: Gradient, size: int) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex

func _build_hollow_pull_ramp() -> GradientTexture1D:
	# Notation (#A080E0) fades in, then shifts to the wound's heat (#F0E8D8) as
	# it is consumed near the center.
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

func _apply_hollow_stress() -> void:
	var s := clampi(hollow_stress, 0, 3)
	if _hollow_glow:
		_hollow_glow.scale = Vector2.ONE * (_HOLLOW_GLOW_SCALE * _HOLLOW_RADIUS[s])
	if _hollow_void:
		# The wound widens as it opens.
		_hollow_void.scale = Vector2.ONE * (_HOLLOW_VOID_SCALE * _HOLLOW_RADIUS[s])
	if _hollow_pull:
		_hollow_pull.amount_ratio = _HOLLOW_INWARD[s]
	_refresh_hollow_facing()

# Gate the Hollow by facing so the wound never appears on the warrior's back.
# Every directional state — IDLE/MOVE and the attack/echo states, all of which
# pose toward _facing_dir — obeys the gate, so the Hollow stays dark when the back
# is turned even mid-attack. HURT/DYING/SUMMONING use single-direction (front)
# sheets, so they keep the wound at full.
func _refresh_hollow_facing() -> void:
	var s := clampi(hollow_stress, 0, 3)
	var f := 1.0
	var directional := _state in [
		State.IDLE, State.MOVE,
		State.ATTACK_STARTUP, State.ATTACK_ACTIVE, State.ATTACK_RECOVERY,
		State.ECHO_ACTIVE,
	]
	if directional:
		f = _HOLLOW_DIR_VIS.get(_facing_dir, 1.0)
	var shown := f > 0.0
	if _hollow_glow:
		_hollow_glow.visible = shown
		_hollow_glow.modulate.a = _HOLLOW_BRIGHTNESS[s] * f
	if _hollow_void:
		_hollow_void.visible = shown
		_hollow_void.modulate.a = f
	if _hollow_pull:
		_hollow_pull.emitting = shown

func _set_hollow_stress(value: int) -> void:
	hollow_stress = clampi(value, 0, 3)
	if is_node_ready():
		_apply_hollow_stress()

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
