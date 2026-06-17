# Migration Plan — 2D Top-Down → Low-Res 3D Isometric

> Status: **Phases 0–4 + all of Phase 2b done** (2026-06-17) — the Ring 1 run loop plays in
> low-res 3D end-to-end (`main.tscn` = rig + terrain + synced warrior/enemy/arc billboards, 2D
> HUD on top, `game_state.gd` unchanged), and the warrior's **full visual identity** now reads in
> 3D: ability shockwaves (resonance/burst → flat 3D ground rings), hover bob, notation drift, the
> **Hollow** chest wound (void/ember/pull, facing-gated), and the **hem/shimmer** overlay shader.
> Still 2D by choice: the `base` diorama. **Manual playthrough sign-off done (2026-06-17):** the
> full run→fight→die→`base`→re-summon loop was played end-to-end windowed in 3D (WASD move, mouse
> attack, R resonance → 3D ground ring, Q/E + arrows orbit, F extract, real `change_scene_to_file`
> transitions main→base→main with a clean rig rebuild) — all deferred "manual sign-off" notes are
> closed, and every per-phase throwaway harness is **deleted**. One control fix from the
> playthrough: `extract` was rebound **Q → F** (`project.godot` `[input]` only) so Q/E are free for
> camera orbit. Pipeline reference: `RENDERING_3D.md`. **Next: Phase 5** (rings 2–5, camera
> pixel-snap, bounds/aspect tuning, optional warm-effect palette retune).

## Start here (fresh session)

**Phases 0–4 and all of Phase 2b are done — the Ring 1 loop plays in 3D and the warrior's full
visual identity reads** (bob, notation, ability shockwaves, the Hollow chest wound, the hem/shimmer
overlay). Remaining: **Phase 5** (rings 2–5, camera pixel-snap, bounds/aspect tuning, and the
optional warm-effect palette retune — the cool palette currently cool-shifts the Hollow ember to
pink, accepted as-is). See entries below.

1. Read `CLAUDE.md` (direction + conventions), then `docs/RENDERING_3D.md` (the proven
   pipeline), then skim the **Phases** section below for what's ✅ DONE and what each
   delivered file is. The current 3D stack: `scripts/iso_rig.gd` (`IsoRig`, the rig) →
   `scripts/ring1_world.gd` + `scenes/ring1.tscn` (`Ring1` playfield) →
   `scripts/sim_space.gd` (`SimSpace`, the shared sim↔world transform) →
   `scripts/warrior_sync.gd` (`WarriorSync`, the player billboard + mouse aim) →
   `scripts/world_sync.gd` (`WorldSync`, the enemy/arc billboard manager).
2. See it running, windowed (headless can't render 3D — see the `headless-test-workflow`
   memory): the **real Ring 1 run** is just `… res://scenes/main.tscn` (WASD move, mouse aim,
   click attack, Q/E + arrow orbit, R resonance, F extract) — this is the live game now, and the
   full run→fight→die→base→re-summon loop is playthrough-verified. The per-phase throwaway
   capture harnesses have been deleted (their PNGs remain in `docs/gen/`). The original spike
   `scenes/ring1_iso_test.tscn` is still the read-only look reference.
3. **Architecture is decided: Option B (hybrid)** — see below. Don't reopen it. Rig
   ownership is also decided (scene owns + injects the rig).
4. **Phase 3's two open decisions are now RESOLVED** (see *Open questions* + the Phase 3
   *Delivered* block): mouse→world aim reuses the proven `camera_relative_dir()` on a
   screen-space delta (no hand-rolled raycast); `WarriorSync` stays a per-entity sync for the
   player, and a separate **`WorldSync`** manager group-scans the dynamic many (enemies/arcs).
   The palette-legibility finding is **resolved**: `IsoRig`'s palette now carries the two
   frequency-signal hues (dissonant pink `c4547a` / harmonic lavender `c0a0f0`), so the combat
   read survives the snap and the warrior is no longer confusable with a dissonant enemy.
5. **Gotcha:** after adding any `class_name`, run `… --headless --import` once before a
   direct scene run, or the global class cache is stale (`Could not find type "X"`).
6. Throwaway harnesses — **all deleted (2026-06-17)** after the manual playthrough sign-off:
   `scenes/ring1_verify.*` (Phase 1), `scenes/warrior_iso_test.*` (Phase 2),
   `scenes/ring1_phase3_test.*` (Phase 3), `scenes/main_verify.*` (Phase 4). Their capture PNGs
   in `docs/gen/` are kept as verification evidence. The run-loop logic (`game_state.gd`) is
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

