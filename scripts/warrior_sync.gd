extends Node
class_name WarriorSync

## Phase 2 hybrid binding: the warrior's 2D `CharacterBody2D` stays the source of
## truth (Option B); this drives a camera-facing 3D billboard from it each frame.
##
## - Position: `Vector2(x,y)` sim px -> `Vector3(x,0,y)` world units (the
##   transform below is ring-specific, so it lives here, not on the reusable rig).
## - Facing: the 8-dir sheet picked from the body's *velocity* relative to camera
##   yaw (via the rig's pure-math helper) — so the sprite faces correctly at any
##   orbit angle.
## - Input: a camera-relative provider injected into the warrior, so "up" is
##   always away-from-camera as the camera rotates.
## - The 2D body is hidden (`visible = false` on the root) — physics, timers,
##   combat, and signals keep running; only the 2D *presentation* is suppressed,
##   which also defers effects-as-3D (the notation/Hollow nodes) to Phase 2b.

# --- sim<->world transform (ring-specific; NOT on the rig) ---------------
# Two anchors bracket PPU: plateau width (480/26 ≈ 18.5) and the spike's tuned
# 6 u/s feel (warrior SPEED 100 px/s -> 100/6 ≈ 16.7). ~18 sits between them.
const PIXELS_PER_UNIT := 18.0
const SIM_ORIGIN := Vector2(240.0, 135.0)  # 2D play-area centre -> world origin
const HOVER_Y := 2.0                        # billboard height on the plateau top
const MOVE_EPSILON := 8.0                   # px/s; below this, keep last facing

const DIR_NAMES := [
	"north", "north-east", "east", "south-east",
	"south", "south-west", "west", "north-west",
]

# Fixed raw input for programmatic/headless drive (capture harness). The
# `Vector2.INF` sentinel means "read live Input" (the normal play path).
var raw_input_override := Vector2.INF

var _rig: IsoRig
var _warrior: CharacterBody2D
var _billboard: Sprite3D
var _dir_textures := {}
var _facing := "south"


## Current 8-dir sheet name (for verification / debugging).
func get_facing() -> String:
	return _facing


## The billboard's world position — output of the sim->world transform.
func get_billboard_position() -> Vector3:
	return _billboard.position


func setup(rig: IsoRig, warrior: CharacterBody2D) -> void:
	_rig = rig
	_warrior = warrior

	for d in DIR_NAMES:
		_dir_textures[d] = load("res://assets/sprites/warrior_8dir/%s.png" % d)

	_billboard = Sprite3D.new()
	_billboard.name = "WarriorBillboard"
	_billboard.texture = _dir_textures[_facing]
	_billboard.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_billboard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_billboard.shaded = false
	_billboard.pixel_size = 0.045
	rig.add_world_child(_billboard)

	# The billboard is the warrior now: suppress all 2D presentation in one line
	# (a hidden root Node2D isn't drawn even when children set visible=true), and
	# stop the 2D camera fighting the display. Physics/combat are untouched.
	_warrior.visible = false
	var cam := _warrior.get_node_or_null("Camera2D")
	if cam:
		cam.enabled = false

	# Camera-relative input: "up" stays away-from-camera at any yaw.
	_warrior.input_provider = Callable(self, "_camera_dir")

	_sync_position()  # place the billboard before the first frame


# Camera-relative sim-space move direction from raw input (live or overridden).
func _camera_dir() -> Vector2:
	var raw := raw_input_override
	if raw == Vector2.INF:
		raw = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return _rig.camera_relative_dir(raw)


# Visual sync runs after physics, so it reads the body's post-move state.
func _process(_delta: float) -> void:
	_sync_position()
	_sync_facing()


func _sync_position() -> void:
	var p := _warrior.global_position
	_billboard.position = Vector3(
		(p.x - SIM_ORIGIN.x) / PIXELS_PER_UNIT,
		HOVER_Y,
		(p.y - SIM_ORIGIN.y) / PIXELS_PER_UNIT
	)


func _sync_facing() -> void:
	var v := _warrior.velocity
	if v.length() < MOVE_EPSILON:
		return  # keep last facing while idle
	var dir_name := _rig.facing_name(Vector2(v.x, v.y))
	if dir_name != "" and dir_name != _facing:
		_facing = dir_name
		_billboard.texture = _dir_textures[_facing]
