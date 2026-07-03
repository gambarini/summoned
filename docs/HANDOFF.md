# Handoff — Ring "scenario" buildout + combat feel

Paste-ready context for continuing in a new session. Two active tracks: the ring
scenario layer (below, F1–F3/R1c done) and the **combat feel pass** (passes 1–4 done
2026-07-02; the remaining backlog is in that section).

## Context

The game pivoted to fully-3D art (procedural cel-shaded meshes, the warrior pattern);
billboards / 2D-pixel art are deprecated. The 2D sim stays the authoritative gameplay
logic (Option B hybrid) — only *presentation* is 3D mesh. The GDD's five rings are built
as terrain/palette only; the entire "scenario" layer (creatures + their Resonance /
emotional-state machines, avoidance-first combat, objectives, factions, lore) is unbuilt.
We're building that out via `docs/RING_BACKLOG.md`.

**Read first:** `docs/RING_BACKLOG.md` (the plan), plus memory files
`creature_framework_f1.md`, `art_direction_3d.md`, and `godotiq_live_test_gotchas.md`.

## Just completed — Combat feel pass 1 (2026-07-02, verified in-engine)

From a full warrior-controls review (user: swordplay "not precise, dynamic, fast paced").
The conclusion: the swing animation itself is fine; the problems were around it — dropped
inputs, a press dead-zone, hits decoupled from the blade, enemies that ignore being hit,
zero audio. Landed this session:

- **Input buffering** (`warrior.gd`): `INPUT_BUFFER 0.15s`; `_unhandled_input` no longer
  hard-drops per state (only DYING/SUMMONING ignore input) — attack/dash presses arm
  `_attack_buffer`/`_dash_buffer`, consumed by `_tick_buffers()` (from `_physics_process`)
  at the first legal frame. Dash outranks attack; an attack buffered during a dash fires
  when it ends (dash→attack for free). `_try_attack()` now returns `bool` (fired or not).
- **Chain retiming**: `warrior.tscn` AttackCooldown 0.35→**0.25**, RecoveryTimer
  0.4→**0.3**; finisher recovery multiplier 1.5→**2.0** in `warrior.gd` (finisher keeps
  its 0.6s weight). Steps 0–2 now chain at ~0.25s/swing; the old 0.15s press dead-zone
  (cooldown outlasting startup+active with no buffer) is gone.
- **Enemy hit reactions** (`enemy.gd`): `HITSTUN_DURATION 0.22`, `KNOCKBACK_SPEED 140`
  (decay lerp 8/s). `_tick_hit_reaction()` owns the frame while staggered (no chase; the
  pending `_do_attack` tick is gated too); `_stagger()` on a CORRECT non-lethal hit shoves
  away from `_player` (stun-only when `_player` is null) + a squash-pop tween.
  `enemy_fleer.gd`'s replaced `_physics_process` got the same early-out; phaser inherits
  via `super`. `receive_hit(freq)` signature UNCHANGED — the duck-typed contract with
  `creature.gd`/`test_runner.gd` is intact. **`creature.gd` has NO stagger yet** — bake
  the same pattern into the creature framework when touching it.
- Verified live: a `set_meta` swing-counter hooked to `StartupTimer.timeout` proved a
  press injected mid-startup (previously dropped) auto-chains swing 2; a scripted CORRECT
  hit gave 0.22s stun + 13.6px shove + settled pop; whole project compiles (39 scripts,
  0 errors); real-input mash at the new cadence + dash ran with a clean console.

## Just completed — Combat feel pass 2 (2026-07-02, verified in-engine)

Backlog items 1+2 (hit window + hitstop targeting):

- **Hit window ≈ the strike** (`attack_arc.gd`): the wedge now stops registering after a
  per-step hit window (`HIT_STEPS`: 0.13s for steps 0–2, 0.17s for the thrust finisher —
  ≈ ATTACK_ACTIVE 0.083/0.125 + a hair of early recovery) via a physics-clock tween that
  flips `HitArea.monitoring` off; the 0.32s DURATION is now purely the visual fade tail.
  Travel compressed to `TRAVEL_TIME 0.16s` (was the full 0.32s) so the blade crosses the
  corridor inside the window. Window ends before the earliest chained next-startup
  (cooldown 0.25 from startup entry), so no more hits ~0.3s after the pose or spilling
  into the next windup.
