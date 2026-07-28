class_name CreatureRoster
extends RefCounted

## The per-ring creature table — what living things a ring holds, how many, and where
## they stand. Replaces the hard-coded `_spawn_test_creatures()` / `_spawn_test_herd()`
## harness that used to sit in `main.gd`, so adding a creature to a ring is a table edit
## here rather than another bespoke spawn function in the run scene (roadmap 4).
##
## Creatures are deliberately NOT the enemy pockets (`main.gd`'s SPAWN_MIX): pockets are
## the hostile husks the warrior sweeps, creatures are the ring's *life* — some hostile,
## some not. They keep their own placement rules and their own seeds, and the clear-count
## still keys on each one's `is_hostile()` (see clear_tracker.gd).
##
## Entry schema (every key but `script` and `seed` is optional):
##
##   script    res:// path to a `Creature` subclass. Its `class_name` must appear in
##             `WorldSync.CREATURE_MESH_SCRIPTS` or it falls back to the deprecated
##             billboard path — `mesh_gaps()` asserts this and the suite checks it.
##   count     Vector2i(min, max) inclusive; equal values pin the count.
##   placement SCATTERED — each animal placed independently.
##             COLLECTIVE — one group centre, members spread around it, then wired.
##   band      Vector2(min_px, max_px) distance from the summon point. Omit for a
##             uniform scatter over the whole arena. The arena is `PLAY_SCALE`-huge, so
##             a band is what keeps a 3-animal entry an encounter rather than a needle
##             in a field; `min_px` is raised to the caller's home-safe radius.
##   spread    COLLECTIVE only — px radius of the group around its centre.
##   wire      COLLECTIVE only — method handed the FULL group array (self included) on
##             every member. For the Pale Herd that array *is* the detection web.
##   seed      Local seed constant, offset per run by `GameState.ring_seed()`. Block
##             3000+ is reserved for creatures (terrain uses 5..59, pockets 1001..1005).
##
## Placement always honours the caller's spawn hygiene: nothing lands inside the
## home-safe radius around the summon point, and everything stays inside the
## margin-inset `SimSpace` box, so it scales with `SimSpace.PLAY_SCALE`.

enum Placement { SCATTERED, COLLECTIVE }

const RING_CREATURES := {
	1: [
		# The Threshold: Ring 1's intervention lesson. Banded close to the summon point
		# so leaving home is the encounter — but outside the home-safe radius, so the
		# warrior walks into it rather than materialising in its space.
		{
			"script": "res://scripts/creature_threshold.gd",
			"count": Vector2i(3, 3),
			"placement": Placement.SCATTERED,
			"band": Vector2(300.0, 560.0),
			"seed": 3101,
		},
		# The Pale Herd: the baseline-calm teacher. One collective, wired to itself.
		{
			"script": "res://scripts/creature_pale_walker.gd",
			"count": Vector2i(7, 7),
			"placement": Placement.COLLECTIVE,
			"band": Vector2(420.0, 780.0),
			"spread": 60.0,
			"wire": "set_herd",
			"seed": 3102,
		},
	],
	# PLACEHOLDER — proves a ring gains creatures by editing this table and nothing
	# else. Ring 2's real roster (the claim/acoustic-passage creature and the first
	# corrupted one) lands with roadmap items 22 and 23, which replace this entry.
	2: [
		{
			"script": "res://scripts/creature_threshold.gd",
			"count": Vector2i(2, 2),
			"placement": Placement.SCATTERED,
			"band": Vector2(340.0, 700.0),
			"seed": 3201,
		},
	],
}

const _PLACE_TRIES := 24  # band samples before falling back to a uniform box scatter


## Spawn a ring's whole roster under `parent`, registering each creature with the run's
## clear tracker (which turns the non-hostile ones away itself). `home_safe` and `margin`
## are the caller's spawn hygiene — the same numbers `main.gd` uses for enemy pockets.
## Returns every spawned node, in table order.
static func spawn(parent: Node, ring: int, tracker: RefCounted, home_safe: float, margin: float) -> Array:
	var spawned: Array = []
	var table: Array = RING_CREATURES.get(ring, [])
	var lo: Vector2 = SimSpace.box_min_px() + Vector2(margin, margin)
	var hi: Vector2 = SimSpace.box_max_px() - Vector2(margin, margin)
	for entry in table:
		spawned.append_array(_spawn_entry(parent, entry as Dictionary, tracker, lo, hi, home_safe))
	return spawned


