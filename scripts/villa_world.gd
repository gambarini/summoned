extends Node3D
class_name VillaWorld

## The Villa (the tribe's home) 3D playfield geometry — the between-runs base, now a
## low-res 3D iso scene like the rings instead of the old 2D diorama. Same contract
## as the ring builders: a `Node3D` terrain builder (`build(rig)`) that also carries
## `apply_environment(rig)` so `base` can reconfigure the shared rig. Unlike the rings
## there is no roaming warrior, so the rig's follow camera stays disabled (centred on
## the villa at the origin) and the player only orbits.
##
## The tribe shelters in the Pale Reaches (Ring 1's place), so the palette is the rig
## default (the measured Pale Reaches ramp). The villa reads as an inhabited camp:
## a central ceremony dais where Anthe sings the summoning (the warm summon-glow), the
## Singers' bunting, a ring of dwellings (tents + a stone hall), and Anthe herself as
## a small cel-shaded robed figure on the dais. See `docs/RENDERING_3D.md`.

# Pale Reaches surface colours (shared with Ring 1).
const COL_GROUND := Color("7c8591")
const COL_GROUND_LOW := Color("4c5a6d")
const COL_PATH := Color("98a0a8")
const COL_STONE := Color("667383")
const COL_STONE_DARK := Color("4c5a6d")
const COL_FLORA := Color("828d9b")
const COL_FLORA2 := Color("6e7a89")
const COL_PALE := Color("cbd2d3")
const COL_TENT := Color("8a7d6a")        # warm canvas (the dwellings)
const COL_TENT2 := Color("6e6354")       # canvas in shadow
const COL_HEARTH := Color("d4803a")      # warm summon / hearth glow
# Anthe the summoner: a violet robe (the "normal summoning" hue) + pale head.
const COL_ANTHE_ROBE := Color("7b4ea0")
const COL_ANTHE_ROBE_DK := Color("563670")
const COL_ANTHE_PALE := Color("e6dcc8")

var _rig: IsoRig


## Warm, sheltered dusk for the home camp: Ring 1's pale haze but a touch warmer and
## cosier (the hearth), with a gentle vignette. Call BEFORE the rig enters the tree.
func apply_environment(rig: IsoRig) -> void:
	rig.bg_color = Color("4a5365")
	rig.fog_color = Color("5a697d")
	rig.fog_density = 0.007
	rig.ambient_color = Color("e8e0d4")  # warm-tinted fill (the camp is lived-in)
	rig.ambient_energy = 0.5
	rig.vignette_strength = 0.22


func build(rig: IsoRig) -> void:
	_rig = rig
	_build_villa()
	# Dusty-rock ground recipe (shared). Villa plateau is a fixed 40x32, so pass its
	# half-extents (20x16) — slightly inset so decals stay on the slab.
	GroundStyle.scatter_decals(self, _rig, Vector2(19.0, 15.0), COL_GROUND)


func _mat(col: Color) -> ShaderMaterial:
	return _rig.solid_material(col)