- **Per-step hit shapes** (`attack_arc.gd` + `warrior.gd`): `set_direction(dir, combo_step)`
  builds the hit polygon per step, mirroring `WarriorSync._make_slash_mesh` — wide 70°/59°
  crescents (36/38px) for the horizontal/rising cuts, a 40°/44px focused chop, a 20°/50px
  +64px-travel spike for the thrust (it no longer hits with a wide side wedge). `warrior.gd`
  passes `_combo_step`; `_on_hit`'s stale "accept the entire travel" comment updated.
- **Hitstop gated to the strike pose** (`warrior_sync.gd` `_on_melee_hit`): only arms when
  `vfx_state()` is ATTACK_ACTIVE/ATTACK_RECOVERY, so a stale hit can't freeze the next
  swing's windup.
- Verified live via exec/meta-probes: step-0 vs step-3 wedge = 36px/70° vs 50px/20°;
  monitoring true at 80ms → false at 200ms with the arc still fading; hitstop 0 on an
  IDLE-state emit, 0.07 on ACTIVE/RECOVERY; a real buffered swing landed on a live enemy
  (`melee_hit` fired, enemy shoved ~22px); console clean; 3 scripts compile 0 errors.
- NOT done from the item-2 "consider" list: freezing the struck enemy for the hitstop
  beat, and a camera kick (still NO screen shake anywhere in the project).

## Just completed — Combat feel pass 3 (2026-07-02, verified in-engine)

Backlog item 1 (attack movement rules):

- **Damped drift replaces the stop-go** (`warrior.gd` `_handle_movement`): the three
  attack states get their own branch — `velocity.lerp(dir * SPEED * ATTACK_DRIFT(0.4),
  ATTACK_DRIFT_DAMP(9.0) * delta)`. Startup no longer hard-roots (momentum carries in,
  ~91→59 px/s over the 0.117s), and active/recovery no longer fall through to the
  full-speed default branch (they damp to the ~40px/s steerable drift floor instead of
  sliding at 100).
- **Sim-side forward step** (`warrior.gd` `_enter_state` ATTACK_ACTIVE): `velocity =
  _attack_dir * ATTACK_STEP_SPEED(130)`, ×`ATTACK_STEP_FINISHER(1.6)` on the thrust
  (step 3). The drift branch bleeds it out; net step ≈ 12px per swing, wall-honest via
  `move_and_slide`.
