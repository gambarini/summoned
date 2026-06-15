# Migration Plan — 2D Top-Down → Low-Res 3D Isometric

> Status: **Phases 0–2 done** (2026-06-15) — reusable `IsoRig`, Ring 1 3D geometry, and the
> hybrid warrior *walk* (billboard synced to the 2D body, camera-relative). Still 2D: the
> warrior's effects (Phase 2b), enemies/combat (Phase 3), and the `main`/HUD/base wiring
> (Phase 4). Pipeline reference: `RENDERING_3D.md`. Phase 3 (enemies & combat) is next.

## Start here (fresh session)

**Phases 0–2 are done.** Next up is **Phase 3 (enemies & combat)** — see its entry below.

1. Read `CLAUDE.md` (direction + conventions), then `docs/RENDERING_3D.md` (the proven
   pipeline), then skim the **Phases** section below for what's ✅ DONE and what each
   delivered file is. The current 3D stack: `scripts/iso_rig.gd` (`IsoRig`, the rig) →
   `scripts/ring1_world.gd` + `scenes/ring1.tscn` (`Ring1` playfield) →
   `scripts/warrior_sync.gd` (`WarriorSync`, the hybrid billboard).
2. See it running, windowed (headless can't render 3D — see the `headless-test-workflow`
   memory): the **Phase 2 walk** is
   `… res://scenes/warrior_iso_test.tscn -- --capture [yaw=NNN] [drive=up]`; the **Ring 1
   world** is `… res://scenes/ring1.tscn` (interactive, Q/E orbit). The original spike
   `scenes/ring1_iso_test.tscn` is still the read-only look reference.
3. **Architecture is decided: Option B (hybrid)** — see below. Don't reopen it. Rig
   ownership is also decided (scene owns + injects the rig).
4. **Two decisions open Phase 3** (in *Open questions*): mouse→world attack aim (the 2D
   cursor no longer maps to the world — raycast the screen ray onto the 3D ground to set
   `_attack_dir`), and whether to generalize `WarriorSync` into a sync-manager/registry now
   that enemies + attack arcs also need syncing.
5. **Gotcha:** after adding any `class_name`, run `… --headless --import` once before a
   direct scene run, or the global class cache is stale (`Could not find type "X"`).
6. Throwaway harnesses to delete when their phase is signed off: `scenes/ring1_verify.*`
   (Phase 1), `scenes/warrior_iso_test.*` (Phase 2). The run-loop logic (`game_state.gd`) is
   unchanged throughout.

## Guiding constraints

- **The run-loop close stays the priority** (run → fight → die → tribe cost → base →
  re-summon). That work is pure logic and transfers to any renderer. Don't let migration
  block it; ideally close the loop in the current setup first, then migrate rendering
  underneath it.
- **Keep `project.godot` untouched.** The pipeline is self-contained in SubViewports. If
  a project-level render change ever seems required, raise it explicitly.
- **Migrate one ring / one system at a time**, behind the spike as a reference. Ring 1
  first (its palette and geometry already exist in the spike).

## Architecture — DECIDED: Option B (hybrid)

**2D simulation drives 3D presentation.** Keep the existing 2D gameplay
(`CharacterBody2D`, `Area2D`, the current `enum State` machines, combat rules) running as
the source of truth; render it by driving 3D billboards/props from the 2D positions:
`Vector2(x, y)` → `Vector3(x, 0, y)`. This gets the look in front of the game fast without
destabilising working combat. Migrate individual systems to full 3D nodes (the rejected
Option A) only opportunistically and later, if/when a system needs true 3D physics.

Implications to hold throughout:
- One canonical coordinate space is the **2D sim** (`x, y`). The 3D layer is presentation
  only — never let gameplay read positions back from 3D nodes.
- A thin sync step each frame maps each 2D entity to its 3D billboard/prop.
- Z-ordering / "height" in the world maps to the 3D Y only for visuals (e.g. the warrior
  hovers); it does not affect 2D collision.

## Phases

### Phase 0 — Reusable rendering rig (foundation) — ✅ DONE (2026-06-15)
Promote the spike's pipeline into a reusable component the game scenes mount into:
- an `IsoRig` scene: rotation pivot + orthographic camera + the `_world_viewport` /
  `_post_viewport` / display-`TextureRect` chain + cel/palette materials, exposing
  `RENDER_SIZE`, palette, zoom, pitch as params.
- camera-relative input helper (already proven in `_update_warrior`).
- Keep `cel.gdshader` / `pixel_post.gdshader` as the shared shaders.
*Exit:* a blank scene can drop in `IsoRig` + content and get the look.

