extends Node3D
class_name Ring5World

## Ring 5 (The Still Heart) 3D playfield geometry — the final ring. Same contract as
## `Ring2World`..`Ring4World`: a `Node3D` terrain builder (`build(rig)`) carrying
## `palette()` / `apply_environment(rig)` so `main` reconfigures the shared rig per
## ring. Spawns live in `main.gd` (sim-space; the bounds are universal).
##
## The Still Heart: "the world looks like a very high-quality reproduction of itself,
## made by something that understood form but not warmth ... this is what the world was
## listening for." The concept art (`idea/the_still_heart_concept_1.png`) is a cold,
## near-MONOCHROME blue-grey ruined formal ROSE GARDEN — symmetric hedges and radial
## paths, dense grey rose foliage, ruined garden stone — with one violet-blue accent:
## a central crystalline ALTAR/cathedral with a tall glowing spire (the listening
## heart), and faint pale-white glints (a distant stag, the warrior's "something
## left"). Palette + environment are MEASURED from the concept (quantize + pixel scan)
## per `docs/RENDERING_3D.md`, NOT assumed from GDD prose. It is the cold inversion of
## Ring 4's warm canyon — colourless "form without warmth".
##
## Legibility is no longer gated (the enemy MOOD PIP carries frequency against any
## terrain — see `world_sync.gd`), so the palette is free to be monochrome grey,
## including a violet accent near the harmonic signal hue (the structure violet is
## distinctly darker/less saturated than the `c0a0f0` signal, so they don't collapse;
## the pip distinguishes either way). The one read still on terrain is WARRIOR vs
## ground: the warrior billboard is dark, so the WALKABLE plaza is a LIGHTER cool grey
## (the lit central plaza, brighter than the dark garden — also on-concept) while the
## darker greys recede into the peripheral garden.
##
## Universal bounds (`sim_space.gd`): the walkable plaza covers the warrior's reachable
## footprint (x +-13.0, z +-6.94) with ~1u margin, so it keeps the shared 28 x 22
## plateau.

# --- Measured Still Heart surface colours ---------------------------------
const COL_VOID := Color("1f242f")        # darkest cold blue-grey (sky / surround)
const COL_SHADOW := Color("282f39")      # deep garden shadow
const COL_RUIN_DARK := Color("323843")   # ruined stone in shadow / hedge base
const COL_GROUND_DARK := Color("3a434e") # dark garden ground (peripheral lowland)
const COL_STONE := Color("444a52")       # ruined garden stone (mid)
const COL_ROSE := Color("53565c")        # grey rose foliage (colourless reproduction)
const COL_GROUND := Color("5b606a")      # mid plaza grey (worn variation)
const COL_PLAZA := Color("676970")       # WALKABLE plaza (lighter, so the dark warrior reads)
const COL_PLAZA_LIT := Color("7b7d83")   # lit plaza / path highlight (pale grey)
const COL_STRUCT_DARK := Color("303c60") # central altar deep violet
const COL_STRUCT := Color("3c486c")      # altar mid violet-blue
const COL_STRUCT_LIT := Color("485478")  # altar lit violet
const COL_GLOW := Color("5f67a0")        # bright spire glow (periwinkle — the one accent)
const COL_PALE := Color("c4c8d2")        # pale near-white glint (stag / "something left")

var _rig: IsoRig


## 16-entry palette every pixel snaps to: 14 measured Still Heart tones + the two
## gameplay-signal hues (dissonant pink / harmonic lavender), universal and preserved
## on every ring (see `iso_rig.gd`). The structure violet (`303c60`..`5f67a0`) sits
## darker/duller than the `c0a0f0` harmonic signal, so the altar can't be confused with
## a harmonic enemy; the pip distinguishes either way.
func palette() -> PackedStringArray:
	return PackedStringArray([
		"1f242f", "282f39", "323843", "3a434e",   # cold grey darks (sky / shadow / ruin / ground)
		"444a52", "53565c", "5b606a", "676970",   # grey ramp (stone / rose / plaza)
		"7b7d83", "c4c8d2",                        # pale grey highlight, pale-white glint
		"303c60", "3c486c", "485478", "5f67a0",   # violet altar ramp + spire glow
		"c4547a", "c0a0f0",                        # signal: dissonant pink, harmonic lavender
	])