- **`LUNGE_PX` lie deleted** (`warrior_sync.gd`): `_sync_position`'s push is now recoil
  only — the mesh just tracks the body. (The −0.25×12px windup back-shift went with it;
  the mesh's own arm draw-back still carries the anticipation.)
- Verified live via physics-frame samplers: stationary swing displaces 12.17px exactly
  along `_attack_dir`; move-attack timeline MOVE(100) → startup 91→59 → active fires at
  130 → recovery settles to the drift floor 22→36 → clean re-accel to 100 (velocity never
  0, never 100 mid-swing); mesh-to-body sim gap 0.0px on every frame of a swing (was up
  to 12px at `_atk`=1); console clean; both scripts compile 0 errors.

## Just completed — Combat feel pass 4 (2026-07-02, verified in-engine)

Backlog item 1 (dash identity — range, mesh read, dash-cancel):

- **Range doubled** (`warrior.gd`): `DASH_SPEED` 320→**560**, `DASH_DURATION` 0.18→**0.22**
  — measured 121.3px per dash (~152px with the decel tail), was ~58px. `DASH_COOLDOWN`
  stays 0.7; i-frames still span the whole DASH state.
- **Dash-cancel into attack** (`warrior.gd` `_try_attack`): new DASH branch — a buffered
  attack cancels the dash once `DASH_ATTACK_CANCEL_AFTER` (**0.10s**) of commit has passed
  (so the i-frame blip still reads). The 560px/s dash velocity feeds straight into the
  attack states' damped drift, so dash-attack is a genuine lunge; pre-window presses stay
  buffered and fire at the first legal frame as before.
- **DASH read on the mesh** (`warrior_sync.gd`): `_dash_lean` (0..1, in at 16/s ≈ full in
  0.06s, out at 7/s) drives `_mesh.rotation.x = DASH_LEAN(0.42) * lean` — a ~24° forward
  pitch about the post-yaw local X (composes with `_sync_facing`'s rotation.y, YXZ order,
  pivots at the feet). Cape flares `+0.30 * lean`; `_update_notation_emission` gets a DASH
  branch pinning `amount_ratio = 1.0` — the world-space emitter turns that into a glyph
  streak carved along the dash path (the cloak shredding under the burst).
- Verified via a physics-frame probe (per-frame state/pos/lean/ratio metas): clean dash =
  14 DASH frames, 121.3px, lean peak exactly 0.420 → 0.000 after, notation 1.0 → 0.30;
  dash + buffered attack = **7** DASH frames (~0.117s) then ATTACK_STARTUP→ACTIVE→
  RECOVERY→IDLE (full dash is 14 — the cancel fired at the first frame past the window);
  console clean; both scripts compile 0 errors. Numbers-verified only — an eyes-on feel
  check of the lean/trail at speed is still worth a minute.
- Harness note: `godotiq_input` `{"key":"space"}` does NOT trigger the dash — the synthetic
  event lacks `physical_keycode`, which the raw-key binding checks. Drive it in tests via
  `w._start_dash()` (+ `w._attack_buffer = 0.3` for the cancel path); real keyboards fine.

### Combat feel backlog (reviewed, NOT fixed — priority order)

1. **Windup dead-hold**: `_atk` reaches its windup target in ~0.036s then holds static
   for the rest of the 0.117s startup — reads as input lag, not anticipation.
2. **Zero audio in the project** (no AudioStream anywhere): swing whoosh + hit crunch is
   cheaply half of "impact"; even placeholder synth blips would change the feel.
3. **Resonance (R) / Song (G) have no body animation** on the mesh — only the ground disc.
4. **Impact extras** (deferred from pass 2): freeze the struck enemy for the hitstop beat;
   small camera kick on a landed hit (no screen shake exists yet).

## Just completed — F1 (verified in-engine)

- `scripts/creature.gd` — `class_name Creature extends CharacterBody2D`. Thin state-machine
  base built *alongside* `enemy.gd` (NOT a refactor — the verified run loop is untouched).
  Builds its own nodes/collision in code, mirroring `enemy.tscn` layers. Joins the loop via
  the duck-typed group `"enemies"` contract: `receive_hit`/`reveal`/`pacify`/`force_amplify`,
  `enemy_died` signal, static `Freq`/`HitResult` enums (DISSONANT=0 order MUST match
  enemy.gd). `WorldSync` group-scans and needs a child literally named `"Visual"` to build
  the 3D billboard.
- `scripts/creature_threshold.gd` — working Threshold: Still→Assessing→Committed→Withdrawn
  + the Resonance **intervention window** (projecting any frequency during Assessing →
  withdraws). All transitions verified via `exec`.
- `main.gd._spawn_test_creatures()` — TEMP harness: 3 named Thresholds in Ring 1 at fixed
  offsets, OFF the random `SPAWN_MIX` and OFF the `_enemies_alive` clear-count. Remove when
  Thresholds graduate to real spawning.

## Also completed — F2 (verified in-engine)

Gate creature tells behind the Resonance pulse so the **read** action matters.
- `scripts/creature.gd` — `_refresh_visual()` now paints `_tell_color()` only while
  `_revealed`; otherwise the body shows a new shared `HIDDEN_COLOR` (must stay equal to
  `world_sync.gd`'s `NEUTRAL_COLOR` — WorldSync keys the frequency **pip** on exactly that
  colour, so an unread creature draws no pip). Reveal lapse (`_tick_timers`) refreshes back
  to grey. Previously creatures always painted their tell → both the state colour AND the
  frequency pip leaked with no pulse.
- Verified via `exec`: pip gate flips true→false→true (unread grey → `reveal()` surfaces
  COL_STILL → lapses back). The **intervention** now visibly fires: force `ASSESSING`, pulse
  → flips to `WITHDRAWN` with the dim-retreat colour (amber→dim during the window).
- Reach note: `RESONANCE_RADIUS = 120`; the 3 test Thresholds spawn ~148–155px out, so a
  pulse from the warrior's start point does NOT reach them — walk within 120px to read one.
- **The read is visual-only** (colour + pip). Nothing consumes `get_tell()`/`get_state()`
  for a HUD readout yet; a text/HUD read is future scope, not built.

## Also completed — F3 (verified in-engine)

The progression loop is now **spatial**: you descend a ring by *reaching* an extraction
gate, not by pressing F anywhere.
- `scripts/warrior.gd` — new `var can_extract := false`. `_do_extract()` early-returns
  unless it's true, so the `extract` action (**F key**; E/Q are camera orbit) is inert
  away from the gate. Nothing else touches it — the extract tween → `warrior_extracted`
  → `advance_ring()` path (and its `_run_ended` race guard) is unchanged.
- `scripts/main.gd` — one **extraction gate** per run:
  - `_setup_extraction_gate()` places it at `_gate_pos` (ring override via an optional
    `extraction_point()` method, else the default far-edge point `_default_gate_pos()` =
    centre of the north wall, inset `GATE_MARGIN`), and builds a 3D beacon (pad + light
    shaft, unshaded, mounted via `_rig.add_world_child`).
  - `_tick_extraction_gate(delta)` (called from `_process`) arms `$Warrior.can_extract`
    while the warrior is within `GATE_ACTIVATION_RADIUS` (px **distance check**, not an
    Area2D — matches the `_do_resonance` idiom, zero collision config), pulses the beacon
    brighter, and edge-triggers the HUD prompt `"DESCEND: PRESS F"`.
- Verified via `exec`/`state_inspect`: at spawn `can_extract=false` (F does nothing);
  teleport onto the gate → `can_extract=true` + prompt shown → `_do_extract()` →
  `current_ring` **1→2**, `extractions` **0→1**, scene changes to `base.tscn`.
- **Scope boundary (state this so it doesn't read as an oversight):** F3 gives
  progression a *place to reach* — it does NOT make combat mandatory or rewarding. Ring 1
  is reach-only + gate-far (avoidance-first, per the backlog Gate); a fast player can
  still sprint past everything. Putting the gate *behind decisions* is **C3** (structured
  generator), not F3. The gate has one seam for a later objective-gated ring: keep
  `can_extract` false in `_tick_extraction_gate` until the objective clears.

## Also completed — R1c (verified in-engine)

Ring 1's descent gate now lands on an **authored far landmark** instead of the generic
far-edge default.
- `scripts/ring1_world.gd` — new `_build_descent_landmark(half)` (called at the end of
  `_build_terrain`) places a lone **open arch** flanked by two standing stones at
  `Vector3(half.x * 0.4, 0.5, -half.y * 0.8)` (world), stored in `_descent_pos`. New
  `extraction_point() -> Vector2` returns `SimSpace.to_sim(_descent_pos)`; `main.gd`'s
  `_setup_extraction_gate()` already reads this optional method, so no `main.gd` change.
- **Kept far, not near** (the key call): the observatory in the home hub was the tempting
  "warm doorway" pick, but F3's gate is deliberately *far* from spawn (avoidance-first).
  R1c's contrast is generic-vs-authored, not far-vs-near — so the arch sits **578px from
  spawn** (HUB radius is 234px), off the observatory's back-centre axis, and derives from
  `half` so it stays in-bounds at any `PLAY_SCALE`. An **open** arch so the beacon's light
  shaft (built in `main.gd`) rises through the gap instead of clipping a solid dome.
- Verified via `exec`/`explore`: `can_extract` is false at spawn, true on the gate; the
  gate sim pos `(624, -297)` sits inside the north wall; the beacon shaft renders cleanly
  through the arch, framed by the flanking stones. This completes the P1 slice.

## Also completed — Threshold cel-mesh (2026-07-03, verified in-engine)

The Threshold's placeholder `Polygon2D` billboard is replaced by a procedural cel-shaded
3D mesh (warrior pattern) — the first creature on the all-3D art direction.
- `scripts/threshold_mesh.gd` (new) — `ThresholdMesh extends Node3D`, built from primitives
  via `IsoRig.solid_material()`: a low 6-facet stone carapace + ridge slab + head wedge +
  4 leg stubs. The **tell renders only on an unshaded channel** (eye slit + carapace-top
  crack) tinted per-frame from the sim's `Visual.color` — so the F2 hidden-grey gate, the
  white hit-flash, and WorldSync's pip logic all keep working with ZERO creature.gd changes.
  Per-state posing in `sync_from(body, delta)` (smoothed channels): Still presses flat,
  Assessing lifts + yaw-tracks `Visual.rotation` + breathing pulse, Committed snaps a
  forward stretch (fast 14/s rate), Withdrawn hunches; death shrink mirrors `body.scale`.
- `scripts/world_sync.gd` — new dispatch: `CREATURE_MESH_SCRIPTS` maps script class_name →
  mesh script; `_make_enemy_visual`/`_update_enemy_visual` route listed creatures to the
  mesh rig (`build(rig)` + per-frame `sync_from`), everything else keeps the billboard
  path. Dynamic `call()`s keep it decoupled (mesh script is same-session, so `load()`).
- Verified live: 26 group members → 23 billboards + 3 creature meshes, all Threshold 2D
  bodies suppressed; a 150-frame physics probe proved lift 0.05→0.54 during assess, tell
  grey `8898a8` → amber `d4994d` on reveal → lapses back, reveal-during-assess flips to
  withdrawn in 2 frames (tell `52617a`), commit stretch 0→0.98, reveal-lapse re-grays;
  kill → reap 26→25, mesh freed; screenshots confirm the stone-carapace read + amber tell
  \+ magenta pip; console clean; project compiles 40 scripts 0 errors.
- Gotcha (harness): the game runs in REAL TIME between bridge calls — a forced 1.6s state
  window expires during exec round-trips. Snapshot reads of transient states are useless;
  use the physics-frame probe (schedule events at exact frame counts inside the lambda).

## Also completed — R1a Pale Herd (2026-07-03, verified in-engine)

The 2nd GDD creature, built sim + cel-mesh in one pass (the first creature authored
mesh-first, no billboard stage). Backlog R1a is done; the Ring-1 P1 creature slice
(R1a + R1b + R1c) is now complete.

- `scripts/creature_pale_walker.gd` (new) — `CreaturePaleWalker extends Creature`.
  Calm→Uneasy→Scattered, **no aggressive state** (GDD: it fragments, never fights).
  The collective is an Array of the whole herd handed to every walker via `set_herd()`
  (self included): any member's detection calls `herd_alert()` on all — the **detection
  web** — and any strike / warrior-in-space calls `herd_scatter()` on all. Calm =
  boids-lite graze (cohesion >75px, separation <28px, wander at 26px/s); Uneasy = drift
  away from `_threat_pos` at 58 tightened into the herd; Scattered = 2.2s sprint at 175
  along a per-animal fan vector (±1.1 rad around directly-away), decaying to a 0.35
  floor. Return to Calm requires ≥2 mates within 95px after the 3.5s threat lapse —
  a lone animal seeks the herd centroid, and one with NO valid mates wanders Uneasy
  forever (the GDD's **Isolated**). `frequency = HARMONIC` (the hum), hp 2. Resonance
  reads it but does NOT change its decision (the baseline-calm teacher; intervention
  is the Threshold's lesson).
- `scripts/pale_walker_mesh.gd` (new) — `PaleWalkerMesh`, threshold_mesh.gd pattern.
  Tall narrow pale grazer (shoulder 1.08 — deliberately above the warrior's), long legs
  with speed-driven diagonal-pair swing, neck pivot swinging graze (2.2 rad, head to the
  ground) ↔ alert (0.15, head high + crouch) ↔ run-stretch (1.25 + gallop bounce), eyes
  wide/high. **Two signal channels by design:** the Resonance tell renders ONLY on the
  unshaded neck-membrane strip tinted from `Visual.color` (F2 gate/hit-flash/pip intact,
  zero creature.gd changes); the **hum is diegetic membrane GEOMETRY** — slow deep pulse
  Calm, irregular flutter Uneasy, hard contraction Scattered ("the silence is the first
  tell"), visible unread like the Threshold's posing.
- Wiring: `world_sync.gd` `CREATURE_MESH_SCRIPTS` + `&"CreaturePaleWalker"` entry;
  `main.gd` `_spawn_test_herd()` (called from `_spawn_test_creatures`) drops a 7-walker
  herd at SIM_ORIGIN + (-320,-240), seeded from `GameState.ring_seed(3000)`, off
  SPAWN_MIX and off the clear-count like the Thresholds.
- Verified live (physics-frame probe + snapshots): all 7 calm/graze 26px/s → one web
  ping flips ALL 7 uneasy (58px/s coherent flee, crouch 0.88, head up) → one strike
  scatters ALL 7 (161→61 decaying, divergent angles, hum 1.0→0.1) → threat lapse → 5
  regroup calm + 2 stragglers seeking → all 7 calm. Tell stayed hidden-grey through
  every state; reveal → `edc29e` warm calm tell + **cyan** pip (first HARMONIC pip in
  the game); severed+flung walker stuck Uneasy forever (Isolated rule); 2×DISSONANT
  `receive_hit` = CORRECT + white flash + herd scatter + death reap 29→28 with freed
  mate refs handled; console clean end-to-end; 42 scripts compile 0 errors.
- NOT built: the Isolated corrupted variant's read-interference aura (GDD: disrupts
  nearby Resonance reads) — the stuck-Uneasy state machine exists, the aura doesn't.

## Next — pick one

1. **Combat feel backlog item 2** (audio) — zero AudioStreams in the project; placeholder
   synth whoosh/crunch blips are the cheapest remaining "impact" win.
2. **Enemy placeholders → meshes** — enemy.gd/fleer/phaser still render as flat billboard
   tokens next to two mesh creatures; same dispatch seam makes this incremental.
3. **P1 gate check, then C-track** — the Ring-1 slice (R1a/R1b/R1c) is done: play it and
   judge whether read→avoid/intervene feels good BEFORE generalizing (C1 coherence,
   C2 echo chain, C3 structured generator). The backlog's gate says fix combat design
   here while it's cheap.

## Gotchas

- Godot editor is running → use GodotIQ bridge tools (`script_ops` / `node_ops` /
  `save_scene`) for `.gd` / `.tscn`, never raw file writes (stale-buffer / UID risk).
  `node_ops` needs the target scene ACTIVE in the editor — if another tab is open,
  `exec` (editor context) `EditorInterface.open_scene_from_path(...)` first; op dicts
  use the key `node` (not `path`).
- Project main scene is `base.tscn` (the villa). Run the Ring-1 run scene directly via
  `res://scenes/main.tscn`.
- `state_inspect` does NOT evaluate `get_tree()` / method-call expressions — use `exec`
  (context `"game"`, `Engine.get_main_loop()`).
- **`exec` `await` hangs AND freezes game physics** until `run(stop)`+`run(play)`; extreme
  `Engine.time_scale` also stalls physics. To verify sub-second gameplay windows: one exec
  arms state + a counting lambda writing `set_meta()` on the node, `godotiq_input`
  `{"wait_ms": N}` pumps game frames, a follow-up exec reads the metas. (Memory:
  `godotiq_live_test_gotchas.md`.)
- Validate cycle after each script: `check_errors` + `validate`. The project wants explicit
  type hints (`var x: float = 0.0`, not `:= 0.0`) — the validator flags inferred vars.

## Still pending (NOT done)

- Update `../idea/Summoned_GDD.html` §16 Art Direction (still describes the billboard plan).
- Sweep `CLAUDE.md` for remaining billboard-era references beyond the header that was fixed
  (e.g. the 2026-06 migration note, the asset-listing lines, the Sprite Cleanup section).