**Delivered:** `scenes/iso_rig.tscn` + `scripts/iso_rig.gd` (code-built pipeline,
verbatim port of the spike's measured values). Params exposed as `@export`:
`render_size`, `palette`, `cam_size`, `pivot_pitch`, `initial_yaw`, plus per-ring
`bg_color`/`fog_color`/`ambient_color`/`key_light_*` and `cel_bands`/`cel_light_gain`.
API: `add_world_child()` / `get_world_viewport()` / `get_post_viewport()`,
`orbit()`/`get_yaw()`, `solid_material()`, and pure-math Option-B helpers
`camera_relative_dir()` / `facing_index()` / `facing_name()` (return sim-space
`Vector2`; they move nothing). Verified windowed via the throwaway harness
`scenes/iso_rig_test.tscn` (capture: `docs/gen/iso_rig_test.png`) — pipeline
produces palette-snapped cel output and content survives camera orbit. The spike
is untouched. *Note for Phase 1:* a grey form can melt into same-value haze at some
yaws/depths (the documented "forms vs. same-value bg" issue — depth-silhouette
outline is the eventual fix). Delete `iso_rig_test.*` once Phase 1 stands up real terrain.

### Phase 1 — Ring 1 world geometry — ✅ DONE (2026-06-15)
Replace the 2D ground (`scripts/ground_layer.gd` tilemap / procedural FloorGrid) with the
3D cel-shaded terrain from the spike, as the real Ring 1 playfield. Reuse the measured Ring
1 palette. Props (ruins, bunting, flora) from the spike's builders.
*Exit:* Ring 1 renders as 3D under the rig, no 2D tilemap.

**Delivered:** `scripts/ring1_world.gd` (`Ring1World`, a `Node3D` faithful port of the
spike's terrain — construction order + `rng.seed = 7` preserved byte-for-byte; only change
is materials come from `rig.solid_material()`) and `scenes/ring1.tscn` + `scripts/ring1.gd`
(`Ring1`, the clean composable playfield: instances `IsoRig`, builds + mounts `Ring1World`,
Q/E camera orbit; no capture/quit). Verified **pixel-identical** to fresh spike baselines at
yaw 45 *and* 135 (0/57,600 px diff) via the throwaway harness `scenes/ring1_verify.tscn`
(captures: `docs/gen/ring1_phase1*.png`). The 2D `main.tscn` / `ground_layer.gd` are
untouched — they get swapped out in Phase 4. *Note:* `iso_rig_test.*` was removed (the rig
is now exercised through real terrain). `ring1_verify.*` is throwaway — delete after Phase 1
sign-off. Adding a `class_name` requires a `--headless --import` pass before any direct
scene run, or the global class cache is stale (see `headless_test_workflow` memory).

### Phase 2 — Player (hybrid) — ✅ DONE (movement; 2026-06-15)
Keep the warrior's 2D body, `enum State` machine, and ability logic exactly as-is. Add a
3D billboard (`Sprite3D`) bound to the 2D body via the per-frame sync (`Vector2(x,y)` →
`Vector3(x,0,y)`). Facing: pick the 8-dir frame from the warrior's 2D movement direction
**relative to camera yaw** (per `WARRIOR.md` / `_update_warrior` in the spike). Input must
become camera-relative so controls stay correct as the camera rotates. Effects
(glow/trail/Lament/Hollow) become 3D nodes/billboards driven by the same sync.
*Exit:* walk and fight Ring 1 in 3D, combat logic untouched.

**Delivered (the walk).** Honest exit met: **walk Ring 1 in 3D, camera-relative, combat
logic intact.** "Fight" (enemies + mouse→world attack aim) is genuinely Phase 3, and the
effects→3D conversion is split out as **Phase 2b** below.
- `scripts/warrior_sync.gd` (`WarriorSync`): drives a camera-facing `Sprite3D` billboard
  from the warrior's `CharacterBody2D` each frame. Position via the ring-specific sim→world
  transform (lives here, *not* on the reusable rig); facing via `rig.facing_name(velocity)`;
  camera-relative input injected into the warrior. Hides the 2D body with one
  `visible = false` on the root (physics/timers/combat/signals keep running) — which also
  defers the effects nodes for free.
- `scripts/warrior.gd`: **two touches.** (1) Restored a working-tree parse-blocker
  (`warrior.gd:316` stray `a`) back to HEAD — not a logic change. (2) Added an
  `input_provider: Callable` hook in `_read_dir` (unset → original WASD expression). The 2D
  default path is unchanged **by inspection** (the harness only exercised the injected
  branch). *Subclass/inherited-scene alternative exists if HEAD purity is wanted.*
- `scripts/ring1.gd`: rig ownership **inverted** — the scene (future `main`) owns the rig
  and injects it; Ring1 self-creates only as a standalone fallback.
- *Verified* windowed via throwaway `scenes/warrior_iso_test.tscn` with a programmatic
  discriminator: holding a fixed raw "up", the warrior shows the away/"north" sheet at yaw
  45 *and* 135, the billboard moves screen-top in both, and the **sim position rotates
  exactly 90°** between the two (proving input was rotated by yaw, not world-fixed). The
  sim→world transform output was checked numerically (yaw135's asymmetric `x≠z` rules out a
  transpose). Captures: `docs/gen/warrior_phase2_*.png`. Delete `warrior_iso_test.*` after
  sign-off.

*Semantic shift to bank:* `_read_dir` now feeds camera-relative sim space, so the warrior's
internal `_facing_dir` **and** the mouse-based `_attack_dir` are in that space too. Invisible
now (2D hidden), but Phase 2b (Hollow facing) and Phase 3 (attack aim) must account for it.

### Phase 2b — Player effects → 3D (deferred from Phase 2)
Convert the warrior's effect nodes (notation drift, the Hollow void/ember/pull, hover bob,
glow/trail) from 2D presentation into 3D nodes/billboards driven by the same `WarriorSync`.
Currently suppressed (not converted) by the body's `visible = false`.
*Exit:* the warrior's full visual identity reads in 3D, not just the base billboard.