## Form without warmth: the Still Heart has no warm slot, so the warrior's fire goes
## COLD here — his ember/hem read as a pale-white glint, the "He has something left"
## cold star from the concept, instead of snapping to the dissonant-pink signal.
func ember_tint() -> Color:
	return Color("c4c8d2")


## Reconfigure the rig for the Still Heart: a cold, colourless twilight — dim cool
## ambient, a cold blue-grey key, grey haze. "Form but not warmth": no warm slot at all
## (the opposite of Ring 4). Call BEFORE the rig enters the tree (it builds on _ready).
func apply_environment(rig: IsoRig) -> void:
	rig.bg_color = Color("22272f")        # cold dark blue-grey sky
	rig.fog_color = Color("3a434e")       # cold grey aerial haze
	rig.fog_density = 0.005               # the garden recedes into still cold haze
	rig.ambient_color = Color("c6ccd8")   # cool dim fill (keeps albedo, tints cold)
	rig.key_light_color = Color("b8c0d4") # cold blue-grey key (no warmth)
	# pitch / rotation / cel bands stay at the rig defaults (universal iso look).


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
	rng.seed = 55  # Ring 5's own scatter seed (1=7, 2=12, 3=31, 4=44)

	# --- Surrounding lowland: a large dark cold plane so far edges fade into grey
	# haze instead of a void. ---
	var land := CSGBox3D.new()
	land.size = Vector3(300.0, 2.0, 300.0)
	land.position = Vector3(0.0, -2.4, 0.0)
	land.material = _mat(COL_GROUND_DARK)
	add_child(land)

	# --- Main walkable plaza (28 x 22, universal footprint) — the lit cool stage ---
	var plaza := CSGBox3D.new()
	plaza.size = Vector3(28.0, 1.0, 22.0)
	plaza.position = Vector3(0.0, 0.0, 0.0)
	plaza.material = _mat(COL_PLAZA)
	add_child(plaza)

	# Worn / lit plaza patches break the flat colour (formal, low-contrast — mid greys,
	# never the darkest, so the dark warrior keeps its read wherever it stands).
	for n in range(8):
		var lit := n % 3 == 0
		var patch := _box(
			Vector3(rng.randf_range(3.0, 5.5), 0.06, rng.randf_range(3.0, 5.5)),
			COL_PLAZA_LIT if lit else COL_GROUND
		)
		patch.position = Vector3(rng.randf_range(-11.0, 11.0), 0.5, rng.randf_range(-8.5, 8.5))
		patch.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		add_child(patch)

	# --- Radial paths converging on the altar (formal symmetry — "understood form"). ---
	for i in range(8):
		var path := _box(Vector3(1.6, 0.1, 11.0), COL_PLAZA_LIT)
		path.position = Vector3(0.0, 0.52, 0.0)
		path.rotation_degrees.y = i * 45.0
		add_child(path)

	# --- The central altar: the crystalline violet heart with a glowing spire (the
	# listening structure; the hero landmark, like Ring 4's mechanism but tall + cold). ---
	add_child(_make_altar(Vector3(0.0, 0.5, 0.0)))

	# --- Formal hedges framing garden beds (low symmetric grey borders). ---
	var hedge_specs := [
		[Vector3(-9.0, 0.5, -7.0), 7.0, 0.0], [Vector3(9.0, 0.5, -7.0), 7.0, 0.0],
		[Vector3(-9.0, 0.5, 7.0), 7.0, 0.0], [Vector3(9.0, 0.5, 7.0), 7.0, 0.0],
		[Vector3(-12.0, 0.5, 0.0), 8.0, 90.0], [Vector3(12.0, 0.5, 0.0), 8.0, 90.0],
	]
	for spec in hedge_specs:
		add_child(_make_hedge(spec[0], spec[1], spec[2]))

	# --- Dense grey rose foliage clustered in the garden beds / plateau edges (the
	# colourless rose garden; peripheral so the lit centre stays readable). ---
	var cluster_anchors := [
		Vector3(-11.0, 0.5, 6.5), Vector3(11.0, 0.5, 6.0), Vector3(-11.0, 0.5, -6.5),
		Vector3(11.0, 0.5, -6.0), Vector3(-7.0, 0.5, 9.0), Vector3(7.0, 0.5, 9.0),
		Vector3(-7.0, 0.5, -9.0), Vector3(7.0, 0.5, -9.0),
	]
	for a in cluster_anchors:
		add_child(_make_rose_cluster(a, rng))

	# Scattered single rose bushes for density; keep the central walkable band clear.
	for n in range(22):
		var pos := Vector3(rng.randf_range(-12.0, 12.0), 0.5, rng.randf_range(-9.5, 9.5))
		if absf(pos.x) < 5.0 and absf(pos.z) < 5.0:
			continue
		add_child(_make_rose_bush(pos, rng.randf_range(0.5, 1.0), rng))

	# --- Ruined formal garden stone framing the play area (broken columns + low
	# walls, beyond the footprint — the reproduction crumbling at its edges). ---
	var ruin_specs := [
		[Vector3(-17.0, -0.5, -3.0), 90.0], [Vector3(17.0, -0.5, 3.0), -90.0],
		[Vector3(-3.0, -0.5, -15.0), 0.0], [Vector3(4.0, -0.5, 15.0), 0.0],
		[Vector3(-15.0, -0.5, 12.0), 40.0], [Vector3(15.0, -0.5, -12.0), -40.0],
	]
	for spec in ruin_specs:
		add_child(_make_ruin(spec[0], spec[1], rng))

	# --- Faint pale-white glints: the distant stag, the things still listening. A few
	# quiet near-white points at the periphery (the only brightness besides the spire). ---
	for pos in [Vector3(13.5, 1.0, -8.5), Vector3(-12.5, 0.9, 9.0), Vector3(8.0, 0.8, 13.0)]:
		var glint := _box(Vector3(0.3, 0.5, 0.3), COL_PALE)
		glint.position = pos
		add_child(glint)


