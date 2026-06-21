extends RefCounted
class_name SimSpace

## Shared sim<->world transform for the Ring 1 hybrid layer (Option B).
##
## The 2D sim (`CharacterBody2D` positions, px) is the single source of truth;
## the 3D layer is presentation. This is the *one* place that maps between them,
## used by `WarriorSync` (player billboard), `WorldSync` (enemy/arc billboards),
## and the mouse->world attack aim (which needs the inverse, `to_sim`).
##
## These constants are UNIVERSAL across all rings, not ring-specific (Phase 5
## locked PPU=18). They must be: the warrior billboard's `pixel_size` and the 2D
## sim's 100 px/s speed are fixed, so a per-ring PPU would change the warrior's
## on-screen size and movement feel between rings. Per-ring variation belongs in
## the *terrain* (each ring's geometry), not in this transform.
##
## Forward constraint for new rings (2-5): with PPU=18 and the shared 480x270
## wall box, the warrior's reachable world footprint is x in [-13.0, 13.0],
## z in [-6.94, 6.94] (the roam box minus the 6px collision half-width). Every
## ring's playable terrain must cover at least that — target ~+-14 x +-8 for ~1u
## of margin so the warrior never teeters on the terrain lip (see MIGRATION_3D
## Phase 5; Ring 1's plateau was widened 26->28 for exactly this).
##
## Mapping: sim `(x, y)` px, origin at the play-area centre, 2D y-down -> 3D +z.
## `world = Vector3((x - 240)/PPU, height, (y - 135)/PPU)`. Verified numerically
## in Phase 2 (yaw135's asymmetric x!=z rules out a transpose).

# PPU=18 sits between two anchors: plateau width (480/26 ≈ 18.5) and the spike's
# tuned 6 u/s feel (warrior SPEED 100 px/s -> 100/6 ≈ 16.7). Locked in Phase 5.
const PIXELS_PER_UNIT := 18.0
const SIM_ORIGIN := Vector2(240.0, 135.0)  # 2D play-area centre -> world origin

# --- Play-area size (the one knob) ---------------------------------------
## Arena multiplier vs the original 480x270 sim box. 1.0 = the legacy single-screen
## arena; >1 grows the playable box symmetrically about SIM_ORIGIN so existing
## spawns + the world-centred terrain stay put and only the extents widen. 4.0 is
## the "explore-scale" arena: ~1920x1080 sim px -> ~+-53 x +-30 world units, a space
## the follow camera scrolls across (warrior size/speed are unchanged). The walls
## (main.gd), enemy spawn spread (main.gd), and every ring's terrain extent read
## this through the helpers below -- never hardcode the box size in those files.
const PLAY_SCALE := 4.0
## Half-size of the ORIGINAL 480x270 box (its centre is SIM_ORIGIN).
const _BASE_HALF_PX := Vector2(240.0, 135.0)


## Play-area half-extents in sim px (SIM_ORIGIN +- this is the wall box).
static func half_px() -> Vector2:
	return _BASE_HALF_PX * PLAY_SCALE


## Play-area half-extents in WORLD units -- terrain builders size the walkable
## ground to cover at least this (plus a margin) so the warrior never walks off it.
static func half_world() -> Vector2:
	return half_px() / PIXELS_PER_UNIT


## Wall box corners in sim px.
static func box_min_px() -> Vector2:
	return SIM_ORIGIN - half_px()


static func box_max_px() -> Vector2:
	return SIM_ORIGIN + half_px()


## A scatter point for graduated-density terrain fill: a random point inside +-half
## (world units, small inset) accepted with probability that falls off with distance
## from centre -- dense near `hub_radius`, sparse at the rim. Returns Vector3.INF when
## rejected, and always rejects inside `hub_radius` (the authored central hub). y is
## 0.5 (the plateau top). Shared by every ring builder's expanse fill.
static func scatter_point(rng: RandomNumberGenerator, half: Vector2, hub_radius: float) -> Vector3:
	var x := rng.randf_range(-half.x + 0.5, half.x - 0.5)
	var z := rng.randf_range(-half.y + 0.5, half.y - 0.5)
	var d := Vector2(x, z).length()
	if d < hub_radius:
		return Vector3.INF
	var max_d := half.length()
	var t := clampf(1.0 - (d - hub_radius) / maxf(1.0, max_d - hub_radius), 0.15, 1.0)
	if rng.randf() > t:
		return Vector3.INF
	return Vector3(x, 0.5, z)


## Sim px -> world units. `height` is the 3D Y (presentation-only "hover").
static func to_world(sim: Vector2, height: float) -> Vector3:
	return Vector3(
		(sim.x - SIM_ORIGIN.x) / PIXELS_PER_UNIT,
		height,
		(sim.y - SIM_ORIGIN.y) / PIXELS_PER_UNIT
	)


## World units -> sim px (drops Y; the sim is planar). Inverse of `to_world`.
static func to_sim(world: Vector3) -> Vector2:
	return Vector2(
		world.x * PIXELS_PER_UNIT + SIM_ORIGIN.x,
		world.z * PIXELS_PER_UNIT + SIM_ORIGIN.y
	)
