extends Node3D
class_name Ring4World

## Ring 4 (The Deep Canals) 3D playfield geometry — Shaper territory, the fourth
## ring. Same contract as `Ring2World`/`Ring3World`: a `Node3D` terrain builder
## (`build(rig)`) that also carries `palette()` / `apply_environment(rig)` so `main`
## reconfigures the shared rig per ring. Spawns live in `main.gd` (sim-space; the
## bounds are universal).
##
## The Deep Canals: "vast canyon systems carved deeper by centuries of Shaper
## industry. The workshops descend. The machinery remembers." The concept art
## (`idea/the_deep_canals_concept_1.png`) is a WARM ring — a grid of amber/terracotta
## canyon plateaus separated by deep channels, with FORGE LIGHT glowing gold from
## below in the seams, ROSE canal flora on the edges, one cool BLUE-GREY drained
## canal as the single cold contrast, and a central gold Shaper MECHANISM. Palette +
## environment are MEASURED from the concept (legend swatches + pixel scan) per
## `docs/RENDERING_3D.md`, not assumed from GDD prose.
##
## Legibility is no longer a gating concern: the enemy MOOD PIP (a tiny unsnapped
## magenta/cyan dot above each enemy, drawn in the post-viewport — see `world_sync.gd`)
## carries the frequency signal against any terrain, so the palette is free to use the
## warm canyon hues — including the heated-rose canal flora that coincides with the
## dissonant signal hue. The one read still on terrain is the WARRIOR vs ground: the
## warrior billboard is dark, so the WALKABLE floor is a lighter desaturated sandy tan
## (lit canyon-floor, brighter than the walls — also on-concept) while the saturated
## amber/forge/rose is concentrated in the walls and peripheral props.
##
## Universal bounds (`sim_space.gd`): the walkable plateau covers the warrior's
## reachable footprint (x +-13.0, z +-6.94) with ~1u margin, so it keeps the shared
## 28 x 22 plateau.

# --- Measured Deep Canals surface colours --------------------------------
const COL_VOID := Color("1d0b0a")        # deepest canyon void below the plateaus
const COL_SHADOW := Color("350f0d")      # deep canyon shadow (channel floors)
const COL_WALL_DARK := Color("5c2010")   # canyon wall in shadow (legend "deep canyon shadow")
const COL_WALL := Color("6f2c1a")        # mid canyon wall
const COL_TERRACOTTA := Color("8c351c")  # lit terracotta wall (legend "deep terracotta" family)
const COL_AMBER := Color("9e4420")        # canyon amber body (dominant warm)
const COL_WALL_LIT := Color("b36939")    # lit canyon ledge / wall face
const COL_AMBER_BRIGHT := Color("d4803a") # brightest canyon amber (legend "canyon amber")
const COL_GROUND := Color("a87a52")       # WALKABLE sandy canyon floor (desaturated, lighter
                                          # than the walls so the dark warrior reads)
const COL_GROUND_LIT := Color("c8a474")  # lit floor patch / bridge plank (pale tan)
const COL_FORGE := Color("f0c060")        # forge light glowing from below (the warm accent)
const COL_WATER_DARK := Color("4a5266")  # drained canal deep water (the one cool element)
const COL_WATER := Color("8890a0")        # drained canal lit surface (legend "mechanism's reach")
const COL_FLORA_DEEP := Color("7a2f48")  # rose canal flora shadow
const COL_FLORA := Color("c4547a")        # heated rose canal flora (== dissonant signal hue)

var _rig: IsoRig


## 16-entry palette every pixel snaps to: 14 measured Deep Canals tones + the two
## gameplay-signal hues (dissonant pink / harmonic lavender), universal and preserved
## on every ring (see `iso_rig.gd`). The canal flora deliberately reuses the dissonant
## pink slot (`c4547a` IS the concept's "heated rose"); the mood pip distinguishes a
## dissonant enemy body from the flora, so no separate slot is spent.
func palette() -> PackedStringArray:
	return PackedStringArray([
		"1d0b0a", "350f0d", "5c2010", "6f2c1a",   # canyon darks / channel floors
		"8c351c", "9e4420", "b36939", "d4803a",   # warm amber/terracotta ramp (walls)
		"a87a52", "c8a474", "f0c060", "4a5266",   # sandy floor + forge gold + dark water
		"8890a0", "7a2f48",                        # drained-canal blue-grey, rose flora shadow
		"c4547a", "c0a0f0",                        # signal: dissonant pink, harmonic lavender
	])


