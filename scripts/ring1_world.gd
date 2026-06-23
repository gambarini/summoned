extends Node3D
class_name Ring1World

## Ring 1 (The Pale Reaches) 3D playfield geometry — the cel-shaded blockout that
## replaces the old 2D tilemap ground (`scripts/ground_layer.gd`) and 2D prop
## sprites. Mounts under an `IsoRig`: build it, then `rig.add_world_child(world)`.
##
## This is a faithful port of the proven spike's terrain (`ring1_iso_test.gd`):
## the construction order and `rng.seed = 7` are preserved byte-for-byte so the
## scatter layout matches the spike baselines (`docs/gen/ring1_iso_spike*.png`).
## The only change from the spike is that materials come from the rig's shared
## `solid_material()` (one cel-shader source) instead of a local factory.
##
## Terrain = CSG/BoxMesh greybox; at the iso distance, silhouette + palette +
## soft shading is the concept. See `docs/RENDERING_3D.md`.

# Pale Reaches surface colours, measured off the Ring 1 concept art.
const COL_GROUND := Color("7c8591")     # measured open ground
const COL_GROUND_LOW := Color("4c5a6d") # measured cliff/lowland
const COL_PATH := Color("98a0a8")       # pale cool trail
const COL_STONE := Color("667383")      # measured dome
const COL_STONE_DARK := Color("4c5a6d")
const COL_FLORA := Color("828d9b")
const COL_FLORA2 := Color("6e7a89")
const COL_PALE := Color("cbd2d3")
const COL_DOORWAY := Color("c89a5e")    # warm pinpoint (concept doorway)
const COL_FOG := Color("5a697d")        # measured sky/haze (used in distance lerps)

# Tiling pixel-art textures (cel_triplanar, world-space). Authored at measured
# Ring 1 values; per-surface tint scales them to same-hue variants. One scale per
# family keeps texel density consistent across objects. See memory look_match_spike.
const STONE_TEX := "res://assets/textures/stone_pale.png"
const STONE_SCALE := 0.32   # tiles/world-unit for ALL stone (constant block size)
const GROUND_TEX := "res://assets/textures/ground_tile.png"
const GROUND_SCALE := 0.4    # one scale for ALL ground/path

# Walkable ground (plateau/paths) uses the shared dusty-rock recipe (flat cel colour +
# macro value-drift + scattered decals) via `GroundStyle`. Cliffs + stone ruins keep
# their tiling textures (peripheral / coarse masonry). See docs/RENDERING_3D.md.
var _rig: IsoRig


## Reconfigure the rig's environment for the Pale Reaches atmosphere pass: the
## world dissolves into pale haze at distance and the near-white ambient fill
## drops so the key light + fog model the dusk, instead of the flat-lit "diamond
## floating on grey" read. Proven in the look-match spike (memory look_match_spike).
## Call BEFORE the rig enters the tree (it builds its pipeline lazily on _ready).
## Palette stays the rig default (the measured Ring 1 ramp).
func apply_environment(rig: IsoRig) -> void:
	rig.bg_color = Color("505d70")   # deeper than the haze so distance reads as depth
	rig.fog_color = COL_FOG          # measured pale sky/haze (5a697d)
	rig.fog_density = 0.008          # ~2x the rig default — far lowland still fades, near stays clear
	rig.ambient_energy = 0.42        # slightly deeper fill so shadow sides drop and forms gain contrast
	rig.vignette_strength = 0.18     # light corner settle, not a murky frame (was 0.35 — read as gloom)


## Populate this node with the Ring 1 terrain + props, drawing cel materials from
## `rig`. Call before mounting (`rig.add_world_child(world)`); no tree required.
func build(rig: IsoRig) -> void:
	_rig = rig
	_build_terrain()
	GroundStyle.scatter_decals(self, _rig, SimSpace.half_world(), COL_GROUND)


func _mat(col: Color) -> ShaderMaterial:
	return _rig.solid_material(col)


