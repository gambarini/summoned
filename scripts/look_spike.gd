extends Node
## Look-match de-risk spike (THROWAWAY — not wired into the game).
##
## Proves the proposed Ring 1 look upgrade on one surface set, inside the real
## `IsoRig`, so the rotation behaviour is honest:
##   - left dome  = current look (flat cel `solid_material`)
##   - right dome = new look (world-space triplanar pixel-art stone, no swim)
##   - back wall  = textured cliff face (vertical strata read)
##   - atmosphere = denser fog value-ramp + dropped ambient (dusk mood)
## Compare its capture against `idea/the_pale_reaches_concept_1.png`. Orbit with
## A/D (or `orbit()` via exec) to confirm the grain stays locked to the surface.
## Delete once the technique is accepted or rejected.

const STONE_TEX := "res://assets/textures/stone_pale.png"
const TRIPLANAR_SHADER := "res://assets/shaders/cel_triplanar.gdshader"

const COL_GROUND := Color("7c8591")   # measured open ground
const COL_DOME := Color("667383")     # measured concept dome (flat baseline tint)

var _rig: IsoRig


func _ready() -> void:
	_rig = IsoRig.new()
	_rig.name = "IsoRig"
	_rig.cam_size = 20.0
	_rig.fog_density = 0.016  # denser than live (0.004) so distance fades to haze
	add_child(_rig)           # builds the pipeline in its own _ready
	_tune_environment()
	_build_content()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_A:
			_rig.orbit(-15.0)
		elif event.keycode == KEY_D:
			_rig.orbit(15.0)


# Drop the near-white ambient fill so shadow + fog carry the dusk mood, and sink
# the background toward the fog so the world dissolves into haze at distance.
func _tune_environment() -> void:
	var vp := _rig.get_world_viewport()
	for child in vp.get_children():
		if child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment
			env.ambient_light_energy = 0.5
			env.background_color = Color("505d70")
			return


func _stone_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(TRIPLANAR_SHADER)
	m.set_shader_parameter("albedo_tex", load(STONE_TEX))
	m.set_shader_parameter("texture_scale", 0.7)
	m.set_shader_parameter("bands", _rig.cel_bands)
	m.set_shader_parameter("light_gain", _rig.cel_light_gain)
	return m


func _build_content() -> void:
	var world := Node3D.new()
	world.name = "SpikeWorld"

	# Ground plane (flat pale ground — the domes are the subject).
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	ground.material_override = _rig.solid_material(COL_GROUND)
	world.add_child(ground)

	# Left: current look — flat cel dome.
	world.add_child(_make_dome(Vector3(-5.0, 0.0, 2.0), _rig.solid_material(COL_DOME)))
	# Right: new look — triplanar pixel-art stone dome.
	world.add_child(_make_dome(Vector3(5.0, 0.0, 2.0), _stone_material()))

	# Back: textured cliff/plateau face (tests the vertical triplanar projection).
	var cliff := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(16.0, 7.0, 5.0)
	cliff.mesh = box
	cliff.position = Vector3(0.0, 1.0, -9.0)  # top sits ~4.5 above ground
	cliff.material_override = _stone_material()
	world.add_child(cliff)

	_rig.add_world_child(world)


func _make_dome(pos: Vector3, mat: Material) -> MeshInstance3D:
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 5.0
	sphere.is_hemisphere = true
	dome.mesh = sphere
	dome.position = pos
	dome.material_override = mat
	return dome
