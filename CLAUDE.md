<!-- GODOTIQ RULES START -->
<!-- godotiq-rules-version: 0.5.13 -->
# GodotIQ — Core Rules

You have GodotIQ MCP tools (`godotiq_*`). ALWAYS prefer them over raw file operations on Godot files.

- **DO NOT** read `.tscn`/`.gd`/`.tres` directly with `Read`/`cat` — `file_context`, `scene_map` and `script_ops` return structured data with cross-references, transforms and signal wiring that raw text cannot provide.
- **DO NOT** grep for signal connections or function callers — `dependency_graph` / `signal_map` trace the complete graph in one call.
- **DO NOT** hand-calculate positions or guess scales — `placement` / `suggest_scale` return validated suggestions.
- **DO NOT** build the world in code: terrain, structures and decorations belong in `.tscn` via `build_scene`/`node_ops`; only game logic belongs in scripts.
- **DO NOT** write `.tscn`/`.gd` behind a running editor with native file tools — GodotIQ's write tools detect the editor and route safely; raw writes risk stale-buffer overwrites and UID corruption.

## Mandatory Workflows

1. **Session start:** `project_summary(detail="brief")` FIRST — architecture, autoloads, counts in ~500 chars.
2. **Before editing any file:** `file_context(file, detail="brief")`; for signature/signal changes also `impact_check(file, action, target)`. NEVER modify a `.gd` without `file_context` first.
3. **3D scene work:** `scene_map(focus, radius, detail="brief")` → `placement` for positions → `build_scene` (batches: grid/line/scatter) or `node_ops(validate=true)` → `save_scene()` → self-verify with `explore`/`spatial_audit`.
4. **Visual QA after scene work:** `explore(mode="tour")` — describe each screenshot, fix issues, tour again; `explore(mode="inspect", positions=[...])` for close-ups.
5. **After every code change:** `validate(target=file, detail="brief")` for Pro convention checks, then `check_errors(scope=file)` for compilation/parser errors. One script, one validate/check cycle — never batch five scripts then debug.
6. **Multi-file refactor:** `impact_check` BEFORE changing; `validate(target="project")` baseline before/after; then `check_errors(scope="project")` and `signal_map(find="orphans")`.
7. **Testing/debugging:** `run(action="play")` → `verify_project_runs()` → `read_debug_console()` for errors → `state_inspect` for values (cheap, preferred) → `verify_motion` for movement → `screenshot(scale=0.25, quality=0.3)` only when visuals changed (expensive) → `run(action="stop")`.

## Token Efficiency

- Default to `detail="brief"`; full payloads can emit 50k–140k chars and crash the session.
- Always filter: `focus`+`radius` (scene_map), `path_filter` (asset_registry), `scope="file:..."` (signal_map).
- Prefer `state_inspect` (~200 chars) over `screenshot` (10k+) when you need data, not pixels; max 1 screenshot per verification point.
- Batch: one `build_scene` or one `exec` loop beats 20 single `node_ops`; group edits → one `save_scene` → one verification cycle.
- Act on tool responses immediately; every bridge response carries `_editor_state` (open_scene, game_running, recent_errors) — react to it.

## Error Recovery

| Error | Action |
|---|---|
| `GAME_NOT_RUNNING` | `run(action="play")` |
| `RUNTIME_NOT_ATTACHED` | game playing but runtime tools unavailable: `run(action="stop")` then `play` to retry the handshake; if persistent, check the addon is enabled |
| `NO_GAME_SESSION` | restart the game with `run` |
| `NODE_NOT_FOUND` | `scene_tree(detail="brief")` to find the correct name |
| `ADDON_NOT_CONNECTED` | enable the GodotIQ addon in the Godot editor |
| `BLOCKED_EDITOR_OPEN` | the editor is open: use bridge ops (`node_ops`/`script_ops`/`save_scene`) instead of direct disk writes |
| `TIMEOUT` | wait, check `state_inspect`; truly dead → `run(action="stop")`, retry |
| `SCRIPT_ERRORS` | `check_errors(scope="scene")`, fix the scripts, rerun |
| `BLOCKED` (node_ops) | read the `validation` array, adjust position/scale |
| `NO_SCENE` / `PARENT_NOT_FOUND` / `NO_NODES` (build_scene) | open a scene / fix or create the parent / pass exactly one mode with valid data |
| Partial success (build_scene) | check `errors`, retry only the failed items |

