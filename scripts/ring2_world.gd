extends Node3D
class_name Ring2World

## Ring 2 (The Singing Lands) 3D playfield geometry — the cel-shaded blockout for
## the second ring. Modelled on `Ring1World`: a `Node3D` terrain builder mounted
## under an `IsoRig` (`build(rig)`, then `rig.add_world_child(world)`). Unlike
## Ring 1 it also carries its own look: `palette()` and `apply_environment(rig)`
## let `main` reconfigure the shared rig per ring (Phase 5). Spawns are NOT here —
## they live in `main.gd` (sim-space, bounds are universal).
##
## The Singing Lands: "where the world becomes genuinely alive" (GDD §The Five
## Rings) — dense alien flora in deep purples and rose-pinks, ruined Singer
## settlements, a faint wrongness at colour's edge. Palette + environment are
## MEASURED from `idea/the_singing_lands_concept_1.png` per `docs/RENDERING_3D.md`
## (dark indigo backdrop, saturated rose/magenta flora, one warm amber glow).
##
## Universal bounds (see `sim_space.gd`): the walkable plateau must cover at least
## the warrior's reachable footprint (x +-13.0, z +-6.94) with ~1u margin, so it
## keeps Ring 1's 28 x 22 plateau.

# --- Measured Singing Lands surface colours ------------------------------
# Legibility strategy (Phase 5 gate): the WALKABLE ground is a DESATURATED purple-
# grey, and the saturated rose/magenta is concentrated in the FLORA props. This
# restores the read that Ring 1 got for free — there, the grey ground let the
# saturated signal hues (pink/lavender enemies) pop by saturation alone. A
# saturated rose ground (the first pass) collapsed that: the dissonant-pink signal
# blended into the rose terrain. Keeping the stage desaturated also lets the dark
# warrior billboard read against it. The rose stays the ring's identity — it lives
# in the dense flora that rings the play area, not under the player's feet.
const COL_LOWLAND := Color("18172f")    # dark indigo surrounding land (fades to haze)
const COL_GROUND := Color("736d85")     # walkable plateau (pale desaturated purple-grey)
const COL_GROUND_MID := Color("574f63") # ground variation
const COL_GROUND_DARK := Color("40384e") # worn / shadow patches
const COL_PATH := Color("834150")       # rose dirt trail (reads on the pale ground)
const COL_PATH_PALE := Color("9a5656")  # lit path / highlight
const COL_STONE := Color("4a3a52")      # Singer ruin stone (mid — reads vs the dark bg)
const COL_STONE_DARK := Color("18172f") # ruin shadow / deep recess
const COL_OUTPOST := Color("2e2749")    # Watcher-outpost indigo (far silhouette)
const COL_OUTPOST_LIT := Color("353560")
const COL_FLORA := Color("722a49")      # alien flora body (deep rose-magenta)
const COL_FLORA_HI := Color("9a5656")   # flora highlight (rose; brightest terrain rose,
                                        # kept below the dissonant signal so highlights
                                        # snap to terrain, not the signal)
const COL_FLORA_DEEP := Color("502a42")  # flora shadow (purple)
const COL_GLOW := Color("c16e39")       # warm amber glow point (the one warm accent)
const COL_FOG := Color("2e2749")        # indigo haze (distance lerps)

var _rig: IsoRig


## The 16-entry palette every pixel snaps to: 14 measured Singing Lands tones +
## the two gameplay-signal hues (dissonant pink / harmonic lavender), which are
## universal and must be preserved on every ring (see `iso_rig.gd`). The brightest
## terrain rose is `9a5656`; `a9615c` is deliberately excluded (too near the
## signal pink — it would pull flora highlights onto the dissonant signal).
func palette() -> PackedStringArray:
	return PackedStringArray([
		"18172f", "221d3c", "2e2749", "353560",   # indigo darks (bg / outpost / shadow)
		"40384e", "4a3a52", "574f63", "736d85",   # desaturated purple-grey stage + stone
		"502a42", "652b45", "722a49", "834150",   # saturated rose/magenta flora
		"9a5656", "c16e39",                        # rose highlight, warm amber glow
		"c4547a", "c0a0f0",                        # signal: dissonant pink, harmonic lavender
	])


## The warrior's ember/hem snap to the ring's own warm amber glow (palette-present),
## so his fire reads amber here instead of colliding with the dissonant-pink signal.
func ember_tint() -> Color:
	return Color("c16e39")


