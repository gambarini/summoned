extends "res://scripts/enemy_mesh.gd"
class_name EnemyFleerMesh

## The fleer husk: tall, thin, backswept — built to run, not fight. Its "chase"
## is flight, so the sprint lean is steep and the gait fast; and when it is
## pinned against a wall it trembles harder and harder as the sim's cornered
## timer builds toward the detonation. The quiver IS the explosion's tell —
## diegetic geometry, like the Pale Herd's hum membrane — so the burst stops
## being an unreadable surprise.

const CORNERED_FUSE := 2.0  # mirror of enemy_fleer.gd's detonation threshold
const QUIVER_RATE := 26.0   # trembling phase rate (rad/s), ramping with the fuse
const QUIVER_AMP := 0.07

var _quiver_t: float = 0.0


func _init() -> void:
	_rest_y = 0.52
	_lean_max = 0.55
	_hunch = -0.06        # tilted back — wary even standing still
	_gait_freq = 13.0
	_bob_amp = 0.05
	_ref_speed = 90.0     # enemy_fleer.gd FLEE_SPEED


func _build_geometry(rig: IsoRig) -> void:
	var dark: Material = rig.solid_material(HUSK_DARK)
	var mid: Material = rig.solid_material(HUSK_MID)
	var pale: Material = rig.solid_material(HUSK_PALE)
	# Narrow upright torso.
	_box(Vector3(0.20, 0.46, 0.16), Vector3(0.0, 0.02, 0.0), mid)
	# Small head, carried high.
	_box(Vector3(0.14, 0.13, 0.15), Vector3(0.0, 0.32, 0.05), pale, -10.0)
	# Backswept crest — the panic silhouette.
	_box(Vector3(0.05, 0.09, 0.34), Vector3(0.0, 0.40, -0.16), dark, -24.0)
	# Tell channels: eye band + a membrane strip along the crest ridge.
	_box(Vector3(0.12, 0.04, 0.03), Vector3(0.0, 0.33, 0.135), _tell_mat, -10.0)
	_box(Vector3(0.028, 0.03, 0.30), Vector3(0.0, 0.455, -0.17), _tell_mat, -24.0)
	# Long runner legs.
	for side in [-1.0, 1.0]:
		var hip: Node3D = Node3D.new()
		hip.position = Vector3(side * 0.085, -0.20, 0.0)
		_body.add_child(hip)
		_box(Vector3(0.07, 0.36, 0.075), Vector3(0.0, -0.18, 0.0), dark, 0.0, hip)
		_legs.append(hip)


func _animate(sim_body: Node2D, state: StringName, delta: float) -> void:
	super(sim_body, state, delta)
	# Detonation build-up: peek at the sim's cornered timer (presentation-only
	# read of a private channel — the fuse has no public getter) and tremble
	# with it. fuse 0 -> rock still; fuse 1 -> about to blow.
	var fuse: float = 0.0
	var raw: Variant = sim_body.get("_cornered_timer")
	if raw != null:
		fuse = clampf(float(raw) / CORNERED_FUSE, 0.0, 1.0)
	_quiver_t += delta * QUIVER_RATE * (1.0 + 1.5 * fuse)
	_body.rotation.z = sin(_quiver_t) * QUIVER_AMP * fuse
	_body.rotation.x += sin(_quiver_t * 1.73) * QUIVER_AMP * 0.8 * fuse
