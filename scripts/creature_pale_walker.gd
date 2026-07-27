class_name CreaturePaleWalker
extends Creature

## The Pale Herd (GDD Ring 1) — one walker of the collective. The baseline-calm
## teacher: a tall pale grazer that never fights. The herd exists because no single
## animal can watch enough of the featureless landscape alone — together their
## collective hum forms a detection web, so one member seeing the warrior makes the
## WHOLE herd uneasy.
##
##   Calm      — grazing drift, loosely cohering around the herd. The collective hum
##               (tell: a slow, deep, warm pulse — almost pleasant).
##   Uneasy    — something registered: the herd tightens and drifts away from the
##               threat. Tell goes irregular, stuttering.
##   Scattered — genuine threat (struck, or the warrior in an animal's space): the
##               herd fragments INSTANTLY, each animal sprinting a different vector.
##               The hum dissolves into sharp individual pulses.
##
## No aggressive state. A lone separated animal cannot return to Calm without the
## collective — it stays Uneasy, hum irregular and searching (the GDD's Isolated).
## Resonance READS this creature but does not change its decision — the Pale Herd is
## what non-hostile feels like; the intervention lesson belongs to the Threshold.

const CALM := &"calm"
const UNEASY := &"uneasy"
const SCATTERED := &"scattered"

# Movement (sim px/s). Long legs built for covering ground: the scatter sprint far
# outruns the warrior's 100; grazing is a slow ambient drift.
const GRAZE_SPEED := 26.0
const UNEASY_SPEED := 58.0
const SCATTER_SPEED := 175.0
const REGROUP_SPEED := 46.0

# Herd shape.
const COHESION_DIST := 75.0    # farther than this from the herd centre -> drift back
const SEPARATION_DIST := 28.0  # closer than this to a mate -> push apart
const HERD_RADIUS := 95.0      # a mate inside this counts toward the collective
const REGROUP_MIN := 2         # mates within HERD_RADIUS needed to return to Calm

# Timings.
const UNEASY_RELAX := 3.5      # s after the last threat ping before regrouping starts
const SCATTER_TIME := 2.2      # s of fragment sprint before the animal slows to regroup
const SCATTER_FAN := 1.1       # rad of per-animal spread around directly-away
const GRAZE_TURN_MIN := 1.4    # s between grazing heading changes
const GRAZE_TURN_MAX := 3.0
const SEARCH_TURN_MIN := 0.6   # the isolated search wander re-aims faster, irregular
const SEARCH_TURN_MAX := 1.4

# Placeholder tells (the 2D octagon; the cel-mesh mirrors Visual.color verbatim).
const COL_CALM := Color(0.93, 0.76, 0.62)       # slow deep warm pulse
const COL_UNEASY := Color(0.87, 0.81, 0.50)     # irregular, stuttering
const COL_SCATTERED := Color(0.96, 0.94, 1.0)   # sharp individual pulses, no coherence

var _mates: Array = []          # the whole herd, self included (assigned by the spawner)
var _threat_pos: Vector2 = Vector2.ZERO
var _threat_timer: float = 0.0
var _scatter_dir: Vector2 = Vector2.ZERO
var _scatter_timer: float = 0.0
var _wander_dir: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	detect_radius = 110.0  # wide-set peripheral vision — it notices you early
	attack_radius = 24.0   # "its space" — the warrior inside it is a genuine threat
	_rng.randomize()
	_wander_dir = Vector2.from_angle(_rng.randf_range(0.0, TAU))
	super()
	frequency = Freq.HARMONIC  # the collective hum is a harmonic signature

## The spawner hands every walker the full herd array (self included).
func set_herd(mates: Array) -> void:
	_mates = mates

# ── Collective web (any member can ping the whole herd) ─────────────────────

func herd_alert(threat: Vector2) -> void:
	if _dead or _pacified:
		return
	_threat_pos = threat
	_threat_timer = UNEASY_RELAX
	if _state == CALM:
		_change_state(UNEASY)

func herd_scatter(threat: Vector2) -> void:
	if _dead or _pacified:
		return
	_threat_pos = threat
	_threat_timer = UNEASY_RELAX
	if _state != SCATTERED:
		_change_state(SCATTERED)

func _alert_herd(threat: Vector2) -> void:
	for m in _mates:
		if is_instance_valid(m):
			m.herd_alert(threat)

func _scatter_herd(threat: Vector2) -> void:
	for m in _mates:
		if is_instance_valid(m):
			m.herd_scatter(threat)

# ── State machine ────────────────────────────────────────────────────────────

func _initial_state() -> StringName:
	return CALM

