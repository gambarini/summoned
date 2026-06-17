# Summoned — Claude Code Instructions

Godot 4 project. **Low-resolution 3D isometric pixel art** — cel-shaded 3D world seen through an orthographic, freely-rotatable camera, rendered at a low internal resolution and palette-snapped so it reads as hand-drawn pixel art. Characters are camera-facing billboards from pixel sprite sheets. Nearest-neighbour filtering throughout — no bilinear anywhere.

> **Direction change (2026-06):** the project pivoted from 2D top-down to low-res 3D isometric. **Migration Phases 0–4 + Phase 2b part 1 are done (2026-06-16): the Ring 1 run loop (`main.tscn`) plays in 3D end-to-end** — `IsoRig` rig + `Ring1World` terrain + warrior/enemy/arc billboards synced from the still-authoritative 2D sim (Option B hybrid), 2D HUD on top; the warrior's core effects (hover bob, notation drift, resonance/burst shockwave rings) read in 3D. Remaining: **Phase 2b part 2** (the Hollow void/ember/pull + hem/glow shader — Hollow is gated on `hollow_stress`, so invisible in normal play) and **Phase 5** (rings 2–5, polish). `base.tscn` stays a 2D diorama by choice. The original spike `scenes/ring1_iso_test.tscn` is the read-only look reference. See `docs/RENDERING_3D.md` (the pipeline) and `docs/MIGRATION_3D.md` (the plan + current status).

Design intent: `../idea/Summoned_GDD.html` (§16 Art Direction reflects the 3D pivot).  
Character references: `docs/[CHARACTER].md` — see Character Docs below.

---

## Current Priority

Close the run loop: **run start → fight → die → tribe cost → base → run again.**

Scenes exist for warrior, enemies (fleer, phaser), base, HUD, and main. Game state is wired via `game_state.gd`. The loop is not yet closed — death does not flow into tribe cost, base screen, or re-summoning.

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
	warrior_8dir/     8-direction rotation PNGs (64×64) — used as billboards in 3D
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