## Conventions

- GDScript: `snake_case.gd` files, `PascalCase` classes, type hints everywhere (`var hp: int = 0`, `-> void`), `@onready` for node refs, `is_instance_valid()` for null checks.
- `node_ops` paths are relative to the scene root: `"Entities/Worker_1"`, not `"Main/Entities/Worker_1"`.
- Scripts created this session: reference with `load()`, not `preload()`.

**Full reference:** `GODOTIQ_RULES.md` in the project root — read the relevant section before non-trivial work (3D building patterns, Godot quirks, verification recipes, spatial validation, per-tool reference).
<!-- GODOTIQ RULES END -->

# Summoned — Claude Code Instructions

Godot 4 project. **Low-resolution 3D isometric pixel art** — cel-shaded 3D world seen through an orthographic, freely-rotatable camera, rendered at a low internal resolution and palette-snapped so it reads as hand-drawn pixel art. Characters and creatures are **procedural low-poly cel-shaded 3D meshes** — the warrior pattern: a `*_mesh.gd` (`Node3D` rig built in code) driven by a `*_sync.gd` from the still-authoritative 2D sim (Option B hybrid). See `warrior_mesh.gd` + `warrior_sync.gd`. The low-res render + palette snap keep the look pixel-art-ish; the characters are meshes, **not** billboard sprites. Nearest-neighbour filtering throughout — no bilinear anywhere.

> **Direction change (2026-06):** the project pivoted from 2D top-down to low-res 3D isometric. **Migration Phases 0–4 and all of Phase 2b are done (2026-06-17): the Ring 1 run loop (`main.tscn`) plays in 3D end-to-end** — `IsoRig` rig + `Ring1World` terrain + warrior/enemy/arc billboards synced from the still-authoritative 2D sim (Option B hybrid), 2D HUD on top; the warrior's **full visual identity** reads in 3D (hover bob, notation drift, resonance/burst shockwave rings, the Hollow chest wound, the hem/shimmer overlay shader). The full run→fight→die→base→re-summon loop is playthrough-verified. Remaining: **Phase 5** (rings 2–5, camera pixel-snap, bounds/aspect tuning; optional warm-effect palette retune — the cool palette cool-shifts the Hollow ember to pink, accepted as-is). **Update (2026-06-21):** rings 1–5 are now **explore-scale** (huge open arenas) — the play-area size is one knob, `SimSpace.PLAY_SCALE` (=4), and the old fixed `480×270` box / `28×22` plateau / `±13.0,±6.94` footprint numbers are the `PLAY_SCALE=1` case (superseded; walls + enemy pocket-spawns + every ring's terrain derive from `SimSpace.half_world()`). `base.tscn` is now a **3D villa** (`villa_world.gd`, Anthe + ceremony dais under the IsoRig), no longer a 2D diorama. The original spike `scenes/ring1_iso_test.tscn` is the read-only look reference. See `docs/RENDERING_3D.md` (the pipeline) and `docs/MIGRATION_3D.md` (the plan + current status).

> **Art direction → 3D meshes (2026-06-30):** the game has fully moved to 3D — the original 2D-pixel-art / camera-facing-billboard plan is **deprecated**. Every character/creature now follows the warrior's procedural-mesh pattern (above). **Done (2026-07-03): no character billboards remain** — warrior, both ring creatures (Threshold, Pale Herd) and all three enemies (`enemy_mesh.gd` + fleer/phaser subclasses, routed via `world_sync.gd`'s `CREATURE_MESH_SCRIPTS`) are procedural cel-meshes; only the transient attack-arc ground decal still uses `WorldSync`'s polygon fallback path. New ring creatures must be authored as meshes, not sprites. The 2D *sim* stays the gameplay-truth layer — only *presentation* is 3D. (The 2026-06 migration note above predates this where it says "warrior/enemy/arc billboards".)

Design intent: `../idea/Summoned_GDD.html` (§16 Art Direction still describes the old 2D-pixel/billboard plan — **pending update** to the 3D-mesh direction).  
Character references: `docs/[CHARACTER].md` — see Character Docs below.

---

## Current Priority