## Reconfigure the rig's environment for the Singing Lands: a dark indigo backdrop
## with luminous flora, instead of Ring 1's pale cool haze. Call BEFORE the rig
## enters the tree (it builds its pipeline on _ready). Signal-hue palette aside,
## this is what makes Ring 2 read as a different place.
func apply_environment(rig: IsoRig) -> void:
	rig.bg_color = Color("221d3c")        # dark indigo sky
	rig.fog_color = COL_FOG               # indigo aerial haze
	rig.fog_density = 0.006               # a touch heavier than Ring 1 — moodier depth
	rig.ambient_color = Color("d6cfe6")   # pale cool-lavender fill (keeps albedo, tints cool)
	rig.key_light_color = Color("b0a8d0") # cool violet key
	# pitch / rotation / cel bands stay at the rig defaults (universal iso look).


## Populate this node with the Ring 2 terrain + props, drawing cel materials from
## `rig`. Call before mounting (`rig.add_world_child(world)`); no tree required.
func build(rig: IsoRig) -> void:
	_rig = rig
	_build_terrain()
	GroundStyle.scatter_decals(self, _rig, SimSpace.half_world(), COL_GROUND)


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
	rng.seed = 12  # Ring 2's own scatter seed (Ring 1 uses 7)
	# Walkable half-extents from the shared arena knob (SimSpace.PLAY_SCALE); all
	# terrain extents derive from it so the ground covers the warrior's reach.
	var half := SimSpace.half_world()

	# --- Surrounding lowland: large dark plane so the frame fills and fades into
	# indigo haze instead of a void. Sized well beyond the plateau. ---
	var land := CSGBox3D.new()
	var land_span := maxf(300.0, (maxf(half.x, half.y) + 90.0) * 2.0)
	land.size = Vector3(land_span, 2.0, land_span)
	land.position = Vector3(0.0, -2.6, 0.0)
	land.material = _mat(COL_LOWLAND)
	add_child(land)

	# --- Plateau the path crosses (covers the full reachable footprint +-half) ---
	var plateau := CSGBox3D.new()
	plateau.size = Vector3(half.x * 2.0 + 2.0, 1.0, half.y * 2.0 + 2.0)
	plateau.position = Vector3(0.0, 0.0, 0.0)
	plateau.material = GroundStyle.ground_mat(_rig, COL_GROUND)
	add_child(plateau)

	# Worn purple ground patches break the flat plateau colour.
	for n in range(8):
		var patch := _box(
			Vector3(rng.randf_range(3.0, 6.0), 0.06, rng.randf_range(3.0, 6.0)),
			COL_GROUND_DARK if n % 2 == 0 else COL_GROUND_MID
		)
		patch.position = Vector3(rng.randf_range(-10.0, 10.0), 0.5, rng.randf_range(-8.0, 8.0))
		patch.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		add_child(patch)

	# --- Winding rose path across the camp (two angled flat strips) ---
	var path_a := CSGBox3D.new()
	path_a.size = Vector3(2.2, 0.12, 12.0)
	path_a.position = Vector3(-2.0, 0.52, 2.0)
	path_a.rotation_degrees = Vector3(0.0, 16.0, 0.0)
	path_a.material = GroundStyle.ground_mat(_rig, COL_PATH)
	add_child(path_a)
	var path_b := CSGBox3D.new()
	path_b.size = Vector3(2.2, 0.12, 9.0)
	path_b.position = Vector3(2.0, 0.52, -5.5)
	path_b.rotation_degrees = Vector3(0.0, -20.0, 0.0)
	path_b.material = GroundStyle.ground_mat(_rig, COL_PATH_PALE)
	add_child(path_b)

	# --- The warm glow point: "a wrongness at colour's edge" (concept centre) ---
	# A small amber shrine node + an omni light, the one warm accent in the frame.
	add_child(_make_glow_shrine(Vector3(6.0, 0.5, 1.5)))

	# --- Ruined Singer settlements: a broken wall + a toppled arch ---
	add_child(_make_ruined_wall(Vector3(-8.5, 0.5, -4.0), 7.0, -12.0))
	add_child(_make_arch(Vector3(3.5, 0.5, -8.0)))

	# --- Dense alien flora clusters (the signature of the Singing Lands) ---
	# Saturated rose/magenta crystal spikes, clustered along the plateau edges and
	# the ruins so the walkable centre stays readable (legibility: keep the bright
	# signal hues uncluttered where enemies will stand).
	var cluster_anchors := [
		Vector3(-10.0, 0.5, 6.0), Vector3(10.0, 0.5, 5.5), Vector3(-9.5, 0.5, -7.5),
		Vector3(9.0, 0.5, -6.5), Vector3(-11.0, 0.5, -1.0), Vector3(11.0, 0.5, 0.5),
		Vector3(-4.0, 0.5, 8.5), Vector3(5.0, 0.5, 8.5), Vector3(0.0, 0.5, -9.0),
	]
	for a in cluster_anchors:
		add_child(_make_flora_cluster(a, rng))

	# --- Scattered single flora spikes + crystal tufts for density ---
	for n in range(40):
		var pos := Vector3(rng.randf_range(-12.0, 12.0), 0.5, rng.randf_range(-9.5, 9.5))
		# Keep the central walkable band sparse so combat reads cleanly.
		if absf(pos.x) < 4.5 and absf(pos.z) < 4.5:
			continue
		add_child(_make_flora_spike(pos, rng.randf_range(0.5, 1.6), rng))

	# --- A distant Watcher outpost silhouette (far back-right, outside the play
	# area). Pushed well out so it stays a background silhouette and doesn't loom
	# into the near foreground when the camera orbits past it. ---
	add_child(_make_outpost(Vector3(half.x * 0.7, 0.5, -half.y * 0.8)))

	# === EXPANSE FILL: the authored camp above is the dense hub; populate the larger
	# reach out to the edges with graduated-density flora/rubble (thinning toward the
	# haze) plus a few outlying ruins as explore landmarks. ===
	_fill_expanse(half)
	_add_outlying_landmarks(half)


