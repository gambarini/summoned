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

# --- t3ssel8r pixel-art machinery (ported from the proven spike) ----------
## Texels of overscan added to each side of the render target so the final blit
## can slide by the sub-pixel remainder without revealing a gap at the edge.
const PAD := 3
## Pivot height the follow camera tracks at; the warrior's x/z drive it, y is held
## constant so vertical hover never pumps the frame.
const FOLLOW_PIVOT_Y := 0.5
## Seconds for the depth outline to fade back in after the camera stops orbiting.
## The outline pass amplifies the (structural, unfixable) orbit-reprojection crawl,
## so it is faded toward 0 while actively orbiting (spike finding).
const OUTLINE_FADE_TIME := 0.18

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
	"566375", "5a697d", "667383",         # dropped near-dup mid-grey 616b78 for the warm slot
	"6e7a89", "7c8591", "8b95a0",
	"a8b1ba", "cbd2d3",
	"c89a5e", "d4803a",  # warm: terrain tan + the warrior's reserved ember amber
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
@export var ambient_energy := 1.0               # fill strength; <1 lets fog/key model dusk
@export var key_light_color := Color("c8d0db")  # cold, raking key light
@export var key_light_rotation := Vector3(-42.0, 130.0, 0.0)

# --- Cel shading ---------------------------------------------------------
@export var cel_bands := 2.0       # number of hard light steps
@export var cel_light_gain := 0.3  # how much the directional adds (low = soft)

# --- Post pass --------------------------------------------------------------
@export var vignette_strength := 0.0  # corner darkening (per-ring); 0 = off

# --- Depth outline (t3ssel8r) -----------------------------------------------
## Transparent depth-based ink overlay (silhouette + crease). Reads only the depth
## buffer, so it is renderer-portable. Fades out during active orbit.
@export var outline_enabled := true
@export var outline_strength := 1.0
@export var outline_color := Color(0.08, 0.10, 0.14)
@export var outline_depth_threshold := 0.16
@export var outline_normal_threshold := 0.12

var _world_viewport: SubViewport  # the 3D render (padded by PAD on each side)
var _post_viewport: SubViewport   # 3D render + palette post (also padded)
var _screen_viewport: SubViewport # device-res composite; the sub-pixel offset lives here
var _display: TextureRect         # padded post, upscaled NEAREST into _screen_viewport
var _window_view: TextureRect     # shows _screen_viewport 1:1 in the stretched canvas
var _pivot: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _cel_shader: Shader
var _outline_mat: ShaderMaterial
var _built := false

# Derived pixel-grid geometry (set in _ensure_built / _resize_screen).
var _padded := Vector2i(326, 186)
var _world_per_texel := 1.0
var _upscale := 6
var _base_display_pos := Vector2.ZERO  # _display position at zero sub-pixel offset

# Follow-camera state. The consumer feeds the warrior's world position each frame
# (Path A): the pivot tracks it, snapped to whole texels on the camera's screen
# axes, and the fractional remainder is replayed as the blit offset -> smooth
# motion of crisp, texel-stable pixels.
var _follow_enabled := false
var _follow_target := Vector3(0.0, FOLLOW_PIVOT_Y, 0.0)

# Outline-fade: 1.0 right after an orbit input, decays to 0 over OUTLINE_FADE_TIME.
var _orbit_activity := 0.0


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
	# Padded render target + constant world-per-texel: the padded viewport renders a
	# few extra texels each side, but the ortho size is scaled up to match so each
	# texel still covers `cam_size / render_size.y` world units (the visible framing
	# is unchanged; the overscan is pure headroom for the sub-pixel slide).
	_padded = render_size + Vector2i(2 * PAD, 2 * PAD)
	_world_per_texel = cam_size / float(render_size.y)
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
	if delta_deg != 0.0:
		# Orbit reprojects the scene every frame — a structural crawl the snap cannot
		# fix and the outline pass amplifies. Mark activity so _process fades the ink.
		_orbit_activity = 1.0
	# Re-snap the follow against the new screen axes so the framing stays texel-locked
	# through the rotation.
	if _follow_enabled:
		_apply_follow()