# The central altar: a low tiered violet base + a ring of inward-LEANING buttress
# pillars that converge into a spire silhouette ABOVE head height, with a glowing
# crystal at the convergence — "what the world was listening for". Dead centre stays
# open at the warrior's height (the warrior spawns here), so the spire reads as a
# crystalline cathedral the warrior stands within, not an obelisk it clips into.
func _make_altar(pos: Vector3) -> Node3D:
	var altar := Node3D.new()
	altar.position = pos
	# Tiered circular base (concentric stepped discs, low so it stays walkable).
	var tiers := [
		[3.4, 0.22, COL_STRUCT_DARK], [2.6, 0.4, COL_STRUCT], [1.8, 0.6, COL_STRUCT_LIT],
	]
	for t in tiers:
		var disc := CSGCylinder3D.new()
		disc.radius = t[0]
		disc.height = t[1]
		disc.position = Vector3(0.0, t[1] * 0.5, 0.0)
		disc.material = _mat(t[2])
		altar.add_child(disc)
	# Eight buttress pillars rising from the rim (radius 4.0) and leaning inward to
	# converge near the centre at height ~6 — a crystalline spire cage. At the
	# warrior's height (y<=3) the pillars are still well out from centre, so they
	# never clip the player standing at the altar's heart.
	for i in range(8):
		var ang := deg_to_rad(i * 45.0)
		var base := Vector3(sin(ang) * 4.0, 0.0, cos(ang) * 4.0)
		var top := Vector3(sin(ang) * 0.9, 6.0, cos(ang) * 0.9)
		altar.add_child(_leaning_pillar(base, top, 0.34, COL_STRUCT))
	# A glowing crystal at the convergence (well above head height) + a pale tip.
	var glow := _box(Vector3(0.9, 1.6, 0.9), COL_GLOW)
	glow.position = Vector3(0.0, 6.2, 0.0)
	glow.rotation_degrees.y = 45.0
	altar.add_child(glow)
	var tip := _box(Vector3(0.5, 0.7, 0.5), COL_PALE)
	tip.position = Vector3(0.0, 7.2, 0.0)
	tip.rotation_degrees.y = 45.0
	altar.add_child(tip)
	# A low lit ring on the base so the heart reads even when the spire is off-frame.
	var ring := CSGCylinder3D.new()
	ring.radius = 1.4
	ring.height = 0.7
	ring.position = Vector3(0.0, 0.35, 0.0)
	ring.material = _mat(COL_GLOW)
	altar.add_child(ring)
	# Cold periwinkle light: the listening heart glowing in the colourless garden.
	var light := OmniLight3D.new()
	light.light_color = Color("8088c0")
	light.light_energy = 5.0
	light.omni_range = 11.0
	light.position = Vector3(0.0, 4.0, 0.0)
	altar.add_child(light)
	return altar