func _make_flora_cluster(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var cluster := Node3D.new()
	cluster.position = pos
	for i in range(rng.randi_range(5, 9)):
		var off := Vector3(rng.randf_range(-1.4, 1.4), 0.0, rng.randf_range(-1.4, 1.4))
		var spike := _make_flora_spike(off, rng.randf_range(0.8, 2.4), rng)
		cluster.add_child(spike)
	return cluster


# A single tapered alien flora spike (a thin vertical box, jittered) — reads as a
# luminous crystal/stalk against the dark ground.
func _make_flora_spike(pos: Vector3, height: float, rng: RandomNumberGenerator) -> Node3D:
	var stalk := Node3D.new()
	stalk.position = pos
	var pick := rng.randf()
	var col := COL_FLORA
	if pick < 0.33:
		col = COL_FLORA_HI
	elif pick < 0.5:
		col = COL_FLORA_DEEP
	var w := rng.randf_range(0.10, 0.22)
	var spike := _box(Vector3(w, height, w), col)
	spike.position = Vector3(0.0, height * 0.5, 0.0)
	spike.rotation_degrees = Vector3(
		rng.randf_range(-10.0, 10.0), rng.randf_range(0.0, 360.0), rng.randf_range(-10.0, 10.0)
	)
	stalk.add_child(spike)
	# A small bright bud near the tip on the taller spikes.
	if height > 1.2:
		var bud := _box(Vector3(w * 1.8, w * 1.8, w * 1.8), COL_FLORA_HI)
		bud.position = Vector3(0.0, height * 0.95, 0.0)
		stalk.add_child(bud)
	return stalk


func _make_glow_shrine(base_pos: Vector3) -> Node3D:
	var shrine := Node3D.new()
	shrine.position = base_pos
	# A short dark plinth.
	var plinth := CSGCylinder3D.new()
	plinth.radius = 0.9
	plinth.height = 0.6
	plinth.position = Vector3(0.0, 0.3, 0.0)
	plinth.material = _mat(COL_STONE)
	shrine.add_child(plinth)
	# The warm node itself: a small amber box that catches the eye.
	var node := _box(Vector3(0.5, 0.7, 0.5), COL_GLOW)
	node.position = Vector3(0.0, 0.95, 0.0)
	node.rotation_degrees.y = 45.0
	shrine.add_child(node)
	# The omni light that sells the "glow point" — warm, local.
	var glow := OmniLight3D.new()
	glow.light_color = COL_GLOW
	glow.light_energy = 8.0
	glow.omni_range = 9.0
	glow.position = Vector3(0.0, 1.2, 0.0)
	shrine.add_child(glow)
	return shrine


func _make_ruined_wall(base_pos: Vector3, length: float, yaw_deg: float) -> Node3D:
	var wall := Node3D.new()
	wall.position = base_pos
	wall.rotation_degrees.y = yaw_deg
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# A crumbling row of stone blocks of varying heights (the broken Singer wall).
	var segs := int(length / 1.1)
	for i in range(segs):
		var h := rng.randf_range(0.8, 2.6)
		var block := _box(Vector3(1.0, h, 0.9), COL_STONE.lerp(COL_STONE_DARK, rng.randf() * 0.5))
		block.position = Vector3(-length * 0.5 + i * 1.1, h * 0.5, 0.0)
		wall.add_child(block)
	return wall


func _make_arch(base_pos: Vector3) -> Node3D:
	var arch := Node3D.new()
	arch.position = base_pos
	arch.rotation_degrees.y = -15.0
	var mat := _mat(COL_STONE)
	for dx in [-1.3, 1.3]:
		var pillar := CSGBox3D.new()
		pillar.size = Vector3(0.7, 3.4, 0.7)
		pillar.position = Vector3(dx, 1.7, 0.0)
		pillar.material = mat
		arch.add_child(pillar)
	var lintel := CSGBox3D.new()
	lintel.size = Vector3(3.3, 0.7, 0.7)
	lintel.position = Vector3(0.0, 3.4, 0.0)
	lintel.material = mat
	arch.add_child(lintel)
	# Flora overtaking the ruin — a couple of spikes climbing the pillars.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	arch.add_child(_make_flora_spike(Vector3(-1.3, 0.0, 0.4), 2.2, rng))
	arch.add_child(_make_flora_spike(Vector3(1.3, 0.0, -0.4), 1.6, rng))
	return arch


func _make_outpost(base_pos: Vector3) -> Node3D:
	var outpost := Node3D.new()
	outpost.position = base_pos
	# A clustered set of dark indigo towers — a far Watcher silhouette.
	var heights := [9.0, 12.0, 7.0, 10.0]
	var offs := [Vector3(0, 0, 0), Vector3(2.2, 0, 1.0), Vector3(-2.0, 0, 1.5), Vector3(1.0, 0, -2.0)]
	for i in range(heights.size()):
		var h: float = heights[i]
		var tower := _box(Vector3(2.0, h, 2.0), COL_OUTPOST if i % 2 == 0 else COL_OUTPOST_LIT)
		tower.position = (offs[i] as Vector3) + Vector3(0.0, h * 0.5, 0.0)
		outpost.add_child(tower)
	return outpost


# World radius of the authored central camp, kept clear by the expanse fill.
const HUB := 13.0


# Graduated-density scatter across the plateau using the Singing Lands' own props:
# dense just outside the hub, thinning to sparse at the rim. Own RNG (seed 23) so the
# hub's seed-12 layout is byte-for-byte unchanged.
func _fill_expanse(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var area := half.x * half.y
	for n in range(clampi(int(area * 0.03), 24, 90)):
		var p := SimSpace.scatter_point(rng, half, HUB)
		if p != Vector3.INF:
			add_child(_make_flora_cluster(p, rng))
	for n in range(clampi(int(area * 0.08), 60, 260)):
		var p := SimSpace.scatter_point(rng, half, HUB)
		if p != Vector3.INF:
			add_child(_make_flora_spike(p, rng.randf_range(0.5, 1.8), rng))
	for n in range(clampi(int(area * 0.03), 24, 100)):
		var p := SimSpace.scatter_point(rng, half, HUB)
		if p == Vector3.INF:
			continue
		var sz := rng.randf_range(0.3, 0.8)
		var chunk := _box(Vector3(sz, sz * 0.7, sz), COL_STONE if n % 2 == 0 else COL_STONE_DARK)
		chunk.position = p + Vector3(0.0, sz * 0.35, 0.0)
		chunk.rotation_degrees = Vector3(rng.randf_range(-10.0, 10.0), rng.randf_range(0.0, 90.0), rng.randf_range(-10.0, 10.0))
		add_child(chunk)


# A few Singer ruins out in the reach so exploration has destinations.
func _add_outlying_landmarks(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var ring_r := minf(half.x, half.y)
	for i in range(5):
		var ang := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var r := ring_r * rng.randf_range(0.5, 0.85)
		var pos := Vector3(cos(ang) * r, 0.5, sin(ang) * r)
		var kind := i % 3
		if kind == 0:
			add_child(_make_ruined_wall(pos, rng.randf_range(5.0, 9.0), rng.randf_range(0.0, 180.0)))
		elif kind == 1:
			add_child(_make_arch(pos))
		else:
			add_child(_make_glow_shrine(pos))