> **📋 The roadmap lives in Notion, not in this file.**
> **[SUMMONED — Roadmap HQ](https://app.notion.com/p/3a92711a768d81a986c0d95d4a6f6cdb)** is the single source of truth for *what to build next*: a `Roadmap` database of 42 items with Phase / Priority / Status / Size / dependencies, plus a `Session Log`. Each item is scoped to **one session = one commit** and carries its own Spec / Hook points / Done when.
>
> **At session start:** read the Roadmap HQ page (it holds the working conventions, the verification recipe and the commit protocol), take the lowest-numbered `todo` item whose dependencies are `done`, and set it to `wip` before writing code. Close out by setting `done`, filling `Commit hash`, and adding a Session Log entry.
>
> `docs/RING_BACKLOG.md` remains useful **design** reference (the GDD-vs-built analysis) but its status marks are superseded by Notion. `docs/HANDOFF.md` stays as engineering notes / session history.
> The sections below are kept as **context**, not as the work queue.

Make runs **matter and vary** — the loop and per-run map randomization are done; the gap is now purpose and generator quality.

**Done:**
- **Run loop is closed** (`main.gd`): death → `grief_reserve − 1` → `base.tscn`; extract → `current_ring + 1` → `base.tscn`; `clock_ticks` advances each run-end. Verified end-to-end.
- **Maps are per-run randomized** (2026-06-30): every ring world + enemy layout derives RNG from `GameState.ring_seed(local)`, offset by a per-summon `GameState.run_seed` rolled in `main.gd._ready()`. `run_seed == 0` (and `GameState.lock_seed = true`) reproduces the original pinned layouts byte-for-byte for the look reference / tests. Previously every run was seed-pinned identical.
- **Progression is spatial** (F3 + R1c): one extraction gate per run, placed by `main.gd._setup_extraction_gate()` (ring override via `extraction_point()`; Ring 1's is an authored far arch). `[F]` only fires inside `GATE_ACTIVATION_RADIUS`. Reach-only — it gives progression a *place*, not a payoff.
- **Meta-economy is a real economy + it persists** (2026-07-26): `game_state.gd` now owns the whole cost model (`begin_summon` / `end_run_death` / `end_run_extract` / `wait`), and saves to `user://summoned_save.cfg` at those call sites — previously nothing was written to disk at all, so grief/clock/ring reset on every quit. Rebuilt against the GDD rather than the old placeholder reading (see below).

**Next (the real roguelike work):**
1. **Give combat a payoff** — `_on_run_cleared()` (`main.gd`) still only shows a banner, and creatures (Threshold / Pale Herd) are off the `_enemies_alive` count so it can fire while a dozen are alive. The gate gives progression a place to reach; nothing yet rewards fighting. Cheapest real fix: pay cleared pockets / correct Resonance reads into the grief reserve, which is now a live currency.
2. **Structure over scatter** — the generator only scatters props + enemy pockets in an open box (no chokepoints, cover, landmarks, objectives), so different seeds look different but play the same. Make the space create decisions.
3. **Tribe roster → the GDD's real triggers** — the economy below is complete as a *cost model*, but two GDD rules still can't be expressed without a tribe roster (members, ages, Anthe's capacity as its own axis):
   - LAST SONG's real trigger is the tribe falling below its floor (Anthe lost, no surviving adult), not the clock cap. `GameState.is_last_song()` is the seam.
   - Ring access should key off **tribe phase**, not extraction count — GDD: "The warrior does not earn access. The tribe does." `advance_ring()` is the seam.

> **Correction (2026-07-26) — the old priority #3 was wrong on both halves.** It read: *"`grief_reserve` only ever drains (−1 per death, never replenished) … define a grief source and a clock-10 resolution (win/lose)."* In fact (a) a grief source already existed — `base.gd._do_wait()`, `[TAB] Wait`, labelled in `base.tscn` — it was just uncosted at a capped clock, so it handed out free reserve forever; and (b) the GDD explicitly rules out a win/lose at the clock cap: the crossing "is not an ending — it is a transition", and Last Song is "the hardest recovery arc. **It is still a recovery arc.**" Grief zero likewise is a *summoning tier* that costs a heavy clock advance ("Anthe ages noticeably"), not a fail state. So the economy has **no terminal state by design**: a death spends a tick and nets −1 reserve, a clean extraction recovers reserve and buys its tick back ("every successful run buys her time"), waiting trades a tick for reserve, and an exhausted summon is paid out of Anthe. The clock is a **ratchet** — the refund never exceeds what the run actually spent, so at the cap an extraction refunds nothing and LAST SONG stands. Tuning constants are at the top of `game_state.gd`.

---

## Character Docs

Each character has a reference doc in `docs/` covering sprite strategy, sheet layout, node architecture, shader params, and generation prompts.

| Doc | Character | Status |
|-----|-----------|--------|
| `docs/WARRIOR.md` | The Warrior (player) | 🚧 In progress — see gaps below |

**Warrior gaps (as of 2026-06-04):**
- `warrior_move.png` not yet created — MOVE state has no sprite sheet and no `_ANIM_MANIFEST` entries. Works in 8-dir mode (uses idle pose), silent failure in legacy fallback.
- HURT / DYING / SUMMONING still on v1 sheets — baked particles and atmospheric edges, inconsistent with v2 node architecture (these effects should be Godot nodes, not baked into frames).
- ECHO_ACTIVE reuses `idle_*` animation — placeholder, not a dedicated visual state.

When adding a new character, create `docs/[CHARACTER].md` following the WARRIOR.md pattern before writing any GDScript or importing sprites.

---

## Project Structure

```
scenes/
  main.tscn          Entry point
  warrior.tscn        Player character
  base.tscn           Between-run base screen
  hud.tscn            HUD overlay
  enemy.tscn          Base enemy
  enemy_fleer.tscn    Fleer variant
  enemy_phaser.tscn   Phaser variant
  attack_arc.tscn     Warrior attack hitbox/visual
  test.tscn           Dev test scene

  ring1_iso_test.tscn  3D iso rendering spike (reference impl — walled off, not in the game)

scripts/              GDScript (.gd) — one per scene
  ring1_iso_test.gd    3D iso spike: ortho camera rig, SubViewport pipeline, cel materials, billboard warrior
assets/
  sprites/
	warrior_8dir/     8-direction rotation PNGs (64×64) — legacy 2D-era sheets, unused by the mesh warrior
	notation/         Individual notation glyph PNGs
	notation_glyphs.png  Composited 128×32 spritesheet
  shaders/
	cel.gdshader        Spatial cel/toon shader (flat quantised lighting) — 3D surfaces
	pixel_post.gdshader  Canvas-item post pass (palette snap; optional dither/edge)
	*.gdshader          Other canvas-item shaders (2D effects)
docs/
  gen/                Raw AI-generated sheets (read-only, never import)
  WARRIOR.md          Warrior sprite + architecture reference
  RENDERING_3D.md     Low-res 3D iso pipeline (the proven recipe + gotchas)
  MIGRATION_3D.md     Plan for moving the live game from 2D to 3D
```

**Rendering note:** the 3D pipeline lives entirely inside SubViewports and does **not** depend on `project.godot` window/stretch settings — keep it that way. Spatial (3D) shaders use `shader_type spatial`; canvas-item (2D/post) shaders use `shader_type canvas_item`. `docs/RENDERING_3D.md` is the source of truth for the camera, viewport chain, cel shader, and palette.

## Sprite Cleanup (when new sheets are generated)

Raw AI-generated sheets land in `docs/gen/`. Claude Code handles:
- Background removal (colored/white → transparent alpha)
- Crop to content — remove label margins baked into some sheets
- No scaling — generation size equals game size (64×64)
- Output to `assets/sprites/`

Tool: `scripts/cleanup_sprites.py` — extend as needed.  
Do not use bilinear or bicubic scaling. Do not add anti-aliasing.

---

## Code Conventions

- GDScript only. No C#.
- `snake_case` for variables and functions. `UPPER_CASE` for constants.
- Private members prefixed with `_`.
- State machine via `enum State` + `_change_state()` / `_enter_state()` / `_exit_state()`.
- No `@export` on internal state vars — only on designer-tunable params (`hollow_stress`, `tribe_coherence_tier`).
- Do not add `print()` debug calls — use `push_warning()` for recoverable issues.

## Do Not Touch

- `project.godot` — window/render settings are correct, do not modify. The 3D pipeline is self-contained in SubViewports and needs no project-level render changes; if migration ever appears to require one, raise it explicitly rather than editing here.
- `.godot/` cache directory — let the editor manage this.
- `docs/gen/` raw sheets — read-only reference, never import directly.
- `scenes/ring1_iso_test.tscn` / `scripts/ring1_iso_test.gd` — the rendering reference spike. Treat as read-only reference for the pipeline; don't wire it into the game.
