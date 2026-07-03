class_name CreatureThreshold
extends Creature

## The Threshold (GDD Ring 1) — an opportunistic stone-grey ambush predator. The
## sharpest single test of the F1 framework: it demonstrates that Resonance changes a
## creature's DECISION, not just reads it.
##
##   Still       — a frequency absence; pressed to the ground, indistinguishable from
##                 terrain. Reads as cold negative space.
##   Assessing   — slow directional rotation toward the warrior. THE WINDOW: projecting
##                 any frequency (a Resonance pulse, or a strike) registers an unknown
##                 variable and it withdraws — no fight. Missing the window (letting it
##                 close, or stepping into its space) lets it commit.
##   Committed   — a single fast, costly lunge. Binary: it commits or it doesn't.
##   Withdrawn   — drops back, will not reconsider until the situation resets to Still.

const STILL := &"still"
const ASSESSING := &"assessing"
const COMMITTED := &"committed"
const WITHDRAWN := &"withdrawn"

const ASSESS_TIME := 1.6      # window length before the assessment completes → commit
const COMMIT_SPEED := 165.0
const COMMIT_TIME := 0.55     # lunge duration cap
const COMMIT_DAMAGE := 2      # "significant Coherence damage" for a missed window
const COMMIT_REACH := 11.0    # px to the warrior that counts as the lunge landing
const WITHDRAW_SPEED := 80.0
const WITHDRAW_TIME := 2.2

# Placeholder tells (recolour the octagon until the cel-mesh lands).
const COL_STILL := Color(0.20, 0.22, 0.26)      # cold near-terrain absence
const COL_ASSESS := Color(0.83, 0.60, 0.30)     # amber, rotating
const COL_COMMIT := Color(1.0, 0.86, 0.55)      # sharp spike
const COL_WITHDRAWN := Color(0.32, 0.38, 0.48)  # dim retreat

var _timer: float = 0.0
var _struck: bool = false  # the committed lunge lands once

func _ready() -> void:
	detect_radius = 78.0  # assesses from a distance, before the warrior is close
	attack_radius = 13.0  # "its space" — entering it closes the window
	super()
	frequency = Freq.DISSONANT

func _initial_state() -> StringName:
	return STILL

func _enter_state(next: StringName) -> void:
	match next:
		STILL:
			_player = null
		ASSESSING:
			_timer = ASSESS_TIME
		COMMITTED:
			_timer = COMMIT_TIME
			_struck = false
		WITHDRAWN:
			_timer = WITHDRAW_TIME

func _update_state(delta: float) -> void:
	match _state:
		ASSESSING:
			# Cosmetic directional rotation toward the warrior; the read "points".
			if is_instance_valid(_player):
				_visual.rotation = (_player.global_position - global_position).angle()
			_timer -= delta
			if _timer <= 0.0:
				_change_state(COMMITTED)  # window closed unchallenged → it commits
		COMMITTED:
			_timer -= delta
			if is_instance_valid(_player):
				var to_player := _player.global_position - global_position
				velocity = to_player.normalized() * COMMIT_SPEED
				if not _struck and to_player.length() <= COMMIT_REACH:
					_struck = true
					_player.take_damage(COMMIT_DAMAGE)
					_change_state(WITHDRAWN)
					return
			if _timer <= 0.0:
				_change_state(WITHDRAWN)
		WITHDRAWN:
			# Pull back from the last known threat, decelerating, ignoring the warrior.
			if is_instance_valid(_player):
				velocity = (global_position - _player.global_position).normalized() * WITHDRAW_SPEED
			_timer -= delta
			if _timer <= 0.0:
				_visual.rotation = 0.0
				_change_state(STILL)

func _on_player_event(event: StringName) -> void:
	match event:
		&"detected":
			if _state == STILL:
				_change_state(ASSESSING)
		&"in_attack":
			# Stepping into its space while it assesses = missed window → commit.
			if _state == ASSESSING:
				_change_state(COMMITTED)

## Projecting a frequency during the assessment is the intervention: it reads an
## unknown variable and withdraws without committing. The whole point of the creature.
func _on_resonance_projected() -> void:
	if _state == ASSESSING:
		_change_state(WITHDRAWN)

func _on_attacked(_attacker_freq: int) -> void:
	if _state == ASSESSING:
		_change_state(WITHDRAWN)

func _tell_color() -> Color:
	match _state:
		ASSESSING: return COL_ASSESS
		COMMITTED: return COL_COMMIT
		WITHDRAWN: return COL_WITHDRAWN
		_: return COL_STILL
