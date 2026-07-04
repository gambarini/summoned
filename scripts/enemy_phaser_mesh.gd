extends "res://scripts/enemy_mesh.gd"
class_name EnemyPhaserMesh

## The phaser husk: a floating two-faced crystal — a 4-facet bipyramid spinning
## over the ground. Its whole identity is the frequency flip it wears openly
## (enemy_phaser.gd never hides its colour), so the tell is the biggest channel
## of any husk: the full equatorial band between the two pyramid halves. Spin
## quickens into the strike; the hover bob replaces a gait.

const SPIN_IDLE := 1.1    # rad/s
const SPIN_CHASE := 3.0
const SPIN_ATTACK := 6.0
const HOVER_PERIOD := 2.1
const HOVER_AMP := 0.05

# Crystal palette — colder than the walking husks; still clear of signal hues.
const CRYSTAL_DARK := Color("353043")
const CRYSTAL_MID := Color("524c66")

var _spin: float = 0.0
var _hover_t: float = 0.0


func _init() -> void:
	_rest_y = 0.55


func _build_geometry(rig: IsoRig) -> void:
	var dark: Material = rig.solid_material(CRYSTAL_DARK)
	var mid: Material = rig.solid_material(CRYSTAL_MID)
	# Two pyramid halves around the equatorial tell band.
	_pyramid(0.26, 0.32, Vector3(0.0, 0.215, 0.0), dark, false)
	_pyramid(0.26, 0.28, Vector3(0.0, -0.185, 0.0), mid, true)
	var band: MeshInstance3D = MeshInstance3D.new()
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = 0.27
	c.bottom_radius = 0.27
	c.height = 0.07
	c.radial_segments = 4
	band.mesh = c
	band.material_override = _tell_mat
	band.position = Vector3(0.0, 0.02, 0.0)
	_body.add_child(band)


# Fully replaces the grunt posing: no limbs — spin, hover, and a chase tilt.
func _animate(_sim_body: Node2D, state: StringName, delta: float) -> void:
	if _body == null:
		return
	var rate: float = SPIN_IDLE + (SPIN_CHASE - SPIN_IDLE) * minf(_speed_n, 1.0)
	if state == &"attack":
		rate = SPIN_ATTACK
	_spin += delta * rate
	_hover_t += delta
	# Pitch composes inside the yaw (YXZ), so the chase tilt precesses with the
	# spin — an unstable, hungry wobble.
	_body.rotation = Vector3(0.16 * minf(_speed_n, 1.0), _spin, 0.0)
	_body.position.y = _rest_y + sin(_hover_t * TAU / HOVER_PERIOD) * HOVER_AMP


func _pyramid(r: float, h: float, pos: Vector3, mat: Material, flip: bool) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = r if flip else 0.0
	c.bottom_radius = 0.0 if flip else r
	c.height = h
	c.radial_segments = 4
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	_body.add_child(mi)