## The warrior's ember/hem snap to the canyon's forge amber (palette-present).
func ember_tint() -> Color:
	return Color("d4803a")


## Reconfigure the rig for the Deep Canals: a warm dark canyon backdrop with forge-lit
## haze, instead of Ring 1's cool pale. Call BEFORE the rig enters the tree (it builds
## its pipeline on _ready). Warm key/ambient/fog sell the forge-lit canyon; kept modest
## so the single cool drain still reads cool after the snap.
func apply_environment(rig: IsoRig) -> void:
	rig.bg_color = Color("241010")        # near-black warm canyon depth
	rig.fog_color = Color("3a1813")       # warm rust aerial haze
	rig.fog_density = 0.006               # moody depth, like Ring 2
	rig.ambient_color = Color("d8c4ac")   # warm sandy fill (keeps albedo, warms shadows)
	rig.key_light_color = Color("e8c088") # warm forge-lit key
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
	rng.seed = 44  # Ring 4's own scatter seed (1=7, 2=12, 3=31)

	# --- The canyon void below: a large deep-warm plane so far edges fade to rust
	# haze instead of a hole. ---
	var land := CSGBox3D.new()
	land.size = Vector3(300.0, 2.0, 300.0)
	land.position = Vector3(0.0, -6.0, 0.0)
	land.material = _mat(COL_VOID)
	add_child(land)

	# --- Main walkable plateau (28 x 22, universal footprint) — the lit sandy floor ---
	var plateau := CSGBox3D.new()
	plateau.size = Vector3(28.0, 1.0, 22.0)
	plateau.position = Vector3(0.0, 0.0, 0.0)
	plateau.material = _mat(COL_GROUND)
	add_child(plateau)

	# Worn / lit floor patches break the flat plateau colour (some pale-lit, some
	# scorched). The scorch uses a MID terracotta (COL_WALL), not the darkest channel
	# shadow — a dark warrior standing on a near-black patch would lose its read.
	for n in range(9):
		var lit := n % 3 == 0
		var patch := _box(
			Vector3(rng.randf_range(3.0, 6.0), 0.06, rng.randf_range(3.0, 6.0)),
			COL_GROUND_LIT if lit else COL_WALL
		)
		patch.position = Vector3(rng.randf_range(-11.0, 11.0), 0.5, rng.randf_range(-8.5, 8.5))
		patch.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		add_child(patch)

	# --- Central Shaper mechanism: a gold ring array with a forge-glow core (the
	# "mechanism's reach"; the centrepiece, like Ring 3's glyph array but warm). ---
	add_child(_make_mechanism(Vector3(0.0, 0.52, 0.0)))

	# --- Terraced canyon walls framing the play area (the signature Deep Canals
	# silhouette — Shaper-carved levels stepping up beyond the footprint). ---
	var wall_specs := [
		[Vector3(-18.0, -1.0, -2.0), 90.0], [Vector3(18.0, -1.0, 3.0), -90.0],
		[Vector3(-4.0, -1.0, -15.0), 0.0], [Vector3(6.0, -1.0, 15.0), 180.0],
		[Vector3(-16.0, -1.0, 12.0), 45.0], [Vector3(16.0, -1.0, -12.0), -135.0],
	]
	for spec in wall_specs:
		add_child(_make_canyon_wall(spec[0], spec[1], rng))

	# --- Forge-light seams glowing from below in the channels around the plateau. ---
	var seam_specs := [
		[Vector3(-14.5, 0.1, 4.0), 8.0, 8.0], [Vector3(14.5, 0.1, -3.0), 7.0, -10.0],
		[Vector3(2.0, 0.1, -12.0), 6.0, 90.0],
	]
	for spec in seam_specs:
		add_child(_make_forge_seam(spec[0], spec[1], spec[2]))

	# --- The cool drained canal: the single cold contrast. Kept close to the play
	# edge (just past +x) with its own cool light so the warm environment doesn't
	# wash it grey-brown before the palette snap. ---
	add_child(_make_drain(Vector3(15.5, 0.0, 5.5), Vector2(7.0, 5.0)))

	# --- Rose canal flora clustered along the plateau edges (the "heated rose"
	# signature; peripheral so the lit centre stays readable). ---
	var cluster_anchors := [
		Vector3(-11.5, 0.5, 7.0), Vector3(11.0, 0.5, 6.5), Vector3(-11.0, 0.5, -7.5),
		Vector3(10.5, 0.5, -7.0), Vector3(-12.5, 0.5, 0.0), Vector3(0.0, 0.5, 9.5),
		Vector3(-5.0, 0.5, -9.5),
	]
	for a in cluster_anchors:
		add_child(_make_flora_cluster(a, rng))

	# Scattered single flora for density; keep the central walkable band clear.
	for n in range(26):
		var pos := Vector3(rng.randf_range(-12.0, 12.0), 0.5, rng.randf_range(-9.5, 9.5))
		if absf(pos.x) < 4.5 and absf(pos.z) < 4.5:
			continue
		add_child(_make_flora_spike(pos, rng.randf_range(0.5, 1.5), rng))

	# --- A couple of plank bridges crossing the channels at the periphery. ---
	add_child(_make_bridge(Vector3(-13.5, 0.5, -3.0), 6.0, 12.0))
	add_child(_make_bridge(Vector3(13.0, 0.5, 9.0), 5.0, -70.0))