### Phase 2b — Player effects → 3D (deferred from Phase 2) — ✅ DONE (2026-06-17)
Convert the warrior's effect nodes (notation drift, the Hollow void/ember/pull, hover bob,
glow/trail) from 2D presentation into 3D nodes/billboards driven by the same `WarriorSync`.
Currently suppressed (not converted) by the body's `visible = false`.
*Exit:* the warrior's full visual identity reads in 3D, not just the base billboard.

**Delivered (part 1): the three effects that were visible or most felt — ability shockwaves,
hover bob, notation drift.** All driven by `WarriorSync`; warrior touches stay the established
provider/flag pattern (no logic change).
- **Ability shockwaves (resonance/burst) — the visible seam from Phase 4, now gone.** These
  rings have *no* gameplay role (the reveal/damage loop runs above them), so they're handled by
  **signal, not group-scan mirror**: `warrior.gd` emits `ground_pulse(center, radius, color)`
  gated by a `suppress_world_vfx` flag (set by `WarriorSync.setup`; unset → original 2D
  `Polygon2D`, behaviour unchanged). `WarriorSync._on_ground_pulse` spawns a self-animating flat
  3D ground ring (annulus) that runs its own scale+alpha tween and frees itself — **no 2D node
  is ever created, so there's no over-the-view flash and no one-frame race** (the trap in the
  hide approach). *Snap note:* a translucent filled disc re-blends to grey under the palette
  snap, so it's a **bright ring held opaque while it expands, fading only late** — reads as a
  clean ground shockwave (`docs/gen/ring1_phase3_pulse_yaw45.png`).
- **Hover bob:** independent sin on the billboard's Y in `WarriorSync` (`BOB_SPEED 0.8`,
  `BOB_AMPLITUDE 0.1` world), gated to IDLE/MOVE via a new `warrior.vfx_hover_active()` accessor
  (matches the 2D rule — still during attacks/hurt/death). The offset is a member (`_bob_y`) so
  a future Hollow node rides the *same* bob (the 2D code welds the wound to the chest). Verified:
  billboard Y traces a clean sinusoid peaking at exactly `HOVER_Y+amp` (2.100).
- **Notation drift:** the 2D `GPUParticles2D` ported to `GPUParticles3D` — same
  `ParticleProcessMaterial` shape with px values rescaled to world (÷PPU), glyphs as billboarded
  particle quads off the 4-frame sheet (`particles_anim_h_frames`), `local_coords=false` so the
  emitter trails. Reads as pale drifting score-debris around the warrior (snaps to the light
  palette). *Move-intensity density scaling not ported (constant idle ratio) — minor.*
- *Verified* via the Phase 3 harness (`-- --capture pulse|bob|trail`) and the real-game
  composite (`docs/gen/phase4_main_composite_yaw45.png` shows notation around the warrior, no 2D
  artifacts). The `trail` capture drives the warrior 107px and confirms the debris strings out
  *behind* the path (`docs/gen/ring1_phase3_trail_yaw45.png`) — validating `local_coords=false`,
  the one thing an idle frame can't show. The hidden 2D `NotationDrift`/Hollow nodes still exist
  on the body (Option B source) and run suppressed — harmless; the 2D notation sim is wasted
  work but left to keep the 2D path intact (gate its `emitting` off if part 2 touches the body).
- *Manual playthrough sign-off — DONE (2026-06-17):* live key/WASD input in `main` confirmed
  (movement → debris trail, R resonance → 3D ground ring, mouse-aim attack, Q/E + arrow orbit)
  across the full run→fight→die→base→re-summon loop. The earlier "integration risk is low" call
  held.

**Delivered (part 2): the Hollow (2026-06-17).** Faithful 3D port of `warrior.gd`'s chest wound,
all in `WarriorSync`, **zero `warrior.gd` changes** — `hollow_stress` is already a public
`@export`, read live each frame.
- **Three nodes under a `Hollow` Node3D** (rides `HOLLOW_Y` chest height + the reserved `_bob_y`):
  a dark **void** disc (`#0D0A1E` radial `GradientTexture2D`, normal blend — carves the recess), a
  smaller additive **ember** core sunk inside it (the dark gap sells the depth, breathing pulse on
  alpha), and an inward **pull** (`GPUParticles3D`). All are camera-facing billboard quads with
  `no_depth_test` + `render_priority` (hem 1 < void 2 < ember 3) so the wound draws over the body
  sprite at the same chest depth without z-fighting. Param arrays (`HOLLOW_RADIUS`/`BRIGHTNESS`/`INWARD`,
  the gradients) re-authored verbatim from `warrior.gd`'s `_HOLLOW_*`.