func _enter_state(next: StringName) -> void:
	match next:
		CALM:
			_wander_timer = 0.0
		SCATTERED:
			_scatter_timer = SCATTER_TIME
			# Each animal sprints its OWN vector: a wide fan around directly-away.
			var away: Vector2 = global_position - _threat_pos
			var base_angle: float = away.angle() if away.length_squared() > 1.0 \
					else _rng.randf_range(0.0, TAU)
			_scatter_dir = Vector2.from_angle(base_angle + _rng.randf_range(-SCATTER_FAN, SCATTER_FAN))

func _update_state(delta: float) -> void:
	if _threat_timer > 0.0:
		_threat_timer -= delta
	# A member that still sees the warrior keeps the whole web alert (and pointed).
	if is_instance_valid(_player) and _state != SCATTERED:
		_alert_herd(_player.global_position)
	match _state:
		CALM:
			_graze(delta)
		UNEASY:
			_uneasy(delta)
		SCATTERED:
			_scatter(delta)

func _graze(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(GRAZE_TURN_MIN, GRAZE_TURN_MAX)
		_wander_dir = Vector2.from_angle(_rng.randf_range(0.0, TAU))
	velocity = (_wander_dir + _flock_correction()).normalized() * GRAZE_SPEED

func _uneasy(delta: float) -> void:
	if _threat_timer > 0.0:
		# Drift away from the threat, tightened into the herd.
		var away: Vector2 = (global_position - _threat_pos).normalized()
		velocity = (away + _flock_correction() * 0.8).normalized() * UNEASY_SPEED
		return
	# Threat faded. Only the collective can return an animal to Calm.
	if _mates_within(HERD_RADIUS) >= REGROUP_MIN:
		_change_state(CALM)
		return
	var centroid: Vector2 = _mates_centroid()
	if centroid.is_finite():
		velocity = (centroid - global_position).normalized() * REGROUP_SPEED
	else:
		# Truly alone (the Isolated): hum irregular and searching — it wanders,
		# re-aiming often, and stays Uneasy forever.
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = _rng.randf_range(SEARCH_TURN_MIN, SEARCH_TURN_MAX)
			_wander_dir = Vector2.from_angle(_rng.randf_range(0.0, TAU))
		velocity = _wander_dir * REGROUP_SPEED

func _scatter(delta: float) -> void:
	_scatter_timer -= delta
	# Full sprint that bleeds off toward the end of the fragment burst.
	velocity = _scatter_dir * SCATTER_SPEED * maxf(_scatter_timer / SCATTER_TIME, 0.35)
	if _scatter_timer <= 0.0:
		_change_state(UNEASY)  # the regroup rule decides whether Calm is reachable

# ── Reactions ────────────────────────────────────────────────────────────────

func _on_player_event(event: StringName) -> void:
	match event:
		&"detected":
			if is_instance_valid(_player):
				_alert_herd(_player.global_position)
		&"in_attack":
			# The warrior inside an animal's space = genuine threat -> instant fragment.
			_scatter_herd(_player.global_position if is_instance_valid(_player) else global_position)
		&"lost":
			_player = null

func _on_attacked(_attacker_freq: int) -> void:
	_scatter_herd(global_position)

## The Pale Herd never fights: no aggressive state, no damage path, and its worst
## reaction to the warrior is to sprint away. It is what non-hostile feels like, so it
## stays off the run's clear-count — a ring must not require killing a herd to clear.
func is_hostile() -> bool:
	return false

func _tell_color() -> Color:
	match _state:
		UNEASY: return COL_UNEASY
		SCATTERED: return COL_SCATTERED
		_: return COL_CALM

# ── Herd queries ─────────────────────────────────────────────────────────────

func _mates_within(radius: float) -> int:
	var n: int = 0
	for m in _mates:
		if m != self and is_instance_valid(m) \
				and global_position.distance_to(m.global_position) <= radius:
			n += 1
	return n

func _mates_centroid() -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var n: int = 0
	for m in _mates:
		if m != self and is_instance_valid(m):
			sum += m.global_position
			n += 1
	return sum / n if n > 0 else Vector2.INF

# Boids-lite: pull toward the herd centre when straggling, push apart when crowding.
func _flock_correction() -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var centroid: Vector2 = _mates_centroid()
	for m in _mates:
		if m == self or not is_instance_valid(m):
			continue
		var away: Vector2 = global_position - m.global_position
		var d: float = away.length()
		if d < SEPARATION_DIST and d > 0.1:
			push += away / d * (1.0 - d / SEPARATION_DIST)
	var pull: Vector2 = Vector2.ZERO
	if centroid.is_finite():
		var to_centre: Vector2 = centroid - global_position
		if to_centre.length() > COHESION_DIST:
			pull = to_centre.normalized()
	return pull + push * 1.5
