extends Node3D
class_name Ring3World

## Ring 3 (The High Canopy) 3D playfield geometry — STARTED, not yet signed off
## (Phase 5: Ring 2 is the finished ring this session; Ring 3 is builder + measured
## palette + environment + one render check). Same contract as `Ring2World`:
## a `Node3D` terrain builder (`build(rig)`) that also carries `palette()` /
## `apply_environment(rig)` so `main` reconfigures the shared rig per ring.
##
## The High Canopy: "Watcher territory — vast elevated plateaus and towering
## formations. Cold, sparse, breathtaking ... carvings and records" (GDD). The
## concept art (`idea/the_high_canopy_concept_1.png`) is NOT cold blue — it is deep
## violet/indigo with pale frost highlights, dark carved monoliths, and warm GOLD
## glyph inscriptions. Palette is measured from it per `docs/RENDERING_3D.md`.
##
## KNOWN legibility item for sign-off: the pale frost-violet tones sit near the
## harmonic-lavender signal hue (`c0a0f0`); frost highlights can snap onto the
## signal. The top frost is greyed here to mitigate, but a dissonant/harmonic
## enemy render on Ring 3 ground is the gate before this ring is called done.
##
## Universal bounds (`sim_space.gd`): keeps the 28 x 22 walkable plateau.

# --- Measured High Canopy surface colours --------------------------------
const COL_LOWLAND := Color("11112f")    # deepest violet void below the plateaus
const COL_GROUND := Color("342d5b")     # walkable plateau (mid violet)
const COL_GROUND_DARK := Color("242049") # worn / shadow patches
const COL_FROST := Color("9a93b0")      # frost on the upper surfaces (greyed off the
                                        # harmonic signal — see header)
const COL_FROST_PALE := Color("d8d0ec") # brightest frost highlight
const COL_STONE := Color("2a224c")      # carved monolith stone
const COL_STONE_DARK := Color("18173a")
const COL_STONE_HI := Color("4a406f")   # lit monolith face
const COL_GLYPH := Color("c9a44e")      # warm gold inscription (the one warm accent)
const COL_FOG := Color("2d2955")        # violet haze (distance lerps)

var _rig: IsoRig


func palette() -> PackedStringArray:
	return PackedStringArray([
		"11112f", "18173a", "201b42", "242049",
		"2a224c", "2d2955", "342d5b", "3d325d",
		"4a406f", "6a5785", "8775b1", "9a93b0",
		"c9a44e", "d8d0ec",
		"c4547a", "c0a0f0",  # signal: dissonant pink, harmonic lavender
	])


## The warrior's ember/hem snap to the Canopy's gold glyph-light — faithful to the
## "THE SUMMONED WARRIOR" portrait's vertical gold ember-seam.
func ember_tint() -> Color:
	return Color("c9a44e")


func apply_environment(rig: IsoRig) -> void:
	rig.bg_color = Color("1b1a3e")        # deep violet sky
	rig.fog_color = COL_FOG               # violet aerial haze
	rig.fog_density = 0.005
	rig.ambient_color = Color("d2cfe4")   # pale cool fill (keeps albedo, slightly dim)
	rig.key_light_color = Color("b8bcd8") # cold key
	# pitch / rotation / cel bands stay at the rig defaults (universal iso look).


func build(rig: IsoRig) -> void:
	_rig = rig
	_build_terrain()


func _mat(col: Color) -> ShaderMaterial:
	return _rig.solid_material(col)


