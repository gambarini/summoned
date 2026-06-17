extends Node

const MAX_GRIEF := 10
const MAX_RING := 5
## Highest ring with authored 3D terrain (see main.gd's _make_ring_world). Rings
## above this fall back to Ring 1's geometry, so progression is capped here until
## rings 4–5 are built — bump as each ring lands.
const HIGHEST_BUILT_RING := 3
var run_count: int = 0
var grief_reserve: int = MAX_GRIEF
var extractions: int = 0
var clock_ticks: int = 0
## Which ring the next/current run takes place in (1..MAX_RING). `main.gd` reads
## this to pick the 3D terrain + per-ring enemy spawns. Progression rule is a
## minimal placeholder (extract advances a ring, death resets to 1) pending the
## real run-structure design — see `advance_ring()` / `reset_ring()`.
var current_ring: int = 1

func starting_coherence() -> int:
	if grief_reserve >= 7:
		return 10
	elif grief_reserve >= 4:
		return 7
	return 4

func advance_clock() -> void:
	clock_ticks = mini(clock_ticks + 1, 10)

func is_last_song() -> bool:
	return clock_ticks >= 10

## Placeholder progression: a successful extraction pushes deeper one ring. Capped
## at HIGHEST_BUILT_RING so extraction never lands on an unbuilt ring (which would
## render Ring 1's terrain mislabeled).
func advance_ring() -> void:
	current_ring = mini(current_ring + 1, HIGHEST_BUILT_RING)

## Placeholder progression: dying ends the run, so the next summon starts at Ring 1.
func reset_ring() -> void:
	current_ring = 1
