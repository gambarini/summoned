extends Node
class_name IsoRig

## Reusable low-res 3D isometric rendering rig.
##
## Promotes the proven pipeline from the walled-off spike
## (`scenes/ring1_iso_test.tscn`) into a component the game scenes mount into:
## an orthographic camera on a rotation pivot, the locked-resolution
## `_world_viewport` -> palette-post -> `_post_viewport` -> display chain, plus
## the cel/palette materials and a measured Ring 1 environment. Drop this in,
## add 3D content via `add_world_child()`, and you get the look.
##
## The pipeline is built in code (not editor-authored) so the measured values
## transfer byte-for-byte from the spike. See `docs/RENDERING_3D.md`.
##
## Scope (Phase 0): rig only. It owns no game content, never moves gameplay
## entities, and never quits the tree. Content/terrain/billboards belong to the
## consumer scene (Phases 1+). The 2D sim stays the source of truth (Option B):
## the camera-relative helpers below are pure math returning sim-space values
## (`Vector2(x, y)`, mapped to 3D as `Vector3(x, 0, y)`); they move nothing.

# 8-dir sheet names, ordered clockwise from "away from camera".
const DIR_NAMES := [
	"north", "north-east", "east", "south-east",
	"south", "south-west", "west", "north-west",
]

# --- Render / pipeline ---------------------------------------------------
## Internal render resolution (chunky pixel grid). Both SubViewports lock here.
@export var render_size := Vector2i(320, 180)
## Fixed colour palette every pixel snaps to. Default = measured Ring 1 terrain
## ramp (greys + warm doorway pinpoint) PLUS two gameplay-signal colours that the
## combat read depends on: the enemy frequency hues (dissonant pink / harmonic
## lavender, from `enemy.gd` COLORS). Without them, frequency billboards snap to
## the nearest grey/warm and the read collapses (see MIGRATION_3D Phase 3). They
## sit far from every terrain grey, so terrain never snaps to them. Signal hues
## are gameplay-universal (not ring-specific); other rings should keep them when
## swapping the terrain ramp. 16 entries = the shader's `palette[16]` ceiling.
@export var palette: PackedStringArray = PackedStringArray([
	"2a333f", "36414f", "485462", "4c5a6d",
	"566375", "5a697d", "616b78", "667383",
	"6e7a89", "7c8591", "8b95a0",
	"a8b1ba", "cbd2d3",
	"c89a5e",
	"c4547a", "c0a0f0",  # signal: dissonant pink, harmonic lavender
])

# --- Camera --------------------------------------------------------------
## Orthographic camera height in world units (zoom). Smaller = closer.
@export var cam_size := 26.0
## Pivot pitch in degrees; the iso angle. ~-30 reads as 2:1 dimetric.
@export var pivot_pitch := -30.0
## Starting yaw in degrees. Orbit freely from here; pitch stays locked.
@export var initial_yaw := 45.0
## Distance the camera sits from the pivot. Keep it near (ortho fog washes far).
@export var cam_distance := 22.0

# --- Environment (per-ring; default measured Ring 1) ---------------------
@export var bg_color := Color("5a697d")        # sky / haze
@export var fog_color := Color("5a697d")        # aerial haze tint
@export var fog_density := 0.004                # keep light; only far edge fades
@export var ambient_color := Color("eef1f5")    # near-white flat fill (keeps albedo)
@export var key_light_color := Color("c8d0db")  # cold, raking key light
@export var key_light_rotation := Vector3(-42.0, 130.0, 0.0)

# --- Cel shading ---------------------------------------------------------
@export var cel_bands := 2.0       # number of hard light steps
@export var cel_light_gain := 0.3  # how much the directional adds (low = soft)

var _world_viewport: SubViewport  # the 3D render
var _post_viewport: SubViewport   # 3D render + palette post (this is what's captured)
var _display: TextureRect         # on-screen scaled view
var _pivot: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _cel_shader: Shader
var _built := false


func _ready() -> void:
	_ensure_built()


## Idempotent: builds the pipeline on first call. Invoked from `_ready` and from
## every public accessor, so consumers can mount content regardless of node
## `_ready` ordering (children `_ready` before parents — without this guard, a
## parent adding content in its own `_ready` could race rig construction and
## render blank).
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_yaw = initial_yaw
	_cel_shader = load("res://assets/shaders/cel.gdshader")
	_build_display()
	_build_world()


# --- Public API ----------------------------------------------------------

## The SubViewport holding the 3D scene. Add cel-shaded geometry / billboards
## here (or use `add_world_child`). Guaranteed live after this returns.
func get_world_viewport() -> SubViewport:
	_ensure_built()
	return _world_viewport


## Mount a 3D node into the rendered world.
func add_world_child(node: Node) -> void:
	_ensure_built()
	_world_viewport.add_child(node)


## The post-processed SubViewport — what the display shows and what a capture
## should sample (3D render + palette snap).
func get_post_viewport() -> SubViewport:
	_ensure_built()
	return _post_viewport


## The orthographic camera (read-only use: basis for camera-relative helpers).
func get_camera() -> Camera3D:
	_ensure_built()
	return _camera


## Current camera yaw in degrees.
func get_yaw() -> float:
	return _yaw