## Feed the follow target each frame (Path A): the camera pivot tracks `world_pos`
## (x/z only; height held at FOLLOW_PIVOT_Y). The pivot is snapped to whole texels on
## the camera's screen axes and the fractional remainder is replayed as the blit
## offset, so the warrior stays centred while crisp, texel-stable pixels slide
## smoothly under him. Enables follow mode on first call.
func set_follow_target(world_pos: Vector3) -> void:
	_ensure_built()
	_follow_enabled = true
	_follow_target = Vector3(world_pos.x, FOLLOW_PIVOT_Y, world_pos.z)
	_apply_follow()


## The device-resolution composite SubViewport (the sub-pixel offset lives in its
## blit). This is what a deterministic capture should sample — NOT the OS window,
## whose size the project's content-scale settings can misreport.
func get_screen_viewport() -> SubViewport:
	_ensure_built()
	return _screen_viewport


## Project a world point to DISPLAYED render-space coordinates (0..render_size) — the
## same space the cursor lands in after undoing the display letterbox. The camera now
## renders into a PADDED viewport, so `unproject_position` returns padded coords (inset
## by PAD); and the sub-pixel blit shifts the displayed image. Both are undone here so
## screen-space aim (mouse -> world direction) stays correct under the new pipeline.
func world_to_render(world_pos: Vector3) -> Vector2:
	_ensure_built()
	var padded := _camera.unproject_position(world_pos)
	var sub := (_display.position - _base_display_pos) / float(_upscale)  # = (-frac.x, frac.y)
	return padded - Vector2(PAD, PAD) + sub


# Decompose the follow target onto the camera's screen right/up axes, snap each to
# whole texels (keeping depth — the forward axis — continuous so nothing pops in z),
# and replay the snapped-away fraction as the display offset.
func _apply_follow() -> void:
	if _camera == null:
		return
	var b := _camera.global_transform.basis
	var right := b.x.normalized()
	var up := b.y.normalized()
	var fwd := -b.z.normalized()

	var a := _follow_target.dot(right)
	var c := _follow_target.dot(up)
	var d := _follow_target.dot(fwd)
	var a_s: float = round(a / _world_per_texel) * _world_per_texel
	var c_s: float = round(c / _world_per_texel) * _world_per_texel
	_pivot.position = right * a_s + up * c_s + fwd * d

	var frac := Vector2((a - a_s) / _world_per_texel, (c - c_s) / _world_per_texel)
	_set_subpixel_offset(frac)


# Snapping the camera back by `frac` texels shifts the projected world forward on
# screen; offset the blit by -frac (in screen px) to cancel it, so the composited
# image slides smoothly by the true sub-texel amount while the RT pixels stay crisp
# and stable. Sign verified empirically in the spike (a screen-right pan must yield a
# smooth +1px/frame composited shift).
func _set_subpixel_offset(frac_texels: Vector2) -> void:
	if _display == null:
		return
	var off := Vector2(-frac_texels.x, frac_texels.y) * float(_upscale)
	_display.position = _base_display_pos + off


func _process(delta: float) -> void:
	if _orbit_activity > 0.0 and _outline_mat != null:
		_orbit_activity = maxf(0.0, _orbit_activity - delta / OUTLINE_FADE_TIME)
		_outline_mat.set_shader_parameter("outline_strength",
			outline_strength * (1.0 - _orbit_activity))


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
	# Chain: 3D world -> _world_viewport (PADDED) -> TextureRect(palette post) ->
	# _post_viewport (PADDED) -> _display TextureRect upscaled NEAREST into
	# _screen_viewport (DEVICE res) with the sub-pixel offset baked into the blit ->
	# _window_view shows _screen_viewport 1:1 in the stretched canvas. None of the
	# render viewports may live under a SubViewportContainer (its stretch would
	# resize them to the window).
	_world_viewport = SubViewport.new()
	_world_viewport.size = _padded
	_world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# No temporal/MSAA jitter — it would masquerade as (and dominate) orbit shimmer.
	_world_viewport.use_taa = false
	_world_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_world_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(_world_viewport)

	_post_viewport = SubViewport.new()
	_post_viewport.size = _padded
	_post_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_post_viewport)

	var post_rect := TextureRect.new()
	post_rect.size = Vector2(_padded)
	post_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	post_rect.stretch_mode = TextureRect.STRETCH_SCALE
	post_rect.texture = _world_viewport.get_texture()
	post_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	post_rect.material = _make_post_material()
	_post_viewport.add_child(post_rect)

	# Composite at DEVICE resolution. canvas_items stretch rasterizes the final
	# window at the device framebuffer, so a device-sized SubViewport shown FULL_RECT
	# maps 1:1 to device pixels — that is what lets the sub-pixel offset (which needs
	# device-pixel granularity) survive the project's 2D-transform pixel snap. The
	# 480x270 HUD on its own CanvasLayer cannot move with the offset: the offset lives
	# inside this viewport's texture, not in any canvas transform.
	_screen_viewport = SubViewport.new()
	_screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_screen_viewport)

	_display = TextureRect.new()
	_display.texture = _post_viewport.get_texture()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen_viewport.add_child(_display)

	_window_view = TextureRect.new()
	_window_view.texture = _screen_viewport.get_texture()
	_window_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_window_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_window_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_window_view)

	_resize_screen()
	get_window().size_changed.connect(_resize_screen)