func _box(size: Vector3, col: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(col)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	return mi


func _build_villa() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91

	# --- Surrounding lowland fading to haze. ---
	var land := CSGBox3D.new()
	land.size = Vector3(300.0, 2.0, 300.0)
	land.position = Vector3(0.0, -2.6, 0.0)
	land.material = _mat(COL_GROUND_LOW)
	add_child(land)

	# --- The camp ground (a sheltered plateau). Sized to fill the iso frame. ---
	var plateau := CSGBox3D.new()
	plateau.size = Vector3(40.0, 1.0, 32.0)
	plateau.position = Vector3(0.0, 0.0, 0.0)
	plateau.material = GroundStyle.ground_mat(_rig, COL_GROUND)
	add_child(plateau)

	# Worn ground patches.
	for n in range(8):
		var patch := _box(
			Vector3(rng.randf_range(3.0, 6.0), 0.06, rng.randf_range(3.0, 6.0)),
			COL_GROUND_LOW if n % 2 == 0 else COL_GROUND.lerp(COL_PATH, 0.25)
		)
		patch.position = Vector3(rng.randf_range(-14.0, 14.0), 0.5, rng.randf_range(-11.0, 11.0))
		patch.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		add_child(patch)

	# --- Central ceremony dais: a tiered stone disc with a warm summon-glow, where
	# Anthe sings the warrior into the world. ---
	add_child(_make_dais(Vector3(0.0, 0.5, 0.0)))
	add_child(_make_anthe(Vector3(0.9, 0.95, 1.0)))  # standing on the dais, off-centre

	# --- Radial path stones leading out from the dais (the procession). ---
	for i in range(6):
		var path := _box(Vector3(1.4, 0.1, 7.0), COL_PATH)
		path.position = Vector3(0.0, 0.53, 0.0)
		path.rotation_degrees.y = i * 60.0 + 15.0
		add_child(path)

	# --- A ring of dwellings around the camp: tents + one stone hall. ---
	var dwell := [
		[Vector3(-11.0, 0.5, -6.0), 0],  [Vector3(11.5, 0.5, -5.0), 1],
		[Vector3(-12.0, 0.5, 5.5), 1],   [Vector3(10.5, 0.5, 6.5), 0],
		[Vector3(-6.0, 0.5, -10.5), 0],  [Vector3(6.5, 0.5, -10.0), 1],
		[Vector3(0.0, 0.5, 10.5), 2],
	]
	for d in dwell:
		var pos: Vector3 = d[0]
		match int(d[1]):
			2: add_child(_make_hall(pos))
			_: add_child(_make_tent(pos, rng))

	# --- The Singers' bunting strung across the camp. ---
	add_child(_make_bunting(Vector3(-7.0, 0.5, 3.0), Vector3(-2.0, 0.5, -2.0)))
	add_child(_make_bunting(Vector3(-2.0, 0.5, -2.0), Vector3(4.5, 0.5, -3.0)))
	add_child(_make_bunting(Vector3(4.5, 0.5, -3.0), Vector3(8.0, 0.5, 2.0)))

	# --- Pale flora + rubble clustered around the camp edges. ---
	for n in range(40):
		var gp := Vector3(rng.randf_range(-15.0, 15.0), 0.5, rng.randf_range(-12.0, 12.0))
		if absf(gp.x) < 5.0 and absf(gp.z) < 5.0:
			continue  # keep the ceremony centre clear
		add_child(_make_grass_tuft(gp, rng))
	for n in range(10):
		var s := rng.randf_range(0.3, 0.6)
		var chunk := _box(Vector3(s, s * 0.6, s), COL_STONE_DARK)
		chunk.position = Vector3(rng.randf_range(-14.0, 14.0), 0.5 + s * 0.3, rng.randf_range(-11.0, 11.0))
		chunk.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 90.0), 0.0)
		add_child(chunk)


# The ceremony dais: concentric stone tiers with a warm glowing core + a hearth light.
func _make_dais(pos: Vector3) -> Node3D:
	var dais := Node3D.new()
	dais.position = pos
	var tiers := [
		[4.0, 0.22, COL_STONE_DARK], [3.0, 0.3, COL_STONE], [2.1, 0.34, COL_STONE.lerp(COL_PALE, 0.2)],
	]
	for t in tiers:
		var disc := CSGCylinder3D.new()
		disc.radius = t[0]
		disc.height = t[1]
		disc.position = Vector3(0.0, t[1] * 0.5, 0.0)
		disc.material = _mat(t[2])
		dais.add_child(disc)
	# Warm summon-glow inlaid in the centre.
	var glow_disc := CSGCylinder3D.new()
	glow_disc.radius = 1.3
	glow_disc.height = 0.12
	glow_disc.position = Vector3(0.0, 0.9, 0.0)
	glow_disc.material = _mat(COL_HEARTH)
	dais.add_child(glow_disc)
	var glow := OmniLight3D.new()
	glow.light_color = COL_HEARTH
	glow.light_energy = 7.0
	glow.omni_range = 10.0
	glow.position = Vector3(0.0, 1.4, 0.0)
	dais.add_child(glow)
	return dais