## Orbit the camera by `delta_deg` (pitch stays locked, so iso is preserved).
func orbit(delta_deg: float) -> void:
	_ensure_built()
	_yaw = fmod(_yaw + delta_deg, 360.0)
	_pivot.rotation_degrees.y = _yaw


## A cel/toon material with the given albedo. All world geometry should use this.
func solid_material(col: Color) -> ShaderMaterial:
	_ensure_built()
	var m := ShaderMaterial.new()
	m.shader = _cel_shader
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("bands", cel_bands)
	m.set_shader_parameter("light_gain", cel_light_gain)
	return m


# --- Camera-relative helpers (pure math; Option B — move nothing) --------

## Map a 2D input vector (e.g. `Input.get_vector(left,right,up,down)`) to a
## sim-space direction relative to the current camera yaw, so "up" on screen is
## always away from the camera. Returns `Vector2(x, y)` in the 2D sim's space
## (3D is `Vector3(x, 0, y)`); zero-length input returns `Vector2.ZERO`.
func camera_relative_dir(input: Vector2) -> Vector2:
	_ensure_built()
	if input.length() < 0.1:
		return Vector2.ZERO
	var gb := _camera_ground_basis()
	var right: Vector3 = gb[0]
	var fwd: Vector3 = gb[1]
	var move := (right * input.x - fwd * input.y).normalized()
	return Vector2(move.x, move.z)


## Pick the 8-direction sheet index for a sim-space movement direction, as the
## move reads *on screen* under the current camera yaw. Returns 0..7 indexing
## `DIR_NAMES`; `Vector2.ZERO` returns -1 (caller should keep last facing).
func facing_index(sim_move: Vector2) -> int:
	_ensure_built()
	if sim_move.length() < 0.0001:
		return -1
	var move := Vector3(sim_move.x, 0.0, sim_move.y).normalized()
	var gb := _camera_ground_basis()
	var right: Vector3 = gb[0]
	var fwd: Vector3 = gb[1]
	var screen_x := move.dot(right)
	var screen_up := move.dot(fwd)
	var angle := rad_to_deg(atan2(screen_x, screen_up))  # 0 = away, +90 = right
	var idx := int(round(angle / 45.0)) % DIR_NAMES.size()
	if idx < 0:
		idx += DIR_NAMES.size()
	return idx


## Convenience: the 8-dir sheet name for a sim-space move ("" if zero-length).
func facing_name(sim_move: Vector2) -> String:
	var idx := facing_index(sim_move)
	return DIR_NAMES[idx] if idx >= 0 else ""


# Camera forward/right projected onto the ground plane. Returns [right, fwd].
func _camera_ground_basis() -> Array:
	var basis := _camera.global_transform.basis
	var fwd := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return [right, fwd]


# --- Pipeline construction (verbatim port of the spike) ------------------

func _build_display() -> void:
	# Both SubViewports stay locked at render_size — they must NOT live under a
	# SubViewportContainer, whose stretch would resize them to the window. Chain:
	# 3D world -> _world_viewport -> TextureRect(palette post) -> _post_viewport
	# (captured) -> display TextureRect scaled up nearest-neighbour.
	_world_viewport = SubViewport.new()
	_world_viewport.size = render_size
	_world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_world_viewport)

	_post_viewport = SubViewport.new()
	_post_viewport.size = render_size
	_post_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_post_viewport)

	var post_rect := TextureRect.new()
	post_rect.size = Vector2(render_size)
	post_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	post_rect.stretch_mode = TextureRect.STRETCH_SCALE
	post_rect.texture = _world_viewport.get_texture()
	post_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	post_rect.material = _make_post_material()
	_post_viewport.add_child(post_rect)

	_display = TextureRect.new()
	_display.texture = _post_viewport.get_texture()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_display)


func _make_post_material() -> ShaderMaterial:
	var pal := PackedVector3Array()
	for hex in palette:
		var c := Color(hex)
		pal.append(Vector3(c.r, c.g, c.b))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/pixel_post.gdshader")
	mat.set_shader_parameter("palette", pal)
	mat.set_shader_parameter("palette_count", pal.size())
	mat.set_shader_parameter("tex_size", Vector2(render_size))
	mat.set_shader_parameter("dither_strength", 0.0)  # flat bands, not stippled blend
	mat.set_shader_parameter("edge_strength", 0.0)    # no ink outline
	return mat


func _build_world() -> void:
	_world_viewport.add_child(_make_environment())
	_world_viewport.add_child(_make_key_light())
	_world_viewport.add_child(_make_camera_rig())


func _make_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = 1.0  # near-white flat fill; cel light adds the bands
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_light_energy = 1.0
	env.fog_density = fog_density
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0

	var we := WorldEnvironment.new()
	we.environment = env
	return we


func _make_key_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = key_light_rotation
	light.light_color = key_light_color
	light.light_energy = 1.0  # cel light_gain controls how soft the bands are
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	return light


func _make_camera_rig() -> Node3D:
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position = Vector3(0.0, 0.5, 0.0)
	_pivot.rotation_degrees = Vector3(pivot_pitch, _yaw, 0.0)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL  # the iso-defining choice
	_camera.size = cam_size
	# Ortho is distance-independent, so keep the camera near — a far camera makes
	# depth fog wash the whole frame.
	_camera.position = Vector3(0.0, 0.0, cam_distance)
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.current = true
	_pivot.add_child(_camera)
	return _pivot