## Size the device-res composite and the upscale to the live window, and recentre the
## padded display. Re-run on window resize. The upscale is the largest integer that
## fits render_size into the device — derived, never hardcoded, so it is correct on a
## ×6 (1920×1080) window or any other integer-multiple device size.
func _resize_screen() -> void:
	if _screen_viewport == null:
		return
	var dev: Vector2i = get_window().size
	dev.x = maxi(dev.x, render_size.x)
	dev.y = maxi(dev.y, render_size.y)
	_upscale = maxi(1, mini(dev.x / render_size.x, dev.y / render_size.y))
	_screen_viewport.size = dev
	_display.size = Vector2(_padded) * float(_upscale)
	# Centre the inner (unpadded) render region in the device viewport, then shift by
	# -PAD*upscale so the overscan sits off-screen on every side.
	_base_display_pos = (Vector2(dev) - Vector2(render_size) * float(_upscale)) * 0.5 \
		- Vector2(PAD, PAD) * float(_upscale)
	_display.position = _base_display_pos


func _make_post_material() -> ShaderMaterial:
	var pal := PackedVector3Array()
	for hex in palette:
		var c := Color(hex)
		pal.append(Vector3(c.r, c.g, c.b))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/pixel_post.gdshader")
	mat.set_shader_parameter("palette", pal)
	mat.set_shader_parameter("palette_count", pal.size())
	mat.set_shader_parameter("tex_size", Vector2(_padded))
	mat.set_shader_parameter("dither_strength", 0.0)  # flat bands, not stippled blend
	mat.set_shader_parameter("edge_strength", 0.0)    # no ink outline
	mat.set_shader_parameter("vignette", vignette_strength)
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
	env.ambient_light_energy = ambient_energy  # 1.0 = flat fill; per-ring can dim for dusk
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
	_pivot.position = Vector3(0.0, FOLLOW_PIVOT_Y, 0.0)
	_pivot.rotation_degrees = Vector3(pivot_pitch, _yaw, 0.0)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL  # the iso-defining choice
	# Scale the ortho size up for the overscan so each texel still covers the same
	# world distance as an unpadded render — the visible framing is identical.
	_camera.size = cam_size * float(_padded.y) / float(render_size.y)
	# Ortho is distance-independent, so keep the camera near — a far camera makes
	# depth fog wash the whole frame.
	_camera.position = Vector3(0.0, 0.0, cam_distance)
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.current = true
	_pivot.add_child(_camera)
	# Depth-outline overlay rides the camera (full-screen quad in the transparent
	# pass; reads only DEPTH_TEXTURE). Fades out during active orbit.
	if outline_enabled:
		_camera.add_child(_make_outline_overlay())
	return _pivot


func _make_outline_overlay() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = load("res://assets/shaders/pixel_outline_t3.gdshader")
	_outline_mat.set_shader_parameter("view_size", Vector2(_padded))
	_outline_mat.set_shader_parameter("depth_threshold", outline_depth_threshold)
	_outline_mat.set_shader_parameter("normal_threshold", outline_normal_threshold)
	_outline_mat.set_shader_parameter("outline_color",
		Vector3(outline_color.r, outline_color.g, outline_color.b))
	_outline_mat.set_shader_parameter("outline_strength", outline_strength)
	var mi := MeshInstance3D.new()
	mi.name = "OutlineOverlay"
	mi.mesh = quad
	mi.material_override = _outline_mat
	mi.extra_cull_margin = 16384.0  # never frustum-culled (it is full-screen clip space)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