func _box(size: Vector3, col: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(col)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	return mi


func _build_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31  # Ring 3's own scatter seed
	# Walkable half-extents from the shared arena knob (SimSpace.PLAY_SCALE).
	var half := SimSpace.half_world()

	# --- The void below: a large deep-violet plane so far edges fade to haze. ---
	var land := CSGBox3D.new()
	var land_span := maxf(300.0, (maxf(half.x, half.y) + 90.0) * 2.0)
	land.size = Vector3(land_span, 2.0, land_span)
	land.position = Vector3(0.0, -6.0, 0.0)
	land.material = _mat(COL_LOWLAND)
	add_child(land)

	# --- Main elevated plateau (covers the full reachable footprint +-half) ---
	var plateau := CSGBox3D.new()
	plateau.size = Vector3(half.x * 2.0 + 2.0, 1.0, half.y * 2.0 + 2.0)
	plateau.position = Vector3(0.0, 0.0, 0.0)
	plateau.material = _mat(COL_GROUND)
	add_child(plateau)

	# Thin frost skim across the plateau top + worn patches.
	for n in range(8):
		var frosty := n % 3 == 0
		var patch := _box(
			Vector3(rng.randf_range(3.0, 6.5), 0.05, rng.randf_range(3.0, 6.5)),
			COL_FROST if frosty else COL_GROUND_DARK
		)
		patch.position = Vector3(rng.randf_range(-11.0, 11.0), 0.5, rng.randf_range(-8.5, 8.5))
		patch.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		add_child(patch)

	# --- A gold glyph alignment array inlaid in the plateau centre (the carvings) ---
	add_child(_make_glyph_array(Vector3(0.0, 0.52, 0.0)))

	# --- Towering carved monoliths around the rim (sparse, breathtaking) ---
	var monolith_spots := [
		Vector3(-11.0, 0.5, -8.0), Vector3(11.5, 0.5, -7.0), Vector3(-12.0, 0.5, 6.0),
		Vector3(12.0, 0.5, 7.0), Vector3(0.0, 0.5, -10.0), Vector3(-6.0, 0.5, 9.0),
	]
	for i in range(monolith_spots.size()):
		add_child(_make_monolith(monolith_spots[i], rng.randf_range(5.0, 9.0), rng))

	# --- A couple of secondary floating plateaus (the canopy reads as elevated) ---
	add_child(_make_subplateau(Vector3(-20.0, -2.0, -4.0), Vector3(9.0, 1.0, 9.0)))
	add_child(_make_subplateau(Vector3(19.0, -1.0, 3.0), Vector3(8.0, 1.0, 10.0)))

	# --- Sparse frost tufts (cold, not the dense flora of Ring 2) ---
	for n in range(16):
		var pos := Vector3(rng.randf_range(-12.0, 12.0), 0.5, rng.randf_range(-9.5, 9.5))
		if absf(pos.x) < 4.0 and absf(pos.z) < 4.0:
			continue
		add_child(_make_frost_tuft(pos, rng))

	# === EXPANSE FILL: the authored centre is the hub; populate the larger reach with
	# graduated-density frost/monoliths (sparse — the Canopy is cold) + outlying
	# landmarks as explore destinations. ===
	_fill_expanse(half)
	_add_outlying_landmarks(half)


func _make_glyph_array(pos: Vector3) -> Node3D:
	var arr := Node3D.new()
	arr.position = pos
	# A flat dark disc with gold concentric ring + radial spokes (the alignment array).
	var disc := CSGCylinder3D.new()
	disc.radius = 3.2
	disc.height = 0.08
	disc.material = _mat(COL_STONE_DARK)
	arr.add_child(disc)
	var ring := CSGCylinder3D.new()
	ring.radius = 2.6
	ring.height = 0.1
	ring.material = _mat(COL_GLYPH)
	arr.add_child(ring)
	var inner := CSGCylinder3D.new()
	inner.radius = 2.2
	inner.height = 0.12
	inner.position = Vector3(0.0, 0.01, 0.0)
	inner.material = _mat(COL_STONE_DARK)
	arr.add_child(inner)
	# Gold radial spokes.
	for i in range(6):
		var spoke := _box(Vector3(0.18, 0.11, 2.4), COL_GLYPH)
		spoke.position = Vector3(0.0, 0.02, 0.0)
		spoke.rotation_degrees.y = i * 30.0
		arr.add_child(spoke)
	return arr


func _make_monolith(base_pos: Vector3, height: float, rng: RandomNumberGenerator) -> Node3D:
	var mono := Node3D.new()
	mono.position = base_pos
	mono.rotation_degrees.y = rng.randf_range(0.0, 45.0)
	var w := rng.randf_range(1.4, 2.2)
	var shaft := _box(Vector3(w, height, w * 0.8), COL_STONE)
	shaft.position = Vector3(0.0, height * 0.5, 0.0)
	mono.add_child(shaft)
	# Lit face stripe + gold glyph bands carved up the shaft.
	var face := _box(Vector3(w * 0.55, height * 0.92, 0.06), COL_STONE_HI)
	face.position = Vector3(0.0, height * 0.5, w * 0.42)
	mono.add_child(face)
	var bands := int(height / 1.4)
	for b in range(bands):
		var glyph := _box(Vector3(w * 0.5, 0.16, 0.08), COL_GLYPH)
		glyph.position = Vector3(0.0, 1.0 + b * 1.4, w * 0.42)
		mono.add_child(glyph)
	# Frost cap on top.
	var cap := _box(Vector3(w * 1.05, 0.18, w * 0.85), COL_FROST_PALE)
	cap.position = Vector3(0.0, height + 0.09, 0.0)
	mono.add_child(cap)
	return mono


func _make_subplateau(pos: Vector3, size: Vector3) -> Node3D:
	var sub := Node3D.new()
	sub.position = pos
	var slab := CSGBox3D.new()
	slab.size = size
	slab.material = _mat(COL_GROUND.lerp(COL_FOG, 0.3))
	sub.add_child(slab)
	# Frost skim on top.
	var skim := _box(Vector3(size.x * 0.8, 0.06, size.z * 0.8), COL_FROST)
	skim.position = Vector3(0.0, size.y * 0.5 + 0.03, 0.0)
	sub.add_child(skim)
	return sub


func _make_frost_tuft(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var tuft := Node3D.new()
	tuft.position = pos
	for i in range(rng.randi_range(3, 5)):
		var h := rng.randf_range(0.3, 0.7)
		var blade := _box(Vector3(0.06, h, 0.06), COL_FROST if rng.randf() < 0.6 else COL_FROST_PALE)
		blade.position = Vector3(rng.randf_range(-0.15, 0.15), h * 0.5, rng.randf_range(-0.15, 0.15))
		blade.rotation_degrees = Vector3(
			rng.randf_range(-12.0, 12.0), rng.randf_range(0.0, 360.0), rng.randf_range(-12.0, 12.0)
		)
		tuft.add_child(blade)
	return tuft


# World radius of the authored central area, kept clear by the expanse fill.
const HUB := 13.0


# Graduated-density scatter across the plateau (cold + sparse). Own RNG (seed 41) so
# the authored seed-31 layout is byte-for-byte unchanged.
func _fill_expanse(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var area := half.x * half.y
	for n in range(clampi(int(area * 0.05), 40, 200)):
		var p := SimSpace.scatter_point(rng, half, HUB)
		if p != Vector3.INF:
			add_child(_make_frost_tuft(p, rng))
	for n in range(clampi(int(area * 0.01), 8, 44)):
		var p := SimSpace.scatter_point(rng, half, HUB)
		if p != Vector3.INF:
			add_child(_make_monolith(p, rng.randf_range(4.0, 8.0), rng))
	for n in range(clampi(int(area * 0.02), 16, 80)):
		var p := SimSpace.scatter_point(rng, half, HUB)
		if p == Vector3.INF:
			continue
		var sz := rng.randf_range(0.3, 0.7)
		var chunk := _box(Vector3(sz, sz * 0.6, sz), COL_STONE if n % 2 == 0 else COL_STONE_DARK)
		chunk.position = p + Vector3(0.0, sz * 0.3, 0.0)
		chunk.rotation_degrees = Vector3(rng.randf_range(-10.0, 10.0), rng.randf_range(0.0, 90.0), rng.randf_range(-10.0, 10.0))
		add_child(chunk)


# A few monoliths / sunken terraces / glyph arrays out in the reach as destinations.
func _add_outlying_landmarks(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var ring_r := minf(half.x, half.y)
	for i in range(5):
		var ang := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var r := ring_r * rng.randf_range(0.5, 0.85)
		var pos := Vector3(cos(ang) * r, 0.5, sin(ang) * r)
		var kind := i % 3
		if kind == 0:
			add_child(_make_monolith(pos, rng.randf_range(6.0, 10.0), rng))
		elif kind == 1:
			add_child(_make_subplateau(pos + Vector3(0.0, -2.0, 0.0), Vector3(rng.randf_range(7.0, 11.0), 1.0, rng.randf_range(7.0, 11.0))))
		else:
			add_child(_make_glyph_array(pos + Vector3(0.0, 0.02, 0.0)))
