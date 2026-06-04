# Summoned — Claude Code Instructions

Godot 4 project. Resolution 480×270. Pixel art — nearest-neighbour filter throughout.  
Design intent: `../idea/Summoned_GDD.html`.  
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

scripts/              GDScript (.gd) — one per scene
assets/
  sprites/
	warrior_8dir/     8-direction rotation PNGs (64×64)
	notation/         Individual notation glyph PNGs
	notation_glyphs.png  Composited 128×32 spritesheet
  shaders/            Canvas item shaders (.gdshader)
docs/
  gen/                Raw AI-generated sheets (read-only, never import)
  WARRIOR.md          Warrior sprite + architecture reference
```

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

- `project.godot` — window/render settings are correct, do not modify.
- `.godot/` cache directory — let the editor manage this.
- `docs/gen/` raw sheets — read-only reference, never import directly.