- **The pull uses a sphere *shell* (`EMISSION_SHAPE_SPHERE_SURFACE`), not the 2D planar ring** —
  radial accel pulls motes inward from any camera yaw (a fixed-plane ring would only read head-on).
- **Facing gate keys off the *displayed* billboard facing (`WarriorSync._facing`), NOT
  `warrior._facing_dir`.** In 2D top-down those were the same node; in 3D they diverge (sheet =
  velocity-vs-camera; `_facing_dir` follows the attack aim). The wound is painted on the sprite, so
  it must track the shown sheet — `HOLLOW_DIR_VIS` re-keyed to WarriorSync's "south"/"north-east"
  vocabulary. This also makes the wound correctly hide when the warrior walks away from camera.
- *Note — the wound shows at `hollow_stress=0` (small, bright ember, no pull motes), faithful to
  the 2D game; the earlier "invisible in normal play" wording was imprecise. `hollow_stress`
  scales it open (ember dims, void widens, pull strengthens); the void dominates at stress 3.*
- *Verified* windowed via the throwaway `scenes/warrior_hollow_test.tscn` (`-- --capture`, now
  **deleted** after sign-off): the **discriminating back-facing test passed** — front (south) shows
  the wound, side (east) faint, **back (north) hides it** (`PASS=true`). Captures kept in
  `docs/gen/hollow_phase2b_{front,front_s1,side,back}.png`. *(Harness gotcha banked: clear the
  `enemies` group first — a combat death `change_scene_to_file`s and frees the harness, the current
  scene, tripping the watchdog.)*

**Delivered (part 2): the hem/shimmer shader (2026-06-17).** `warrior_hover.gdshader` re-authored
as the spatial `assets/shaders/warrior_hover_3d.gdshader` (the 2D canvas_item version stays for the
2D path). It's an **additive overlay billboard quad** layered over the base sprite (the base
`Sprite3D` is untouched), sampling the same 8-dir sheet so UVs line up 1:1 — amber cloak hem +
lavender top shimmer, `move_intensity` eased from the body's velocity in `WarriorSync`. Billboard +
keep-scale done in `vertex()`; `render_priority 1` (over the sprite, under the Hollow). Verified the
overlay renders at the cloak bottom, correct orientation (a magenta debug band confirmed it).

*Art finding — ACCEPTED as-is (2026-06-17):* the cool 16-colour palette has no warm slot, so the
warrior's warm effects cool-shift under the snap — the **ember reads pink** (snaps to the dissonant
frequency hue) and the **amber hem snaps near-cloak grey** (subtle). Decided to keep the faithful
warm colours: the cool palette cooling the wound is on-direction. Retuning the ember to
palette-present hues (pale + lavender) or boosting the hem remains an option if it ever needs to pop
(Phase 5 polish). **Phase 2b is now complete.**

### Phase 3 — Enemies & combat (hybrid) — ✅ DONE (2026-06-16)
Enemies (`enemy`, fleer, phaser) and `attack_arc` get the same treatment: 2D bodies and
`Area2D` hitboxes stay the source of truth; each gets a synced 3D billboard. Combat rules
(frequency / coherence / echo chains) are presentation-agnostic and stay in the 2D sim.
*Exit:* the full Ring 1 fight plays in 3D with no combat-logic changes.

**Delivered.** Exit met: enemies + attack arc render as synced 3D billboards, mouse aim is
camera-relative, **all collision stays 2D and combat logic is untouched.**
- `scripts/sim_space.gd` (`SimSpace`): the sim↔world transform extracted to one shared spot
  (was inlined in `WarriorSync`), now with the inverse `to_sim()` the mouse aim needs. Pure
  static maths; `WarriorSync`, `WorldSync`, and the aim all call it.
- `scripts/world_sync.gd` (`WorldSync`): the sync **manager** for the spawn/despawn crowd. It
  **group-scans** `enemies` (lazily makes a billboard per new member, frees billboards where
  `is_instance_valid()` is false) so spawn/death need no wiring — Phase 4's `main` just adds
  enemies as before. Enemies have no sprite sheets, so the billboard is a camera-facing flat
  mesh built from the *same* `Polygon2D` (octagon/diamond/triangle silhouette), tinted from
  `_visual.color` **every frame** (the colour is the gameplay signal — reveal/amplify/flash).
  Death-shrink (`body.scale`) + amplify-punch (`visual.scale`) ride along free (both tweens
  run on the hidden 2D nodes). The attack arc self-groups (`attack_arcs`) and gets a flat
  ground-plane slash mesh oriented to `_attack_dir`, alpha mirrored from its fade.