## Roster entries whose creature has no cel-mesh in `WorldSync.CREATURE_MESH_SCRIPTS`
## and would therefore render through the deprecated billboard fallback. Empty is the
## only acceptable answer; the test suite asserts it.
static func mesh_gaps() -> Array:
	var gaps: Array = []
	for ring in RING_CREATURES:
		for entry in RING_CREATURES[ring]:
			var path: String = String((entry as Dictionary)["script"])
			var script: GDScript = load(path)
			var cls: StringName = script.get_global_name() if script != null else &""
			if not WorldSync.CREATURE_MESH_SCRIPTS.has(cls):
				gaps.append("ring %d: %s" % [ring, path])
	return gaps


# ── Spawning ────────────────────────────────────────────────────────────────

static func _spawn_entry(parent: Node, entry: Dictionary, tracker: RefCounted,
		lo: Vector2, hi: Vector2, home_safe: float) -> Array:
	var script: GDScript = load(String(entry["script"]))
	if script == null:
		push_warning("CreatureRoster: cannot load %s" % entry["script"])
		return []
	# One RNG per entry, seeded from the run: same run_seed -> same layout, and the
	# entries don't correlate with each other or with the terrain/pocket layers.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = GameState.ring_seed(int(entry["seed"]))

	var count: Vector2i = entry.get("count", Vector2i(1, 1))
	var n: int = rng.randi_range(count.x, count.y)
	var band: Vector2 = entry.get("band", Vector2.ZERO)
	var collective: bool = int(entry.get("placement", Placement.SCATTERED)) == Placement.COLLECTIVE

	var group: Array = []
	if collective:
		var centre: Vector2 = _pick_point(rng, lo, hi, home_safe, band)
		var spread: float = float(entry.get("spread", 60.0))
		for i in range(n):
			var off: Vector2 = Vector2(
				rng.randf_range(-spread, spread),
				rng.randf_range(-spread, spread)).limit_length(spread)
			group.append(_make(parent, script, i, _legalise(centre + off, lo, hi, home_safe), tracker))
	else:
		for i in range(n):
			group.append(_make(parent, script, i, _pick_point(rng, lo, hi, home_safe, band), tracker))

	# Collective wiring: every member receives the WHOLE group, self included — that
	# shared array is the collective (the herd's detection web), not a convenience.
	var wire: String = String(entry.get("wire", ""))
	if wire != "":
		for m in group:
			if m.has_method(wire):
				m.call(wire, group)
			else:
				push_warning("CreatureRoster: %s has no %s()" % [m.name, wire])
	return group


static func _make(parent: Node, script: GDScript, index: int, pos: Vector2,
		tracker: RefCounted) -> CharacterBody2D:
	var body: CharacterBody2D = script.new() as CharacterBody2D
	body.name = "%s%d" % [String(script.get_global_name()).trim_prefix("Creature"), index]
	parent.add_child(body)
	body.global_position = pos
	if tracker != null:
		# Peaceful life is turned away by the tracker itself (is_hostile()), so the
		# roster registers everything and stays out of the clear-count policy.
		tracker.register(body)
	# NOTE: roster creatures are deliberately NOT force_amplify()'d under Last Song —
	# that escalation is applied to the enemy pockets only, matching the behaviour of
	# the harness this replaces. Amplifying ring *life* is a design call for the
	# Last Song item, not a side effect of moving spawn code.
	return body


# ── Placement ───────────────────────────────────────────────────────────────

# A legal point for one creature: inside the inset box and clear of the summon point.
# With a band, sample by angle+distance around the summon point (the arena is far too
# big for uniform scatter to make a 3-animal entry findable); without one — or if the
# band keeps landing outside the box — fall back to the uniform scatter `_spawn_enemies`
# uses. Hygiene wins over the band either way: `_legalise` is unconditional.
static func _pick_point(rng: RandomNumberGenerator, lo: Vector2, hi: Vector2,
		home_safe: float, band: Vector2) -> Vector2:
	if band.y > 0.0:
		var near: float = maxf(band.x, home_safe)
		var far: float = maxf(band.y, near + 1.0)
		for _try in range(_PLACE_TRIES):
			var p: Vector2 = SimSpace.SIM_ORIGIN \
					+ Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(near, far)
			if p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y:
				return p
	var q: Vector2 = Vector2.ZERO
	for _try in range(_PLACE_TRIES):
		q = Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		if q.distance_to(SimSpace.SIM_ORIGIN) >= home_safe:
			break
	return _legalise(q, lo, hi, home_safe)


# Push a point out of the home-safe bubble, then clamp it into the inset box, so the
# spawn-hygiene invariant holds for every creature however it was sampled.
static func _legalise(p: Vector2, lo: Vector2, hi: Vector2, home_safe: float) -> Vector2:
	var from_home: Vector2 = p - SimSpace.SIM_ORIGIN
	var d: float = from_home.length()
	if d < home_safe:
		var dir: Vector2 = from_home / d if d > 0.01 else Vector2.RIGHT
		p = SimSpace.SIM_ORIGIN + dir * home_safe
	return p.clamp(lo, hi)
