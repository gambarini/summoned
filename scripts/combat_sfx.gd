class_name CombatSfx
extends Node

## Placeholder combat audio (combat-feel backlog: the project shipped with ZERO
## AudioStreams — a swing whoosh + hit crunch is cheaply half of "impact").
## Every stream is SYNTHESIZED here at _ready() into an AudioStreamWAV — no
## imported assets, matching the all-procedural art direction — and deliberately
## lo-fi (22 kHz mono, soft-clipped) so the blips sit with the low-res pixel look.
## Presentation-only: WarriorSync instantiates this and calls play_* from the
## same edges that drive the slash VFX and hitstop; the sim never knows.
## Volumes/pitches are placeholder-tuned — expect a real pass when actual sound
## design happens.

const MIX_RATE: int = 22050
const RNG_SEED: int = 24413  # fixed seed -> the same sounds every session

# Per-combo-step swing pitch: steps 0-2 vary around 1.0 so the flourish doesn't
# machine-gun one identical sample; the thrust finisher (3) drops low + heavy.
const SWING_PITCH: Array[float] = [1.0, 1.12, 0.94, 0.78]

var _swing: AudioStreamPlayer = null
var _hit: AudioStreamPlayer = null
var _dash: AudioStreamPlayer = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = RNG_SEED
	# Swing: air displaced by the blade — band-swept noise rising into the cut.
	_swing = _make_player(_make_whoosh(0.17, 300.0, 2600.0), -8.0, 3)
	# Hit: contact — a dark noise burst over a low decaying thump.
	_hit = _make_player(_make_crunch(0.11), -4.0, 3)
	# Dash: a longer air-burst darkening as the lunge bleeds out.
	_dash = _make_player(_make_whoosh(0.22, 1800.0, 350.0), -10.0, 2)


func play_swing(combo_step: int) -> void:
	var idx: int = clampi(combo_step, 0, SWING_PITCH.size() - 1)
	_swing.pitch_scale = SWING_PITCH[idx] * _rng.randf_range(0.97, 1.03)
	_swing.play()


func play_hit() -> void:
	_hit.pitch_scale = _rng.randf_range(0.94, 1.06)
	_hit.play()


func play_dash() -> void:
	_dash.pitch_scale = _rng.randf_range(0.97, 1.03)
	_dash.play()


func _make_player(stream: AudioStreamWAV, volume_db: float, polyphony: int) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.max_polyphony = polyphony  # buffered chains overlap tails, don't cut them
	add_child(p)
	return p


# --- synthesis -------------------------------------------------------------

# White noise through a two-pole lowpass whose cutoff sweeps f_from -> f_to and
# back (triangle peak at 60% through), under a smooth rise-fall envelope.
# f_to > f_from reads as a blade whoosh; f_to < f_from as a dissipating burst.
func _make_whoosh(duration: float, f_from: float, f_to: float) -> AudioStreamWAV:
	var n: int = int(duration * MIX_RATE)
	var frames: PackedFloat32Array = PackedFloat32Array()
	frames.resize(n)
	var lp: float = 0.0
	var lp2: float = 0.0
	for i in range(n):
		var t: float = float(i) / n
		var env: float = pow(sin(PI * t), 1.5)
		var sweep: float = t / 0.6 if t < 0.6 else 1.0 - (t - 0.6) / 0.4
		var cutoff: float = lerpf(f_from, f_to, sweep)
		var a: float = clampf(TAU * cutoff / MIX_RATE, 0.0, 1.0)
		var noise: float = _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * a
		lp2 += (lp - lp2) * a  # second pole steepens the hiss rolloff
		frames[i] = lp2 * env * 2.4  # make up the level the filter eats
	return _wav_from(frames)


# Contact crunch: a fast-decaying dark noise burst (the crack) layered over a
# ~72 Hz decaying sine (the body of the impact).
func _make_crunch(duration: float) -> AudioStreamWAV:
	var n: int = int(duration * MIX_RATE)
	var frames: PackedFloat32Array = PackedFloat32Array()
	frames.resize(n)
	var lp: float = 0.0
	var a: float = clampf(TAU * 1600.0 / MIX_RATE, 0.0, 1.0)
	for i in range(n):
		var t: float = float(i) / MIX_RATE
		var noise: float = _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * a
		var burst: float = lp * exp(-t * 42.0) * 2.0
		var thump: float = sin(TAU * 72.0 * t) * exp(-t * 26.0) * 0.9
		frames[i] = burst + thump
	return _wav_from(frames)


# Soft-clip (tanh) + 16-bit mono pack. The clip is the "mastering": synth layers
# can sum past 1.0 and the saturation reads pleasantly crunchy at this fidelity.
func _wav_from(frames: PackedFloat32Array) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames.size() * 2)
	for i in range(frames.size()):
		var v: float = tanh(frames[i] * 1.5) * 0.85
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
