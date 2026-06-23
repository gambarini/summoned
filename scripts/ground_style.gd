extends RefCounted
class_name GroundStyle

## Shared "dusty-rock" ground recipe for every ring + the villa (one source of truth).
##
## The old tiling ground texture read as undersampling "static" at the iso distance, so
## walkable ground is now: a FLAT cel colour + a SMOOTH world-space macro value-drift
## (broad worn-earth mottle) + scattered flat stone/gravel/crack decals. Hue-agnostic —
## each world passes its own ground colour, so the same recipe themes per ring. Cliffs,
## sub-plateaus and stone ruins keep their own materials (peripheral / coarse / vertical).
## See `docs/RENDERING_3D.md` ("Ground style") and memory ground_texture_spike.

const _TRIPLANAR := "res://assets/shaders/cel_triplanar.gdshader"
const _SPRITE := "res://assets/shaders/sprite_cel.gdshader"
const _PEBBLES := "res://assets/textures/detail_pebbles.png"
const _GRAVEL := "res://assets/textures/detail_gravel.png"
const _CRACK := "res://assets/textures/detail_crack.png"

# Ground value the detail sprites were authored at (Ring 1 grey). A per-ring tint maps
# them to that ring's ground hue (reuse the proven asset, don't re-author per ring).
const _DETAIL_BASE := Color("7c8591")

const MACRO_SCALE := 0.015     # tiles/world-unit -> ~65u period: ONE broad drift, no repeat
const MACRO_STRENGTH := 0.5    # value excursion (proportional, so it suits dark + light grounds)
const DECAL_Y := 0.52          # just above the plateau top (0.5); tiny step so the outline won't rim

# Shared, lazily built (cheap to share across worlds — macro is just broad value drift).
static var _macro: NoiseTexture2D
static var _flat: Texture2D


# Flat cel ground material (no grain) + smooth macro value-drift. Pass the world's
# ground colour; `strength` can be lowered per surface (e.g. paths) if wanted.
static func ground_mat(rig: IsoRig, tint: Color, strength := MACRO_STRENGTH) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(_TRIPLANAR)
	m.set_shader_parameter("albedo_tex", _flat_tex())
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("texture_scale", 0.4)  # unused for a 1x1 albedo, kept valid
	m.set_shader_parameter("bands", rig.cel_bands)
	m.set_shader_parameter("light_gain", rig.cel_light_gain)
	m.set_shader_parameter("macro_noise", _macro_tex())
	m.set_shader_parameter("macro_scale", MACRO_SCALE)
	m.set_shader_parameter("macro_strength", strength)
	return m


# Scatter flat stone/gravel/crack decals over the walkable ground, tinted to `ground_col`.
# One MultiMeshInstance3D per texture (one draw call each). Covers the HUB (where the
# player fights) too, rejecting only the tight central combat band; thins toward the rim.
static func scatter_decals(parent: Node3D, rig: IsoRig, half: Vector2, ground_col: Color,
		seed := 41) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tint := Color(ground_col.r / _DETAIL_BASE.r, ground_col.g / _DETAIL_BASE.g,
		ground_col.b / _DETAIL_BASE.b)
	var area := half.x * half.y
	_layer(parent, rig, _PEBBLES, tint, clampi(int(area * 0.02), 60, 220), 1.4, 2.8, rng, half)
	_layer(parent, rig, _GRAVEL, tint, clampi(int(area * 0.015), 40, 160), 1.6, 3.0, rng, half)
	_layer(parent, rig, _CRACK, tint, clampi(int(area * 0.006), 16, 70), 3.0, 5.0, rng, half)


# Tight central combat band kept clear so warrior/enemy/arc signals stay legible.
static func is_central(p: Vector3) -> bool:
	return absf(p.x) < 4.5 and absf(p.z) < 4.0


static func _macro_tex() -> NoiseTexture2D:
	if _macro == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02  # LOW = a few big smooth blobs (high freq = fine static)
		noise.seed = 7
		_macro = NoiseTexture2D.new()
		_macro.width = 256
		_macro.height = 256
		_macro.seamless = true
		_macro.normalize = true
		_macro.noise = noise
	return _macro


static func _flat_tex() -> Texture2D:
	if _flat == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		_flat = ImageTexture.create_from_image(img)
	return _flat


static func _decal_mat(rig: IsoRig, tex_path: String, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(_SPRITE)
	m.set_shader_parameter("albedo_tex", load(tex_path))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("bands", rig.cel_bands)
	m.set_shader_parameter("light_gain", rig.cel_light_gain)
	m.set_shader_parameter("alpha_cut", 0.5)
	m.set_shader_parameter("billboard", false)
	return m


static func _layer(parent: Node3D, rig: IsoRig, tex_path: String, tint: Color, count: int,
		smin: float, smax: float, rng: RandomNumberGenerator, half: Vector2) -> void:
	var xforms: Array[Transform3D] = []
	var attempts := 0
	var max_d := half.length()
	while xforms.size() < count and attempts < count * 5:
		attempts += 1
		var x := rng.randf_range(-half.x + 1.0, half.x - 1.0)
		var z := rng.randf_range(-half.y + 1.0, half.y - 1.0)
		if is_central(Vector3(x, 0.0, z)):
			continue
		var d := Vector2(x, z).length()
		var t := clampf(1.0 - d / max_d * 0.6, 0.3, 1.0)  # mild thinning to the rim
		if rng.randf() > t:
			continue
		var s := rng.randf_range(smin, smax)
		var basis := Basis(Vector3.UP, deg_to_rad(rng.randf_range(0.0, 360.0))).scaled(Vector3(s, 1.0, s))
		xforms.append(Transform3D(basis, Vector3(x, DECAL_Y, z)))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE  # scaled per-instance; lies in XZ, normal +Y (ground-aligned)
	mm.mesh = pm
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _decal_mat(rig, tex_path, tint)
	parent.add_child(mmi)