# The Shaper mechanism: a dark sunken disc, a gold concentric ring with radial
# spokes, and a raised forge-glow core (with a warm omni) — "the machinery remembers".
func _make_mechanism(pos: Vector3) -> Node3D:
	var mech := Node3D.new()
	mech.position = pos
	var base := CSGCylinder3D.new()
	base.radius = 3.2
	base.height = 0.08
	base.material = _mat(COL_WALL_DARK)
	mech.add_child(base)
	var ring := CSGCylinder3D.new()
	ring.radius = 2.6
	ring.height = 0.12
	ring.material = _mat(COL_AMBER_BRIGHT)
	mech.add_child(ring)
	var inner := CSGCylinder3D.new()
	inner.radius = 2.1
	inner.height = 0.14
	inner.position = Vector3(0.0, 0.01, 0.0)
	inner.material = _mat(COL_SHADOW)
	mech.add_child(inner)
	# Radial gold spokes (the cracked mechanism's reach).
	for i in range(8):
		var spoke := _box(Vector3(0.16, 0.13, 2.3), COL_AMBER_BRIGHT)
		spoke.position = Vector3(0.0, 0.03, 0.0)
		spoke.rotation_degrees.y = i * 22.5
		mech.add_child(spoke)
	# Forge-glow core sunk in the centre + a warm local light.
	var core := _box(Vector3(0.9, 0.5, 0.9), COL_FORGE)
	core.position = Vector3(0.0, 0.3, 0.0)
	core.rotation_degrees.y = 45.0
	mech.add_child(core)
	var glow := OmniLight3D.new()
	glow.light_color = COL_FORGE
	glow.light_energy = 6.0
	glow.omni_range = 8.0
	glow.position = Vector3(0.0, 0.8, 0.0)
	mech.add_child(glow)
	return mech


# A terraced canyon wall: stacked amber slabs stepping up and back beyond the
# footprint, giving the carved-canyon depth silhouette.
func _make_canyon_wall(base_pos: Vector3, yaw_deg: float, rng: RandomNumberGenerator) -> Node3D:
	var wall := Node3D.new()
	wall.position = base_pos
	wall.rotation_degrees.y = yaw_deg
	var steps := rng.randi_range(3, 4)
	var palette_steps := [COL_WALL_DARK, COL_WALL, COL_TERRACOTTA, COL_WALL_LIT]
	var width := rng.randf_range(7.0, 11.0)
	var y := 0.0
	var z := 0.0
	for i in range(steps):
		var h := rng.randf_range(2.0, 3.4)
		var slab := _box(Vector3(width, h, 3.0), palette_steps[i % palette_steps.size()])
		slab.position = Vector3(0.0, y + h * 0.5, z)
		wall.add_child(slab)
		# A lit amber lip on the front edge of each terrace.
		var lip := _box(Vector3(width * 0.92, 0.2, 0.4), COL_AMBER_BRIGHT)
		lip.position = Vector3(0.0, y + h, z + 1.3)
		wall.add_child(lip)
		y += h
		z -= rng.randf_range(2.0, 2.8)  # step back as it rises
		width *= rng.randf_range(0.82, 0.95)
	return wall