- `scripts/warrior_sync.gd`: added `aim_dir_from_screen()` — undo the display's
  `KEEP_ASPECT_CENTERED` letterbox (window px → render px), find the warrior in that viewport
  space via `camera.unproject_position()`, feed the on-screen delta to the **proven**
  `rig.camera_relative_dir()`. Ortho ⇒ screen direction maps faithfully to ground direction,
  so no hand-rolled ground raycast. (Sim→world transform moved to `SimSpace`.)
- `scripts/warrior.gd`: **one touch**, mirroring the Phase 2 `input_provider` pattern — an
  `attack_dir_provider: Callable` hook in `ATTACK_STARTUP`; unset → the original
  `get_global_mouse_position()` aim (2D path unchanged by inspection).
- `scripts/attack_arc.gd`: **one touch** — `add_to_group("attack_arcs")` in `_ready` (harmless
  in pure-2D runs). Collision stays the 2D `HitArea`.
- *Verified* windowed via throwaway `scenes/ring1_phase3_test.tscn`. Enemies sync + survive
  orbit at yaw 45/135 (`docs/gen/ring1_phase3_enemies_yaw*.png`); the arc renders as a
  directional ground slash (`…_arc_yaw45.png`). **Aim discriminator** (the risky piece): a
  *fixed* top-centre cursor yields `_attack_dir` (sim space) = `(-0.707,-0.707)` at yaw 45 and
  `(-0.707,+0.707)` at yaw 135 — a 90° rotation matching the 90° orbit, proving aim is
  camera-relative (a world-fixed aim would be identical at both). A `combo` capture closes the
  asymmetric gaps the straight-away tests miss: an **off-axis** cursor gives `aim.x>0` toward
  the up-right enemy (dot 0.61; slash visually points up-right), and killing an enemy drops the
  tracked billboard count 5→4 (the **death→reap** path). Letterbox offset is structurally 0
  here (project `stretch=canvas_items` pins the content viewport to 480×270 and absorbs the
  OS-window letterbox before the mouse reaches us; 480×270→render 320×180 is aspect-matched) —
  the offset code is correct/future-proof but never bites, so the only real-cursor unknown is
  left to manual playtest. Delete `ring1_phase3_test.*` after sign-off.
- **Legibility fix (done):** the palette post-pass originally only knew the Ring 1 greys + one
  warm tone, so frequency billboards snapped to it (dissonant pink→warm orange, harmonic
  purple→grey) — dissonant enemies, the arc, and the warrior all collapsed onto the same
  orange. Fixed by adding the two gameplay-signal hues to `IsoRig`'s palette (`c4547a` pink,
  `c0a0f0` lavender — the canonical `enemy.gd` COLORS; 16 entries now = the shader's
  `palette[16]` ceiling). Verified: dissonant reads pink, harmonic reads lavender, the arc
  reads pink, the warrior stays neutral, and terrain is untouched (the hues sit far from every
  grey, so nothing else snaps to them). Signal hues are gameplay-universal — other rings keep
  them when swapping the terrain ramp.
- **Still deferred (juice, like Phase 2b):** the fleer's explosion ring is a separate transient
  2D node and is not yet rendered in 3D. Amplified (orange) still folds to the warm tone — fine
  (transient "wrong-hit" feedback); add a third signal hue only if it needs to pop more.

### Phase 4 — HUD, base, flow — ✅ DONE (2026-06-16)
- **HUD** stays 2D: a `CanvasLayer` over the rendered viewport — unaffected by the 3D
  world. Verify it composites above the display TextureRect.
- **Base** (`base.tscn`): keep as the 2D tribe portrait initially (it's a diorama, not a
  playfield); convert to 3D later only if desired.
- **`main.tscn`** wires the rig + Ring 1 + warrior + HUD; `game_state.gd` is unchanged.
*Exit:* run → fight → die → base → re-summon, end-to-end, in 3D for Ring 1.

