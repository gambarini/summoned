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