# Anthe the summoner: a small cel-shaded robed figure (tapered robe + head + a staff
# with a pale tip), violet-robed (the "normal summoning" hue), standing on the dais.
func _make_anthe(pos: Vector3) -> Node3D:
	var anthe := Node3D.new()
	anthe.position = pos
	# Tapered robe: two stacked boxes, wider at the hem.
	var hem := _box(Vector3(1.0, 0.9, 0.8), COL_ANTHE_ROBE_DK)
	hem.position = Vector3(0.0, 0.45, 0.0)
	anthe.add_child(hem)
	var torso := _box(Vector3(0.7, 0.8, 0.6), COL_ANTHE_ROBE)
	torso.position = Vector3(0.0, 1.2, 0.0)
	anthe.add_child(torso)
	# Shoulders / cowl.
	var cowl := _box(Vector3(0.78, 0.3, 0.66), COL_ANTHE_ROBE_DK)
	cowl.position = Vector3(0.0, 1.65, 0.0)
	anthe.add_child(cowl)
	# Head.
	var head := _box(Vector3(0.34, 0.36, 0.34), COL_ANTHE_PALE)
	head.position = Vector3(0.0, 1.95, 0.0)
	anthe.add_child(head)
	# Staff with a pale glowing tip (the ceremony focus).
	var staff := _box(Vector3(0.08, 2.2, 0.08), COL_STONE_DARK)
	staff.position = Vector3(0.5, 1.1, 0.1)
	anthe.add_child(staff)
	var tip := _box(Vector3(0.2, 0.2, 0.2), COL_PALE)
	tip.position = Vector3(0.5, 2.25, 0.1)
	anthe.add_child(tip)
	return anthe


# A canvas tent dwelling: a low square base + a pitched (pyramid-ish) canvas roof.
func _make_tent(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var tent := Node3D.new()
	tent.position = pos
	tent.rotation_degrees.y = rng.randf_range(0.0, 90.0)
	var canvas := rng.randf() < 0.5
	var w := rng.randf_range(2.4, 3.2)
	# Body.
	var body := _box(Vector3(w, 1.4, w), COL_TENT if canvas else COL_TENT2)
	body.position = Vector3(0.0, 0.7, 0.0)
	tent.add_child(body)
	# Pitched roof (a smaller box rotated 45 reads as a ridge from the iso angle).
	var roof := _box(Vector3(w * 0.85, 0.9, w * 0.85), COL_TENT2 if canvas else COL_TENT)
	roof.position = Vector3(0.0, 1.7, 0.0)
	roof.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	tent.add_child(roof)
	# A little warm doorway slit.
	var door := _box(Vector3(0.5, 0.8, 0.1), COL_STONE_DARK)
	door.position = Vector3(0.0, 0.5, w * 0.5 + 0.02)
	tent.add_child(door)
	return tent


# The stone hall: a longer gabled stone building (the tribe's gathering hall).
func _make_hall(pos: Vector3) -> Node3D:
	var hall := Node3D.new()
	hall.position = pos
	var body := _box(Vector3(6.5, 2.4, 4.0), COL_STONE)
	body.position = Vector3(0.0, 1.2, 0.0)
	hall.add_child(body)
	var roof := _box(Vector3(7.0, 0.5, 4.6), COL_STONE_DARK)
	roof.position = Vector3(0.0, 2.55, 0.0)
	hall.add_child(roof)
	# Warm-lit doorway facing the camp (toward -z / the dais).
	var door := _box(Vector3(1.0, 1.6, 0.2), COL_HEARTH)
	door.position = Vector3(0.0, 0.8, -2.0)
	hall.add_child(door)
	var glow := OmniLight3D.new()
	glow.light_color = COL_HEARTH
	glow.light_energy = 3.0
	glow.omni_range = 5.0
	glow.position = Vector3(0.0, 1.2, -2.4)
	hall.add_child(glow)
	return hall


func _make_grass_tuft(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var tuft := Node3D.new()
	tuft.position = pos
	var base := COL_FLORA2 if rng.randf() < 0.3 else COL_FLORA
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
	for p in [a, b]:
		var post := _box(Vector3(0.18, 3.0, 0.18), COL_STONE_DARK)
		post.position = p + Vector3(0.0, 1.5, 0.0)
		n.add_child(post)
	var top_a := a + Vector3(0.0, 2.9, 0.0)
	var top_b := b + Vector3(0.0, 2.9, 0.0)
	var mid := (top_a + top_b) * 0.5 + Vector3(0.0, -0.5, 0.0)
	n.add_child(_line_segment(top_a, mid, COL_STONE_DARK))
	n.add_child(_line_segment(mid, top_b, COL_STONE_DARK))
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
		var col := COL_PALE if i % 2 == 0 else COL_HEARTH  # pale + warm camp flags
		var flag := _box(Vector3(0.34, 0.42, 0.02), col)
		flag.position = pos + Vector3(0.0, -0.26, 0.0)
		flag.rotation_degrees.x = 12.0
		parent.add_child(flag)