# A world-space triplanar cel material: a tiling texture (authored at its base
# colour) tinted to a same-hue variant. Big surfaces only; tiny props stay on _mat.
func _tex_mat(tex_path: String, tint: Color, scale: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/cel_triplanar.gdshader")
	m.set_shader_parameter("albedo_tex", load(tex_path))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("texture_scale", scale)
	m.set_shader_parameter("bands", _rig.cel_bands)
	m.set_shader_parameter("light_gain", _rig.cel_light_gain)
	return m


# Tint that maps a texture authored at `base` to a same-hue `target` (value scale).
func _tint_for(target: Color, base: Color) -> Color:
	return Color(target.r / base.r, target.g / base.g, target.b / base.b)


# Lightweight box prop (MeshInstance3D, not CSG) for the many small details.
func _box(size: Vector3, col: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(col)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	return mi


func _build_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Walkable half-extents (world units) from the shared arena knob (SimSpace.
	# PLAY_SCALE). All terrain extents derive from this, so the ground always covers
	# the warrior's reachable footprint at any PLAY_SCALE (was a fixed 28x22 plateau).
	var half := SimSpace.half_world()

	# --- Surrounding lowland: a large flat plane that recedes into pale haze instead
	# of a void. Sized well beyond the plateau so its edge always drops into distance,
	# even at large PLAY_SCALE. ---
	var land := CSGBox3D.new()
	var land_span := maxf(300.0, (maxf(half.x, half.y) + 90.0) * 2.0)
	land.size = Vector3(land_span, 2.0, land_span)
	land.position = Vector3(0.0, -2.6, 0.0)
	# Lowland stays FLAT: its job is to recede into haze (fog + vignette do that).
	land.material = _mat(COL_GROUND_LOW)
	add_child(land)

	# --- Plateau the tribe shelters on ---
	# Width (x) is 28, not the play-area-derived 26.67: at PPU=18 the warrior's body
	# centre reaches x=+-13.0 world (480/270 roam box minus its 6px half-width), which
	# is exactly the +-13 lip of a 26-wide plateau, so it teeters on the edge at the
	# x-extremes (Phase 5 bounds capture: docs/gen/bounds_corner_*). 28 gives ~1u of
	# ground margin. Depth (z) already has ~4u of slack (warrior reaches z=+-6.94 vs
	# the +-11 plateau), so only x needs the nudge. See MIGRATION_3D Phase 5.
	var plateau := CSGBox3D.new()
	# Cover the full reachable footprint (+-half) with ~1u margin each side so the
	# warrior never teeters on the lip.
	plateau.size = Vector3(half.x * 2.0 + 2.0, 1.0, half.y * 2.0 + 2.0)
	plateau.position = Vector3(0.0, 0.0, 0.0)
	plateau.material = GroundStyle.ground_mat(_rig, COL_GROUND)
	add_child(plateau)

	# (The old 18 textured "worn patches" that broke up the slab are gone — the smooth
	# macro value-drift on the plateau material now supplies that broad mottle, and the
	# scattered decals (_scatter_ground_decals) supply the stone/crack detail.)

	# --- Stratified cliff descending off the plateau's front edge (relocated to the
	# real perimeter at explore-scale; was the old +-12 edge). ---
	_add_cliff(Vector3(-half.x * 0.45, 0.0, half.y - 1.0))

	# --- Carved stairway up the plateau edge (front) ---
	add_child(_make_stairs(Vector3(5.5, 0.5, 9.5), 5))

	# --- Winding path (two angled flat strips of pale dirt) ---
	var path_a := CSGBox3D.new()
	path_a.size = Vector3(2.0, 0.12, 11.0)
	path_a.position = Vector3(-2.0, 0.52, 2.0)
	path_a.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	path_a.material = GroundStyle.ground_mat(_rig, COL_PATH)
	add_child(path_a)

	var path_b := CSGBox3D.new()
	path_b.size = Vector3(2.0, 0.12, 8.0)
	path_b.position = Vector3(1.5, 0.52, -5.0)
	path_b.rotation_degrees = Vector3(0.0, -22.0, 0.0)
	path_b.material = GroundStyle.ground_mat(_rig, COL_PATH)
	add_child(path_b)

	# --- Domed observatory (back-centre), with a warm-lit doorway ---
	add_child(_make_domed_ruin(Vector3(2.0, 0.5, -7.5), 2.4, true))
	# --- Second, smaller dome (right) ---
	add_child(_make_domed_ruin(Vector3(9.0, 0.5, -1.0), 1.8, false))

	# --- A broken arch (left) ---
	add_child(_make_arch(Vector3(-8.0, 0.5, -3.0)))

	# --- Bunting strung across the camp (the Singers are here) ---
	add_child(_make_bunting(Vector3(-5.0, 0.5, 4.0), Vector3(-1.0, 0.5, -1.0)))
	add_child(_make_bunting(Vector3(-1.0, 0.5, -1.0), Vector3(4.0, 0.5, -3.5)))
	add_child(_make_bunting(Vector3(4.0, 0.5, -3.5), Vector3(6.5, 0.5, 1.0)))

	# --- Grass tufts and pale flora, clustered along edges and ruins ---
	for n in range(34):
		var tuft := _make_grass_tuft(
			Vector3(rng.randf_range(-11.0, 11.0), 0.5, rng.randf_range(-9.0, 9.0)), rng
		)
		add_child(tuft)

	# --- A little scattered rubble near the ruins ---
	for n in range(8):
		var s := rng.randf_range(0.3, 0.6)
		var chunk := _box(Vector3(s, s * 0.6, s), COL_STONE_DARK)
		chunk.position = Vector3(rng.randf_range(-9.0, 9.0), 0.5 + s * 0.3, rng.randf_range(-7.0, 7.0))
		chunk.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 90.0), 0.0)
		add_child(chunk)

	# --- Density pass (look-match step 3): the concept is CROWDED. Layer extra
	# flora (three silhouettes) + debris, rejecting the central walkable band so
	# combat signals stay legible. Own rng (seed 13) so the baseline scatter above
	# is byte-for-byte unchanged. ---
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 13
	for n in range(46):
		var gp := Vector3(rng2.randf_range(-12.0, 12.0), 0.5, rng2.randf_range(-9.5, 9.5))
		if _is_central(gp):
			continue
		add_child(_make_grass_tuft(gp, rng2))
	for n in range(16):
		var rp := Vector3(rng2.randf_range(-12.0, 12.0), 0.5, rng2.randf_range(-9.5, 9.5))
		if _is_central(rp):
			continue
		add_child(_make_reed(rp, rng2))
	for n in range(12):
		var fp := Vector3(rng2.randf_range(-11.5, 11.5), 0.5, rng2.randf_range(-9.0, 9.0))
		if _is_central(fp):
			continue
		add_child(_make_flower(fp, rng2))
	for n in range(12):
		var s2 := rng2.randf_range(0.25, 0.55)
		var chunk2 := _box(Vector3(s2, s2 * 0.6, s2), COL_STONE_DARK if n % 2 == 0 else COL_STONE)
		chunk2.position = Vector3(rng2.randf_range(-10.0, 10.0), 0.5 + s2 * 0.3, rng2.randf_range(-8.0, 8.0))
		chunk2.rotation_degrees = Vector3(rng2.randf_range(-12.0, 12.0), rng2.randf_range(0.0, 90.0), rng2.randf_range(-12.0, 12.0))
		add_child(chunk2)

	# === EXPANSE FILL: the home hub above is dense; now populate the much larger
	# reach out to the edges with graduated-density flora/debris (thinning toward the
	# haze) plus a few outlying ruins as explore landmarks. ===
	_fill_expanse(half)
	_add_outlying_landmarks(half)


# Central walkable band kept clear so enemy/warrior signals stay legible.
func _is_central(p: Vector3) -> bool:
	return absf(p.x) < 4.5 and absf(p.z) < 4.0


# A tall pale reed / dead stalk — a second flora silhouette for variety.
func _make_reed(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var reed := Node3D.new()
	reed.position = pos
	var h := rng.randf_range(1.2, 2.3)
	var w := rng.randf_range(0.06, 0.12)
	var col := COL_FLORA2 if rng.randf() < 0.5 else COL_FLORA
	var stalk := _box(Vector3(w, h, w), col.lerp(COL_GROUND, rng.randf() * 0.3))
	stalk.position = Vector3(0.0, h * 0.5, 0.0)
	stalk.rotation_degrees = Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(0.0, 360.0), rng.randf_range(-8.0, 8.0))
	reed.add_child(stalk)
	if rng.randf() < 0.6:
		var bud := _box(Vector3(w * 2.0, w * 2.5, w * 2.0), COL_PALE)
		bud.position = Vector3(0.0, h * 0.96, 0.0)
		reed.add_child(bud)
	return reed


# A small pale flower — a tiny bright accent (the concept's pale blooms).
func _make_flower(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var flower := Node3D.new()
	flower.position = pos
	var h := rng.randf_range(0.35, 0.7)
	var stalk := _box(Vector3(0.04, h, 0.04), COL_FLORA2)
	stalk.position = Vector3(0.0, h * 0.5, 0.0)
	flower.add_child(stalk)
	var head := _box(Vector3(0.14, 0.14, 0.14), COL_PALE)
	head.position = Vector3(0.0, h + 0.05, 0.0)
	flower.add_child(head)
	return flower


func _make_stairs(base_pos: Vector3, steps: int) -> Node3D:
	var stair := Node3D.new()
	stair.position = base_pos
	for i in range(steps):
		var s := _box(Vector3(3.0, 0.3, 0.7), COL_STONE.lerp(COL_GROUND, 0.4))
		s.position = Vector3(0.0, -0.15 - i * 0.3, 0.7 + i * 0.7)
		stair.add_child(s)
	return stair


func _make_grass_tuft(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var tuft := Node3D.new()
	tuft.position = pos
	var base := COL_FLORA2 if rng.randf() < 0.3 else COL_FLORA  # pale cool variation
	for i in range(rng.randi_range(4, 7)):
		var h := rng.randf_range(0.4, 0.95)
		var blade := _box(Vector3(0.05, h, 0.05), base.lerp(COL_GROUND, rng.randf() * 0.35))
		blade.position = Vector3(rng.randf_range(-0.2, 0.2), h * 0.5, rng.randf_range(-0.2, 0.2))
		blade.rotation_degrees = Vector3(
			rng.randf_range(-18.0, 18.0), rng.randf_range(0.0, 360.0), rng.randf_range(-18.0, 18.0)
		)
		tuft.add_child(blade)
	return tuft


func _make_bunting(a: Vector3, b: Vector3) -> Node3D:
	var n := Node3D.new()
	# Posts at each end.
	for p in [a, b]:
		var post := _box(Vector3(0.18, 3.0, 0.18), COL_STONE_DARK)
		post.position = p + Vector3(0.0, 1.5, 0.0)
		n.add_child(post)
	# Drooping line: two segments to a sagged midpoint.
	var top_a := a + Vector3(0.0, 2.9, 0.0)
	var top_b := b + Vector3(0.0, 2.9, 0.0)
	var mid := (top_a + top_b) * 0.5 + Vector3(0.0, -0.5, 0.0)
	n.add_child(_line_segment(top_a, mid, COL_STONE_DARK))
	n.add_child(_line_segment(mid, top_b, COL_STONE_DARK))
	# Triangular-ish flags hanging along the line, alternating warm / pale.
	_hang_flags(n, top_a, mid)
	_hang_flags(n, mid, top_b)
	return n


func _line_segment(p: Vector3, q: Vector3, col: Color) -> MeshInstance3D:
	var seg := _box(Vector3(0.04, 0.04, p.distance_to(q)), col)
	var d := (q - p).normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x := up.cross(d).normalized()
	var y := d.cross(x).normalized()
	seg.transform = Transform3D(Basis(x, y, d), (p + q) * 0.5)
	return seg


func _hang_flags(parent: Node3D, p: Vector3, q: Vector3) -> void:
	var count := maxi(2, int(p.distance_to(q) / 0.55))
	for i in range(1, count):
		var pos := p.lerp(q, float(i) / count)
		var col := COL_PALE if i % 2 == 0 else COL_FLORA  # muted cool flags
		var flag := _box(Vector3(0.34, 0.42, 0.02), col)
		flag.position = pos + Vector3(0.0, -0.26, 0.0)
		flag.rotation_degrees.x = 12.0
		parent.add_child(flag)


func _make_domed_ruin(base_pos: Vector3, radius: float, lit_doorway: bool) -> Node3D:
	var ruin := Node3D.new()
	ruin.position = base_pos

	var drum := CSGCylinder3D.new()
	drum.radius = radius
	drum.height = radius * 1.1
	drum.position = Vector3(0.0, radius * 0.55, 0.0)
	drum.material = _tex_mat(STONE_TEX, Color.WHITE, STONE_SCALE)
	ruin.add_child(drum)

	# Faceted dome (low segment count reads as built panels, not a balloon).
	var dome := CSGSphere3D.new()
	dome.radius = radius
	dome.radial_segments = 8
	dome.rings = 4
	dome.position = Vector3(0.0, radius * 1.1, 0.0)
	dome.material = _tex_mat(STONE_TEX, _tint_for(COL_STONE.lerp(COL_PALE, 0.12), COL_STONE), STONE_SCALE)
	ruin.add_child(dome)

	# Structural ring band where dome meets drum.
	var band := CSGCylinder3D.new()
	band.radius = radius * 1.06
	band.height = 0.3
	band.position = Vector3(0.0, radius * 1.1, 0.0)
	band.material = _tex_mat(STONE_TEX, _tint_for(COL_STONE_DARK, COL_STONE), STONE_SCALE)
	ruin.add_child(band)

	# Finial spire on top.
	var spire := _box(Vector3(0.18, radius * 0.7, 0.18), COL_STONE_DARK)
	spire.position = Vector3(0.0, radius * 2.0 + radius * 0.35, 0.0)
	ruin.add_child(spire)

	# Arched doorway: dark recess + a stone surround.
	var door := CSGBox3D.new()
	door.size = Vector3(radius * 0.5, radius * 0.85, 0.7)
	door.position = Vector3(0.0, radius * 0.42, radius * 0.95)
	door.material = _mat(Color("10131a"))
	ruin.add_child(door)
	var lintel := _box(Vector3(radius * 0.72, 0.25, 0.3), COL_STONE_DARK)
	lintel.position = Vector3(0.0, radius * 0.88, radius * 1.0)
	ruin.add_child(lintel)

	if lit_doorway:
		var glow := OmniLight3D.new()
		glow.light_color = COL_DOORWAY
		glow.light_energy = 9.0
		glow.omni_range = radius * 4.0
		glow.position = Vector3(0.0, radius * 0.4, radius * 1.1)
		ruin.add_child(glow)

	return ruin


func _make_arch(base_pos: Vector3) -> Node3D:
	var arch := Node3D.new()
	arch.position = base_pos
	var mat := _tex_mat(STONE_TEX, _tint_for(COL_STONE_DARK, COL_STONE), STONE_SCALE)
	for dx in [-1.4, 1.4]:
		var pillar := CSGBox3D.new()
		pillar.size = Vector3(0.8, 4.0, 0.8)
		pillar.position = Vector3(dx, 2.0, 0.0)
		pillar.material = mat
		arch.add_child(pillar)
	var lintel := CSGBox3D.new()
	lintel.size = Vector3(3.6, 0.8, 0.8)
	lintel.position = Vector3(0.0, 4.0, 0.0)
	lintel.material = mat
	arch.add_child(lintel)
	# A broken-off stub on top, suggesting ruin.
	var stub := _box(Vector3(0.8, 1.2, 0.8), COL_STONE_DARK)
	stub.position = Vector3(-1.4, 5.0, 0.0)
	stub.rotation_degrees.z = 8.0
	arch.add_child(stub)
	return arch


# World radius of the authored central camp, kept clear by the expanse fill so the
# hand-composed hub and the procedural reach don't double up.
const HUB := 13.0


# Stratified cliff descending off a plateau edge, built relative to `origin` (was an
# inline block at the old +-12 edge; now placed at the real perimeter so it reads as
# the mesa falling away into haze).
func _add_cliff(origin: Vector3) -> void:
	for i in range(4):
		var w := 12.0 - i * 2.0
		var base_y := -1.0 - i * 1.2
		var step := CSGBox3D.new()
		step.size = Vector3(w, 1.0, 6.0)
		step.position = origin + Vector3(-i * 1.2, base_y, i * 2.0)
		step.material = _tex_mat(GROUND_TEX, _tint_for(COL_GROUND_LOW.lerp(COL_FOG, i * 0.2), COL_GROUND), GROUND_SCALE)
		add_child(step)
		for s in range(2):
			var band := _box(Vector3(w + 0.1, 0.18, 6.1), COL_STONE_DARK.lerp(COL_FOG, i * 0.25))
			band.position = origin + Vector3(-i * 1.2, base_y - 0.25 - s * 0.4, i * 2.0)
			add_child(band)


# Graduated-density scatter across the plateau: dense just outside the home hub,
# thinning to sparse at the rim so the reach fades into haze rather than ending in a
# hard prop wall. Budgets scale with area but are capped so node count (FPS) stays
# sane. Own RNG (seed 21) so the hub's seed-7/13 layout is byte-for-byte unchanged.
func _fill_expanse(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var area := half.x * half.y
	for n in range(clampi(int(area * 0.12), 80, 380)):
		var p := _expanse_point(rng, half)
		if p != Vector3.INF:
			add_child(_make_grass_tuft(p, rng))
	for n in range(clampi(int(area * 0.04), 30, 130)):
		var p := _expanse_point(rng, half)
		if p != Vector3.INF:
			add_child(_make_reed(p, rng))
	for n in range(clampi(int(area * 0.03), 20, 100)):
		var p := _expanse_point(rng, half)
		if p != Vector3.INF:
			add_child(_make_flower(p, rng))
	for n in range(clampi(int(area * 0.04), 30, 130)):
		var p := _expanse_point(rng, half)
		if p == Vector3.INF:
			continue
		var sz := rng.randf_range(0.3, 0.7)
		var chunk := _box(Vector3(sz, sz * 0.6, sz), COL_STONE_DARK if n % 2 == 0 else COL_STONE)
		chunk.position = p + Vector3(0.0, sz * 0.3, 0.0)
		chunk.rotation_degrees = Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(0.0, 90.0), rng.randf_range(-12.0, 12.0))
		add_child(chunk)


# A candidate scatter point inside +-half (small inset), accepted with probability
# that falls off with distance from centre (dense near the hub, sparse at the rim).
# Rejects the authored hub footprint and returns Vector3.INF when rejected.
func _expanse_point(rng: RandomNumberGenerator, half: Vector2) -> Vector3:
	var x := rng.randf_range(-half.x + 0.5, half.x - 0.5)
	var z := rng.randf_range(-half.y + 0.5, half.y - 0.5)
	var d := Vector2(x, z).length()
	if d < HUB:
		return Vector3.INF
	var max_d := half.length()
	var t := clampf(1.0 - (d - HUB) / maxf(1.0, max_d - HUB), 0.15, 1.0)
	if rng.randf() > t:
		return Vector3.INF
	return Vector3(x, 0.5, z)


# A few ruins out in the reach (beyond the hub, clear of the rim) so exploration has
# destinations: a dome on the horizon to walk toward. Reuses the hub's ruin makers.
func _add_outlying_landmarks(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var ring_r := minf(half.x, half.y)
	var count := 5
	for i in range(count):
		var ang := TAU * float(i) / float(count) + rng.randf_range(-0.3, 0.3)
		var r := ring_r * rng.randf_range(0.5, 0.85)
		var pos := Vector3(cos(ang) * r, 0.5, sin(ang) * r)
		var kind := i % 3
		if kind == 0:
			add_child(_make_domed_ruin(pos, rng.randf_range(1.6, 2.6), rng.randf() < 0.5))
		elif kind == 1:
			add_child(_make_arch(pos))
		else:
			for s in range(rng.randi_range(3, 5)):
				var h := rng.randf_range(2.0, 4.0)
				var stone := _box(Vector3(rng.randf_range(0.6, 1.0), h, rng.randf_range(0.6, 1.0)), COL_STONE_DARK)
				stone.position = pos + Vector3(rng.randf_range(-2.5, 2.5), h * 0.5 - 0.5, rng.randf_range(-2.5, 2.5))
				stone.rotation_degrees = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(0.0, 90.0), rng.randf_range(-6.0, 6.0))
				add_child(stone)