# A forge seam: a thin gold glow strip sunk into a channel, with a modest warm
# omni so it reads as light welling up from below.
func _make_forge_seam(pos: Vector3, length: float, yaw_deg: float) -> Node3D:
	var seam := Node3D.new()
	seam.position = pos
	seam.rotation_degrees.y = yaw_deg
	var glow := _box(Vector3(0.5, 0.16, length), COL_FORGE)
	seam.add_child(glow)
	var light := OmniLight3D.new()
	light.light_color = COL_FORGE
	light.light_energy = 4.0
	light.omni_range = 6.0
	light.position = Vector3(0.0, 0.6, 0.0)
	seam.add_child(light)
	return seam


# The drained canal: a recessed cool basin with a dark bottom, a lit blue-grey
# water surface, low rim walls, and a local cool light to hold it cool against the
# warm environment.
func _make_drain(pos: Vector3, size: Vector2) -> Node3D:
	var drain := Node3D.new()
	drain.position = pos
	# Recessed basin (dark water sunk below plateau level).
	var basin := _box(Vector3(size.x, 1.4, size.y), COL_WATER_DARK)
	basin.position = Vector3(0.0, -0.7, 0.0)
	drain.add_child(basin)
	# Lit water surface skim.
	var surface := _box(Vector3(size.x * 0.86, 0.08, size.y * 0.86), COL_WATER)
	surface.position = Vector3(0.0, -0.1, 0.0)
	drain.add_child(surface)
	# Low amber rim around the basin.
	for spec in [
		[Vector3(size.x, 0.5, 0.5), Vector3(0.0, 0.0, size.y * 0.5)],
		[Vector3(size.x, 0.5, 0.5), Vector3(0.0, 0.0, -size.y * 0.5)],
		[Vector3(0.5, 0.5, size.y), Vector3(size.x * 0.5, 0.0, 0.0)],
		[Vector3(0.5, 0.5, size.y), Vector3(-size.x * 0.5, 0.0, 0.0)],
	]:
		var rim := _box(spec[0], COL_WALL_DARK)
		rim.position = spec[1]
		drain.add_child(rim)
	# Cool local light so the drain reads cold amid the warm canyon.
	var light := OmniLight3D.new()
	light.light_color = COL_WATER
	light.light_energy = 3.5
	light.omni_range = 7.0
	light.position = Vector3(0.0, 1.2, 0.0)
	drain.add_child(light)
	return drain


# A plank bridge crossing a channel — pale tan planks on a dark stringer.
func _make_bridge(pos: Vector3, length: float, yaw_deg: float) -> Node3D:
	var bridge := Node3D.new()
	bridge.position = pos
	bridge.rotation_degrees.y = yaw_deg
	var deck := _box(Vector3(1.8, 0.12, length), COL_GROUND_LIT)
	bridge.add_child(deck)
	var stringer := _box(Vector3(2.0, 0.3, length * 0.96), COL_WALL_DARK)
	stringer.position = Vector3(0.0, -0.18, 0.0)
	bridge.add_child(stringer)
	return bridge


func _make_flora_cluster(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var cluster := Node3D.new()
	cluster.position = pos
	for i in range(rng.randi_range(4, 8)):
		var off := Vector3(rng.randf_range(-1.4, 1.4), 0.0, rng.randf_range(-1.4, 1.4))
		var spike := _make_flora_spike(off, rng.randf_range(0.7, 2.2), rng)
		cluster.add_child(spike)
	return cluster


# A single tapered rose canal-flora spike (a thin jittered box) — luminous rose
# against the warm canyon floor.
func _make_flora_spike(pos: Vector3, height: float, rng: RandomNumberGenerator) -> Node3D:
	var stalk := Node3D.new()
	stalk.position = pos
	var col := COL_FLORA if rng.randf() < 0.6 else COL_FLORA_DEEP
	var w := rng.randf_range(0.10, 0.22)
	var spike := _box(Vector3(w, height, w), col)
	spike.position = Vector3(0.0, height * 0.5, 0.0)
	spike.rotation_degrees = Vector3(
		rng.randf_range(-10.0, 10.0), rng.randf_range(0.0, 360.0), rng.randf_range(-10.0, 10.0)
	)
	stalk.add_child(spike)
	# A bright rose bud near the tip on the taller spikes.
	if height > 1.2:
		var bud := _box(Vector3(w * 1.8, w * 1.8, w * 1.8), COL_FLORA)
		bud.position = Vector3(0.0, height * 0.95, 0.0)
		stalk.add_child(bud)
	return stalk
