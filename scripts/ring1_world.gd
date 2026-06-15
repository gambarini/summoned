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

var _rig: IsoRig


## Populate this node with the Ring 1 terrain + props, drawing cel materials from
## `rig`. Call before mounting (`rig.add_world_child(world)`); no tree required.
func build(rig: IsoRig) -> void:
	_rig = rig
	_build_terrain()


func _mat(col: Color) -> ShaderMaterial:
	return _rig.solid_material(col)


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

	# --- Surrounding lowland: a large plane so terrain fills the frame at any
	# camera angle and fades into pale haze instead of a void. ---
	var land := CSGBox3D.new()
	land.size = Vector3(300.0, 2.0, 300.0)
	land.position = Vector3(0.0, -2.6, 0.0)
	land.material = _mat(COL_GROUND_LOW)
	add_child(land)

	# --- Plateau the tribe shelters on ---
	var plateau := CSGBox3D.new()
	plateau.size = Vector3(26.0, 1.0, 22.0)
	plateau.position = Vector3(0.0, 0.0, 0.0)
	plateau.material = _mat(COL_GROUND)
	add_child(plateau)

	# Worn ground patches break the flat single colour.
	for n in range(7):
		var patch := _box(
			Vector3(rng.randf_range(3.0, 6.0), 0.06, rng.randf_range(3.0, 6.0)),
			COL_GROUND_LOW if n % 2 == 0 else COL_GROUND.lerp(COL_PATH, 0.25)
		)
		patch.position = Vector3(rng.randf_range(-10.0, 10.0), 0.5, rng.randf_range(-8.0, 8.0))
		patch.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		add_child(patch)

	# --- Stratified cliff descending off the front-left edge ---
	for i in range(3):
		var w := 10.0 - i * 2.0
		var base_y := -1.0 - i * 1.2
		var step := CSGBox3D.new()
		step.size = Vector3(w, 1.0, 6.0)
		step.position = Vector3(-9.0 - i * 1.5, base_y, 8.0 + i * 1.0)
		step.material = _mat(COL_GROUND_LOW.lerp(COL_FOG, i * 0.2))
		add_child(step)
		# Rock strata: thin darker bands on the cliff face.
		for s in range(2):
			var band := _box(Vector3(w + 0.1, 0.18, 6.1), COL_STONE_DARK.lerp(COL_FOG, i * 0.25))
			band.position = Vector3(-9.0 - i * 1.5, base_y - 0.25 - s * 0.4, 8.0 + i * 1.0)
			add_child(band)

	# --- Carved stairway up the plateau edge (front) ---
	add_child(_make_stairs(Vector3(5.5, 0.5, 9.5), 5))

	# --- Winding path (two angled flat strips of pale dirt) ---
	var path_a := CSGBox3D.new()
	path_a.size = Vector3(2.0, 0.12, 11.0)
	path_a.position = Vector3(-2.0, 0.52, 2.0)
	path_a.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	path_a.material = _mat(COL_PATH)
	add_child(path_a)

	var path_b := CSGBox3D.new()
	path_b.size = Vector3(2.0, 0.12, 8.0)
	path_b.position = Vector3(1.5, 0.52, -5.0)
	path_b.rotation_degrees = Vector3(0.0, -22.0, 0.0)
	path_b.material = _mat(COL_PATH)
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
	drum.material = _mat(COL_STONE)
	ruin.add_child(drum)

	# Faceted dome (low segment count reads as built panels, not a balloon).
	var dome := CSGSphere3D.new()
	dome.radius = radius
	dome.radial_segments = 8
	dome.rings = 4
	dome.position = Vector3(0.0, radius * 1.1, 0.0)
	dome.material = _mat(COL_STONE.lerp(COL_PALE, 0.12))
	ruin.add_child(dome)

	# Structural ring band where dome meets drum.
	var band := CSGCylinder3D.new()
	band.radius = radius * 1.06
	band.height = 0.3
	band.position = Vector3(0.0, radius * 1.1, 0.0)
	band.material = _mat(COL_STONE_DARK)
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
	var mat := _mat(COL_STONE_DARK)
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
