extends Node
class_name Ring1

## Ring 1 (The Pale Reaches) playfield — the 3D presentation layer: an `IsoRig`
## with the Ring 1 world geometry mounted under it. This is the composable scene
## Phase 4 wires into `main` alongside the warrior + HUD; it stays clean (no
## capture/quit dev hooks — those live in throwaway harnesses).
##
## Phase 1 scope: world geometry only. The warrior, enemies, and the 2D sim
## binding (Option B: `Vector2(x,y)` -> `Vector3(x,0,y)`) arrive in Phases 2-3.

const ROT_SPEED := 90.0  # deg/sec free camera orbit (pitch stays locked)

# Inject a rig before this enters the tree to share one rig across Ring 1 + the
# warrior + HUD (the Phase 4 `main` arrangement). Left null, Ring 1 self-creates
# and owns a rig so `ring1.tscn` still runs standalone.
var rig: IsoRig
var world: Ring1World
var _owns_rig := false


func _ready() -> void:
	if rig == null:
		rig = load("res://scenes/iso_rig.tscn").instantiate()
		add_child(rig)
		_owns_rig = true

	world = Ring1World.new()
	world.build(rig)
	rig.add_world_child(world)


func _process(delta: float) -> void:
	var spin := 0.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		spin += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
		spin -= 1.0
	if spin != 0.0:
		rig.orbit(spin * ROT_SPEED * delta)