# A box pillar oriented to run from `base` to `top` (local +Y mapped onto the
# base->top direction), width `w`. Used for the altar's inward-leaning buttresses.
func _leaning_pillar(base: Vector3, top: Vector3, w: float, col: Color) -> MeshInstance3D:
	var dir := (top - base)
	var length := dir.length()
	var up := dir / length
	var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD
	var x := arbitrary.cross(up).normalized()
	var z := x.cross(up).normalized()
	var mi := _box(Vector3(w, length, w), col)
	mi.transform = Transform3D(Basis(x, up, z), (base + top) * 0.5)
	return mi


# A low formal hedge: a long grey box with a slightly lit top (clipped garden border).
func _make_hedge(base_pos: Vector3, length: float, yaw_deg: float) -> Node3D:
	var hedge := Node3D.new()
	hedge.position = base_pos
	hedge.rotation_degrees.y = yaw_deg
	var body := _box(Vector3(0.8, 1.0, length), COL_RUIN_DARK)
	body.position = Vector3(0.0, 0.5, 0.0)
	hedge.add_child(body)
	var top := _box(Vector3(0.7, 0.12, length * 0.96), COL_ROSE)
	top.position = Vector3(0.0, 1.02, 0.0)
	hedge.add_child(top)
	return hedge


func _make_rose_cluster(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var cluster := Node3D.new()
	cluster.position = pos
	for i in range(rng.randi_range(4, 7)):
		var off := Vector3(rng.randf_range(-1.4, 1.4), 0.0, rng.randf_range(-1.4, 1.4))
		var bush := _make_rose_bush(off, rng.randf_range(0.6, 1.2), rng)
		cluster.add_child(bush)
	return cluster


# A single grey rose bush — a rounded mound of small jittered grey boxes (colourless
# foliage; a pale highlight bud catches the cold light on the taller ones).
func _make_rose_bush(pos: Vector3, height: float, rng: RandomNumberGenerator) -> Node3D:
	var bush := Node3D.new()
	bush.position = pos
	var greys := [COL_ROSE, COL_GROUND, COL_STONE]
	var blobs := rng.randi_range(3, 5)
	for i in range(blobs):
		var s := rng.randf_range(0.35, 0.6)
		var blob := _box(Vector3(s, s, s), greys[rng.randi() % greys.size()])
		var r := (1.0 - float(i) / blobs) * 0.6
		blob.position = Vector3(
			rng.randf_range(-r, r), height * (0.3 + 0.5 * float(i) / blobs), rng.randf_range(-r, r)
		)
		blob.rotation_degrees = Vector3(rng.randf_range(0, 40), rng.randf_range(0, 360), rng.randf_range(0, 40))
		bush.add_child(blob)
	if height > 0.9:
		var bud := _box(Vector3(0.22, 0.22, 0.22), COL_PLAZA_LIT)
		bud.position = Vector3(0.0, height * 0.95, 0.0)
		bush.add_child(bud)
	return bush


# A ruined formal-garden fragment: a stack of broken grey columns / low wall blocks
# beyond the footprint, framing the play area as the reproduction crumbles.
func _make_ruin(base_pos: Vector3, yaw_deg: float, rng: RandomNumberGenerator) -> Node3D:
	var ruin := Node3D.new()
	ruin.position = base_pos
	ruin.rotation_degrees.y = yaw_deg
	var count := rng.randi_range(3, 5)
	for i in range(count):
		var h := rng.randf_range(1.6, 4.0)
		var col := COL_STONE if rng.randf() < 0.5 else COL_RUIN_DARK
		var block := _box(Vector3(1.2, h, 1.2), col)
		block.position = Vector3(-count * 0.8 + i * 1.6, h * 0.5, rng.randf_range(-0.6, 0.6))
		ruin.add_child(block)
		# A lit broken cap on some columns.
		if rng.randf() < 0.5:
			var cap := _box(Vector3(1.3, 0.3, 1.3), COL_GROUND)
			cap.position = Vector3(-count * 0.8 + i * 1.6, h, 0.0)
			ruin.add_child(cap)
	return ruin