### Phase 3 — Enemies & combat (hybrid)
Enemies (`enemy`, fleer, phaser) and `attack_arc` get the same treatment: 2D bodies and
`Area2D` hitboxes stay the source of truth; each gets a synced 3D billboard. Combat rules
(frequency / coherence / echo chains) are presentation-agnostic and stay in the 2D sim.
*Exit:* the full Ring 1 fight plays in 3D with no combat-logic changes.

### Phase 4 — HUD, base, flow
- **HUD** stays 2D: a `CanvasLayer` over the rendered viewport — unaffected by the 3D
  world. Verify it composites above the display TextureRect.
- **Base** (`base.tscn`): keep as the 2D tribe portrait initially (it's a diorama, not a
  playfield); convert to 3D later only if desired.
- **`main.tscn`** wires the rig + Ring 1 + warrior + HUD; `game_state.gd` is unchanged.
*Exit:* run → fight → die → base → re-summon, end-to-end, in 3D for Ring 1.

### Phase 5 — Remaining rings & polish
Rings 2–5 as 3D geometry with their measured palettes. Polish: camera pixel-snap to kill
rotation shimmer, depth-based silhouette outline if forms need separation, dedicated
isometric character sheets if billboards read wrong at the iso angle.

## Things that DON'T change
- `game_state.gd` / run-loop logic, tribe/relationship/echo persistence.
- Combat *rules* (coherence, frequency reading, echo chains).
- Sprite sheets and the node-based-effects philosophy.
- Nearest-neighbour everywhere; integer display scaling.

## Open questions
- Internal `RENDER_SIZE` for shipping (spike uses 320×180; balances chunk vs. detail).
- Do enemies/props need dedicated isometric sheets, or do current sheets billboard well
  enough?
- Does the base scene stay 2D long-term?
- Where should the per-frame 2D→3D sync live — a single manager iterating registered
  entities, or each entity owning its billboard? (Lean: a small sync manager.) **Phase 2
  started this as a per-entity `WarriorSync`; generalize into a registry/manager in Phase 3
  when there are multiple entities (enemies) to sync.**
- ~~Rig ownership~~ **RESOLVED (Phase 2):** the scene owns the rig and injects it into
  `Ring1` (+ the sync); `Ring1` self-creates only as a standalone fallback.
- **sim↔world coordinate mapping — partially resolved (Phase 2).** Transform shape settled:
  `world = Vector3((sim.x-240)/PPU, hover_y, (sim.y-135)/PPU)` (origin = sim centre (240,135),
  2D y-down → 3D +z, verified numerically). **`PPU = 18` is provisional** (eyeballed between
  the plateau-width anchor 480/26 ≈ 18.5 and the spike-feel anchor 100/6 ≈ 16.7; the static
  captures have no distance reference, only "on the plateau" is confirmed). **Still open:**
  the aspect clash (play area ≈1.78 vs plateau ≈1.18) and real roam bounds — deferred to
  Phase 4 when `main` supplies the walls; *decide then*: reshape plateau toward 1.78, or
  constrain the sim play area to the plateau footprint.
