# Ring Scenario Backlog

Turns the GDD-vs-built gap (rings are terrain+palette only; combat = 3 generic enemies
scattered in a box) into a prioritized build plan. Ordered to **prove the avoidance-first
combat design in one ring before mass-producing creatures** — that design is the GDD's
core bet and is currently unproven in code.

Sizes: S = hours, M = a day or two, L = multi-day.

**Art pattern (locked 2026-06-30):** the game has moved fully to 3D — billboard sprites and
2D pixel art are deprecated. Every character/creature follows the **warrior pattern**: the
2D sim (`CharacterBody2D`) stays the authoritative gameplay logic (Option B hybrid), but its
*presentation* is a procedural low-poly cel-shaded **3D mesh** driven by a `*_sync.gd`
(see `warrior_mesh.gd` + `warrior_sync.gd`). So "build a creature" = sim profile (F1) +
a `creatureN_mesh.gd` (Node3D rig) + a sync that drives it. The current `enemy.gd` Polygon2D
billboards are placeholders to be replaced under this pattern.

---

## P0 — Foundations (unblock everything; build before any creature)

- **F1. Data-driven creature state machine** — _L_
  Replace `enemy.gd`'s `IDLE/CHASE/ATTACK/DEAD` + binary `DISSONANT/HARMONIC` with a
  per-creature emotional state machine (N states, transitions, per-state Resonance "tell",
  frequency that can **shift mid-encounter**). This is the spine every GDD creature needs.
  Keep the existing 3 enemies working as the simplest profile.

- **F2. Resonance read + tell surfacing** — _M_
  A player "pulse" action that reveals a creature's current state/tell (extend the existing
  `reveal()`/`receive_hit()`). Without this, none of the read-based encounters are playable.
  Depends on F1.

- **F3. Objective + extraction gate** — _M_  (also CLAUDE.md "Next" #1) — ✅ **DONE**
  Rings get a goal (reach/clear/observe) and an **exit** that drives `current_ring + 1`.
  Built as a reach-type **extraction gate**: `main.gd` places one gate per run (far-edge
  default, ring override via `extraction_point()`), builds a 3D beacon, and arms
  `warrior.can_extract` on proximity; `warrior._do_extract()` is now gated on it so the
  `extract` (F) action only fires at the gate. Reach-only (avoidance-first); a later
  objective-gated ring keeps `can_extract` false until its objective clears (one seam in
  `_tick_extraction_gate`). Closes the progression loop; does **not** make combat
  mandatory — that's C3. Verified: reach gate → `current_ring` 1→2 → `base.tscn`.

## P1 — Ring 1 vertical slice (prove the loop end-to-end)

Pick Ring 1 — it's the tutorial ring, already the most polished, and its 2 creatures are
the simplest. Goal: one ring that plays the GDD way (read → avoid/pacify/intervene, fight
only on failure), with a real objective.

- **R1a. The Pale Herd** — _M_  — Calm→Uneasy→Scattered; collective hum; fragments on threat,
  never fights. Teaches the **baseline calm read**. Depends on F1/F2. — ✅ **DONE**
  (`creature_pale_walker.gd` + `pale_walker_mesh.gd`, 2026-07-03: detection web propagates
  alerts herd-wide, scatter fans individual vectors, lone animals can't re-calm without the
  collective; cel-mesh from day one — verified in-engine.)
- **R1b. The Threshold** — _M_ — Still→Assessing→Committed→Withdrawn; the **intervention
  window** (project any frequency during Assessing → it withdraws). Teaches Resonance as
  decision-changer, with a real cost for missing the window. Depends on F1/F2.
- **R1c. Ring 1 objective + traversal reason** — _S_ — wire F3 into ring1_world (a goal worth
  crossing the arena for). Depends on F3.
- **R1d. Drifting Scouts signal** — _S_ — wind-borne info pings ("something now knows I'm
  here"). Flavor + teaches world-as-system. Optional for the slice.
- **R1e. Directional wind field** — _S_ — movement cost up/downwind, carries frequency ahead.
  Pure flavor; lowest priority in the slice.

**Gate:** if R1a/R1b/R1c don't feel good, fix the combat design here — cheap — before P2/P3.

## P2 — Combat depth + structure (generalize the slice)

- **C1. Coherence as read-state** — _M_ — high/low/Hollow drives power-vs-control; Hollow
  drains Grief Reserve (ties to meta-economy). Some `pacify()` plumbing exists.
- **C2. Echo Chain 1–5** — _L_ — correct reads build a chain; Chain 4 Harmonic Burst; Chain 5
  Songs (dissonant/harmonic). The skill-expression layer.
- **C3. Structured generator** — _L_  (CLAUDE.md "Next" #2) — replace open-box scatter with
  territories / chokepoints / cover / patrol rhythms so seeds play different, not just look
  different. Creature territories (P1+) give this its content.

## P3 — Expand rings + meta-economy + endgame

- **Ring 2–5 creature sets** — _L each_ — 2–3 signature creatures per ring, each adding ONE
  new teach (R2 Claim/acoustic-passage + first corrupted; R3 Still-Watchers no-combat-
  resolution + Mirror-Kind heal-off; R4 Canal Hunter positional + Paired + Ancient Deep song
  duel; R5 read-blind + The Still). Plus per-ring terrain features (R4 canyon/two-layer).
- **Factions + standing** — _M_ — Watcher outposts (R2–3), Shaper patrols (R4), persistent
  standing gating deep zones.
- **Echo memories + lore** — _M_ — placed fragments (R2 ruins, R3 carvings, R4/R5 Echo) +
  Memory-Keeper interpret on return.
- **Meta-economy fix** — _M_  (CLAUDE.md "Next" #3) — a Grief *source* (not just −1/death) and
  a clock-10 ("LAST SONG") win/lose resolution; tribe-phase gating of ring access.
- **Still Heart endgame** — _L_ — mechanism-as-place + the final choice. Last, by design.

---

## Recommended first move

**F1 → F2 → R1a + R1b → F3 → R1c.** That's the smallest path to a Ring 1 that actually plays
the GDD way and progresses on objective completion. Everything else replicates a proven
pattern; this de-risks it.