**Delivered.** `main.tscn` / `main.gd` are now the 3D run scene; `game_state.gd` and the
run-loop signal handlers are **byte-identical** to the 2D build.
- `scripts/main.gd`: `_ready` now owns + injects the shared `IsoRig`, mounts `Ring1`, and
  builds `WarriorSync` + `WorldSync` (the Phase-2/3 bindings) — then the *unchanged* HUD bind,
  death/extract signal wiring, last-song check, and `_spawn_enemies()`. `_process` adds Q/E
  camera orbit. The death→base→re-summon handlers are untouched (`change_scene_to_file`).
- `scenes/main.tscn`: dropped the 2D `TileMapLayer` ground + all prop `Sprite2D`s (the 3D
  `Ring1World` replaces them). **Kept** the warrior, the HUD `CanvasLayer`, and the boundary
  `Walls` (the 2D roam bounds — still the 480×270 box; warrior stays ~on the plateau, the
  aspect/bounds tuning from the sim↔world open question is left for a polish pass).
- `scripts/warrior_sync.gd`: `setup()` now also wires the live attack aim
  (`attack_dir_provider` → `aim_dir_from_screen(live cursor)`).
- `scripts/world_sync.gd`: enemy bodies + arcs are now hidden (`visible = false`) on
  registration — the harness only sampled the SubViewport, but in the real window the 2D
  camera is off, so an unhidden 2D `Polygon2D` would draw at raw sim coords *over* the 3D
  display. Physics/`Area2D`/combat are unaffected.
- *Verified* windowed via throwaway `scenes/main_verify.tscn`, which instances the real
  `main.tscn` and captures the **root window** (not the SubViewport): Ring 1 renders in 3D, the
  HUD (coherence bar / chain / resonance dot) composites above the display, warrior + 5 enemies
  read as synced frequency-coloured billboards, and **no stray 2D polygons** leak through
  (`docs/gen/phase4_main_composite_yaw45.png`). The **re-summon rebuild path** is verified too
  (the real new risk: `main._ready` building a *fresh* `IsoRig` + two SubViewports + materials
  on a second entry): the `reentry` mode instances `main`, frees it, re-instances, and the
  second build renders identically clean (`docs/gen/phase4_reentry.png`) — and that run also
  drove the **live** attack path (`WarriorSync._aim_live` via `get_mouse_position`, which the
  synthetic-cursor tests bypassed), spawning an arc on the rebuilt rig. `main.tscn` also loads
  clean as the actual root scene. The death/transition *logic* is byte-identical to the proven
  2D build; a full combat-driven playthrough is the natural manual sign-off. Delete
  `main_verify.*` after that. (First-ever run compiles the cel/post shaders — a cold launch can
  be several seconds; give capture watchdogs headroom.)
- *Now orphaned by the 3D `main`* (not auto-deleted): `scripts/ground_layer.gd` and the 2D
  Ring 1 tile/prop assets — still referenced by `scenes/tile_test.tscn`, so left in place.
- *Deferred (Phase 2b), with one visible seam:* the warrior's death/hurt/summon animations are
  suppressed with the hidden body (on death the billboard just holds its last pose before the
  scene swaps — fine). But the **resonance/burst ability rings** are transient 2D `Polygon2D`s
  the warrior spawns into `Main` at runtime, so they currently flash as flat 2D artifacts over
  the 3D view when those abilities fire (the reveal/damage *logic* is unaffected — only the VFX
  reads wrong). Converting these ability/effect visuals to 3D is Phase 2b.

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
  enough? **Phase 3 took the cheap path:** enemies have *no* sheets — they billboard as flat
  `Polygon2D`-silhouette meshes (tinted tokens), and legibility was fixed by adding the
  frequency hues to the palette (above), not by authoring sheets. Dedicated enemy sheets remain
  optional polish (Phase 5) if the silhouettes read wrong at the iso angle.
- Does the base scene stay 2D long-term?
- ~~Where should the per-frame 2D→3D sync live~~ **RESOLVED (Phase 3):** *both*, by lifetime.
  The persistent player keeps a per-entity `WarriorSync` (it has unique input/aim duties); the
  spawn/despawn crowd (enemies, transient arcs) is handled by a single **`WorldSync` manager
  that group-scans** rather than taking explicit registrations — so death/spawn need no wiring.
- ~~Mouse→world attack aim~~ **RESOLVED (Phase 3):** no ground raycast — for the ortho camera,
  unproject the warrior to viewport space, inverse-letterbox the cursor into the same space,
  and feed the on-screen delta to the proven `camera_relative_dir()`. In `WarriorSync.
  aim_dir_from_screen()`, injected into `warrior.gd` via the `attack_dir_provider` hook.
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
