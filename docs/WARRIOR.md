# Warrior — Technical Implementation Reference

> Design intent lives in the GDD (`../../idea/Summoned_GDD.html`) Section 18.  
> This document covers how to implement that intent in Godot 4.

---

## Sprite Strategy — Current Status (May 2026)

### Architecture: Hand-crafted Pixelrama sprites + Shader effects

All warrior sprites are hand-crafted in **PixelLab's Pixelrama editor** and exported as PNG files. Rendered at **full 64×64 in Godot — no scaling.**

All dynamic effects (glow, particles, trail, Lament arc) are Godot nodes — not baked into sprites.

---

### Current Sprite Sheet — `warrior_idle_attack.png`

**File:** `assets/sprites/warrior_idle_attack.png`  
**Sheet size:** 448×512px  
**Frame size:** 64×64px per frame  
**Layout:** 8 rows × 7 columns

#### Row → Direction

| Row | Direction |
|---|---|
| 0 | S |
| 1 | SE |
| 2 | E |
| 3 | NE |
| 4 | N |
| 5 | NW |
| 6 | W |
| 7 | SW |

All 8 directions are explicitly drawn. No `flip_h` mirroring needed for this sheet.

#### Column → Frame / Phase

| Col | Frame | Animation | Phase |
|---|---|---|---|
| 0 | F1 | IDLE (1 frame) + ATTACK F1 | Idle / Attack start |
| 1 | F2 | ATTACK | STARTUP |
| 2 | F3 | ATTACK | STARTUP |
| 3 | F4 | ATTACK | ACTIVE |
| 4 | F5 | ATTACK | ACTIVE |
| 5 | F6 | ATTACK | RECOVERY |
| 6 | F7 | ATTACK | RECOVERY |

**IDLE** = col 0 only (1 frame per direction, static — no animation loop).  
**ATTACK** = cols 0–6 (7 frames per direction, col 0 shared with idle as the start pose).

#### SpriteFrames regions per animation

```
idle_{dir}     → row * 64,  col 0 * 64,  64×64  (1 frame)
startup_{dir}  → row * 64,  col 0 * 64,  64×64  (3 frames: cols 0–2)
active_{dir}   → row * 64,  col 3 * 64,  64×64  (2 frames: cols 3–4)
recovery_{dir} → row * 64,  col 5 * 64,  64×64  (2 frames: cols 5–6)
```

---

### Idle & Move Animation — Static sprite + Shader (no animation frames)

Idle and Move both use a **single static frame per direction** (col 0 of `warrior_idle_attack.png`). No frame animation. All visual life comes from the canvas shader and particles.

Shader: `assets/shaders/warrior_hover.gdshader` — **fragment-only** (hem glow + shimmer).
Applied to: `Sprite8Dir` (the `Sprite2D` node active during IDLE and MOVE states).

The **hover bob + sway are driven in GDScript** (`_update_hover()` in `warrior.gd`), not
the shader, so the Hollow nodes (`HollowVoid`/`HollowGlow`/`HollowPull`) share the same
per-frame offset and stay welded to the chest as the body bobs. Phase is integrated
incrementally (`_bob_phase += speed * delta`) so the movement-driven speed change never
makes the sprite race through cycles — the old `sin(TIME * speed)` form did, which is
what caused the visible up/down "jump" when starting and stopping. Bob runs only in
IDLE/MOVE; it zeroes in every other state.

| Parameter | Default | Effect |
|---|---|---|
| `hover_speed` | 0.8 | Paces the fragment animation (hem pulse, shimmer); also base bob speed in GDScript |
| `hem_tint` | `#D4803A` | Amber colour for hem glow |
| `hem_strength` | 0.5 | Hem glow intensity at idle |
| `hem_threshold` | 0.7 | UV.y cutoff — bottom 30% gets glow |
| `move_intensity` | 0.0 | 0=idle, 1=moving. Tweened by warrior.gd. Scales hem + shimmer (shader) and bob + sway (GDScript). |

#### What `move_intensity` does

| Effect | Idle | Full move | Driven by |
|---|---|---|---|
| Vertical bob | 1.5 px | ~2.4 px | GDScript `_update_hover` |
| Bob speed | 0.8 | ~1.16 | GDScript `_update_hover` |
| Horizontal sway | 0 px | ±1.2 px pendulum (different frequency) | GDScript `_update_hover` |
| Hem glow | 0.5 strength | ~0.85 strength | shader fragment |
| Lavender shimmer | off | Subtle #A080E0 flicker at top of sprite (18% max) | shader fragment |

`move_intensity` is tweened to 1.0 over 0.18s on MOVE entry and back to 0.0 over 0.25s on MOVE exit, via `_tween_move_intensity()` in `warrior.gd`.

#### `_start_idle_pulse()`

Runs during both IDLE and MOVE. Adds a slow alpha breath (0.75→1.0, 0.45s each way, looping) on the active sprite node.

#### `NotationDrift` particles

`GPUParticles2D` node (`warrior.tscn`), configured at runtime in `warrior.gd::_setup_notation_drift()`. Always emitting. Sheds random notation glyphs sampled from `notation_glyphs.png` (4-frame strip): a `CanvasItemMaterial` with `particles_animation` + per-particle randomised `anim_offset` gives each glyph a different static frame (torn stave / notehead / barline).

`local_coords = false` (world space) — emitted glyphs stay where they were born, so as the warrior moves away they settle into the trail of "score debris" the GDD calls for. No per-frame direction push needed; the trail falls out of the same emitter.

`amount_ratio` tweens from `NOTATION_IDLE_RATIO` (0.4) to `NOTATION_MOVE_RATIO` (0.8) on MOVE enter/exit (`_tween_notation_intensity`, called from `_tween_move_intensity`), and the whole range is multiplied by `_NOTATION_TIER_SCALE[tribe_coherence_tier]` so the warrior drifts denser and less stable in the outer rings.

---

### Action States — Current Sprite Sheets

The `AnimatedSprite2D` node (`Sprite`) handles all action states. IDLE and ATTACK are served from `warrior_idle_attack.png`. HURT, DYING, and SUMMONING use v1 sheets. MOVE is not yet created.

| File | Layout | State(s) | Status |
|---|---|---|---|
| `warrior_idle_attack.png` | 8 rows × 7 cols | IDLE (col 0) + ATTACK_STARTUP/ACTIVE/RECOVERY (cols 0–6) | ✅ Active |
| `warrior_hurt_v1.png` | 1 row × 2 cols | HURT (universal) | ✅ v1 active |
| `warrior_dying_v1.png` | 1 row × 6 cols | DYING (universal) | ✅ v1 active |
| `warrior_summoning_v1.png` | 1 row × 6 cols | SUMMONING (universal) | ✅ v1 active |
| `warrior_move.png` | TBD | MOVE (8 dirs) | ⏳ Not yet created |

---

---

## Attack Arc — `scenes/attack_arc.tscn`

The attack arc is a short-lived `Node2D` spawned by `warrior.gd` on `ATTACK_ACTIVE` entry. It travels forward from the warrior's hand and fades out. It carries the hitbox.

### Node structure

```
AttackArc (Node2D, attack_arc.gd)
├── ArcGlow  (Polygon2D) — wide soft halo, #A080E0 at 60% alpha
├── ArcCore  (Polygon2D) — main strike shape, #C4547A full alpha
├── ArcInner (Polygon2D) — bright inner edge, #F0E8D8 at 85% alpha
└── HitArea  (Area2D)
	└── HitShape (CollisionPolygon2D) — matches ArcCore polygon
```

Layers are drawn back-to-front: Glow behind, Inner on top. All polygons are built at runtime in `_ready()` via `_build_arc_polygon()`.

### Geometry constants

| Constant | Value | Effect |
|---|---|---|
| `INNER_R` | 10.0 | Inner radius of core arc |
| `OUTER_R` | 26.0 | Outer radius of core arc |
| `HALF_ANGLE` | 55.0° | Half-spread of the arc fan |
| `STEPS` | 12 | Polygon smoothness |

Glow polygon: inner×0.4, outer×1.55, angle+14°. Inner polygon: inner×1.2–1.9, angle-16°.

### Travel constants (tune in-game)

| Constant | Value | Effect |
|---|---|---|
| `HAND_OFFSET` | 12.0 px | Spawn offset forward from warrior center |
| `TRAVEL_DIST` | 52.0 px | Distance arc travels before fading |
| `DURATION` | 0.32 s | Total lifetime |

### Animation sequence

- t=0.00: spawns at warrior center + `HAND_OFFSET` px forward, scale (0.5, 0.6)
- t=0–0.11s: scale punches to (1.1, 1.0), ease-out — snap feel
- t=0–0.32s: travels `TRAVEL_DIST` px forward, quad ease-out (fast burst, settles)
- t=0–0.32s: `ArcGlow` alpha fades 0.6 → 0 across full travel
- t=0.13–0.32s: `ArcCore` and `ArcInner` fade to 0 in second half
- t=0.32s: `queue_free`

### Spawn call (from warrior.gd)

```gdscript
func _spawn_attack_arc() -> void:
	var arc := AttackArcScene.instantiate()
	get_parent().add_child(arc)
	arc.global_position = global_position   # warrior center
	arc.set_direction(_attack_dir)          # sets rotation, offsets to hand, starts tween
	arc.hit_target.connect(_on_hit)
```

`set_direction()` must be called after `add_child()` — it adjusts `global_position` by `HAND_OFFSET` and fires the animation.

---

### What Claude Code Should Do

See `CLAUDE.md` in the project root for the full task list. Key items for the warrior:

1. **✅ Download sprites** — all 8 rotation PNGs are in `assets/sprites/warrior_8dir/` with `.import` files.
2. **✅ Verify scene** — `scenes/warrior.tscn` has `Sprite8Dir` (Sprite2D) with `ShaderMaterial` and `warrior_hover.gdshader`. Scene integrity confirmed.
3. **Import fix** — `warrior_idle_attack.png` may be missing a `.import` file (not auto-imported yet). Open the Godot editor once to trigger auto-import, or copy the pattern from another `.import` file in the same folder.

---

### Generated Sprite Sheets (v1 — reference only)

All sheets located in `docs/gen/`. ⚠️ V1 sheets have baked-in particles and atmospheric edges — do not use as final frames for v2. Retained as silhouette reference.

**Notes for Claude Code cleanup (if v2 sheets are generated):**
- Backgrounds are colored/white — background removal required
- Text labels are baked into margins — slice regions must land on sprite content only
- Style is painterly/atmospheric — accepted art direction, not a defect

**⚠️ Architecture pivot — v2 generation superseded by Pixellab object approach**

V1 sheets had baked-in particles and atmospheric edge effects. V2 approach: base sprite = dark form only (now via Pixellab object), all dynamic effects via shader + CPUParticles2D nodes.

---

## Godot Node Architecture

Two sprite nodes serve different states. `Sprite8Dir` is visible during IDLE and MOVE; `Sprite` (AnimatedSprite2D) takes over for all action states. Only one is shown at a time.

```
CharacterBody2D (Warrior)
├── Sprite8Dir (Sprite2D)          ← IDLE/MOVE: rotation sprites + hover shader
├── Sprite (AnimatedSprite2D)      ← ATTACK, HURT, DYING, SUMMONING, ECHO_ACTIVE
├── NotationDrift (GPUParticles2D) ← world-space notation drift + trail (drawn behind body)
├── HollowPull (GPUParticles2D)    ← notation drawn inward to the chest, ratio = hollow_stress
├── HollowVoid (Sprite2D)          ← dark #0D0A1E recess (normal blend) — the absence the ember burns in
├── HollowGlow (Sprite2D)          ← additive ember core sunk inside HollowVoid, dims with hollow_stress
├── CollisionShape2D
├── Camera2D
├── AttackCooldown (Timer)         ← 0.35s, prevents rapid re-attack
├── ResonanceCooldown (Timer)      ← 2.5s
├── StartupTimer (Timer)           ← 0.117s → transitions to ATTACK_ACTIVE
├── ActiveTimer (Timer)            ← 0.083s → transitions to ATTACK_RECOVERY
├── RecoveryTimer (Timer)          ← 0.4s → transitions to IDLE
├── HurtTimer (Timer)              ← 0.233s → transitions to IDLE
├── DyingTimer (Timer)             ← 2.5s → emits warrior_died
└── SummoningTimer (Timer)         ← 2.5s → transitions to IDLE
```

**`Sprite8Dir`** holds the `ShaderMaterial` (`warrior_hover.gdshader`). It shows one of the 8 rotation PNGs (`warrior_8dir/`), updated each frame via `_refresh_8dir()`. Falls back to the AnimatedSprite2D if fewer than 8 PNGs are found.

**`Sprite`** uses a `SpriteFrames` resource built at runtime in `_setup_sprite_frames()` from `warrior_idle_attack.png` (and v1 sheets for hurt/dying/summoning).

### What goes in the base sprite

The sprite frame should contain:
- Dark triangular cloak form (`#0D0A1E`, `#2A1448`, `#7B4EA0`)
- Crown spikes (`#2A1448` tipped with `#C0A0F0`)
- Warm bleed at the base (`#C4547A` → `#D4803A`)
- Dark void at the Hollow position (the absence — no fill, or `#0D0A1E` only)

### What does NOT go in the base sprite

- Notation particle dots — driven by `NotationDrift` (CPUParticles2D)
- Lament arc — spawned as `AttackArcScene` child on ATTACK_ACTIVE entry
- Atmospheric dissolving edge — handled by shader `cloak_edge_definition` param

---

## Direction Structure

8 directions total. All 8 directions are explicitly drawn — no `flip_h` mirroring. This applies to both `warrior_idle_attack.png` (8 rows) and the `warrior_8dir/` rotation PNGs.

| Direction | Code | Sprite source |
|---|---|---|
| Down | `s` | `warrior_idle_attack.png` row 0 / `south.png` |
| Down-Right | `se` | `warrior_idle_attack.png` row 1 / `south-east.png` |
| Right | `e` | `warrior_idle_attack.png` row 2 / `east.png` |
| Up-Right | `ne` | `warrior_idle_attack.png` row 3 / `north-east.png` |
| Up | `n` | `warrior_idle_attack.png` row 4 / `north.png` |
| Up-Left | `nw` | `warrior_idle_attack.png` row 5 / `north-west.png` |
| Left | `w` | `warrior_idle_attack.png` row 6 / `west.png` |
| Down-Left | `sw` | `warrior_idle_attack.png` row 7 / `south-west.png` |

### Hollow Visibility Per Direction

| Direction | Hollow | Detail |
|---|---|---|
| S (down) | Full | 3–4px #F0E8D8 at chest center — primary view |
| SE (down-right) | Partial | 2px #F0E8D8 slightly left of center |
| E (right) | Sliver | 1px #F0E8D8 at left edge of form only |
| NE (up-right) | None | Form turned away |
| N (up) | None | Pure dark form from behind |
| NW (up-left) | None | Form turned away (mirrors NE) |
| W (left) | Sliver | 1px #F0E8D8 at right edge of form only (mirrors E) |
| SW (down-left) | Partial | 2px #F0E8D8 slightly right of center (mirrors SE) |

This gate (`_refresh_hollow_facing()` · `_HOLLOW_DIR_VIS`) applies in **every directional
state** — IDLE/MOVE *and* the attack/echo states, which all pose toward `_facing_dir`. So
the Hollow stays dark when the back is turned even mid-attack. HURT/DYING/SUMMONING use
single-direction front sheets and keep the wound at full.

---

## Sprite vs. Shader Classification

### Directional Sprite Frames — all 8 directions explicit

| State | Frames per dir | Dirs | Total frames | Notes |
|---|---|---|---|---|
| IDLE | 1 (static) | 8 | 8 | Col 0 of warrior_idle_attack.png. Shader carries all visual life. |
| ATTACK_STARTUP | 3 | 8 | 24 | Cols 0–2. Starts from idle pose. |
| ATTACK_ACTIVE | 2 | 8 | 16 | Cols 3–4. Hitbox fires here. |
| ATTACK_RECOVERY | 2 | 8 | 16 | Cols 5–6. Returns to idle. |
| MOVE | TBD | 8 | TBD | Not yet created. |

### Universal Sprite Frames — 1 set, no direction

| State | Frames | Notes |
|---|---|---|
| HURT | 2 | Stagger in place — use S-facing pose |
| DYING | 6 | Dissolution — start from S-facing idle |
| SUMMONING | 6 | Assembly — final frame must match IDLE_S frame 1 exactly |

**Directional total: 60 frames. Universal total: 14 frames. Grand total: 74 frames.**

### Shader / Parameter Only — no new sprites

| State or modifier | Base frames | Parameters |
|---|---|---|
| ECHO_ACTIVE | IDLE (current direction) | `modulate.a = 0.65` · `hollow_pulse = false` · `hollow_intensity = 0.4` · `particle_direction = inward` |
| HOLLOW_STRESS 0→3 | Any active state | `hollow_radius ↑` · `hollow_center_brightness ↓` · `particle_inward_ratio ↑` · `trail_intensity ↑` |
| TRIBE_COHERENCE | Set at SUMMONING, persists all run | `particle_scatter_density` · `cloak_edge_definition` · `hollow_pulse_speed` · `idle_anim_speed` |
| LOW_HEALTH | Any active state | `hollow_pulse_urgency ↑` · `cloak_dissolution_rate ↑` · hurt sound variant → `"low_health"` |
| CHAIN_COUNT 0→4 | ATTACK states | Separate UI node (chain arc indicator). Not a sprite parameter. |
| Lament arc effect | None — separate node | `GPUParticles2D` child. Spawned on ATTACK_ACTIVE entry. Direction + scale driven by CHAIN_COUNT. |

### No Warrior Sprite

| State | What's shown | Notes |
|---|---|---|
| DEAD | Base screen — tribe portrait | Warrior node hidden or scene unloaded |

---

## Sprite Sheet Specifications

All sprites: **64×64px per frame — generation size and game size are the same.** No scaling pipeline. Transparent background (PNG alpha). 8-color palette only.

> **Pixellab dimensions:** Use W × H in the generator.

| Sheet | Layout | Dimensions (W×H) | Status |
|---|---|---|---|
| Turnaround reference | 5 panels × 1 pose | 320×64 | Reference only |
| `warrior_idle_attack.png` — IDLE + ATTACK | 8 rows × 7 cols | 448×512 | ✅ Active |
| `warrior_move.png` — MOVE | 8 rows × 2 frames | 128×512 | ⏳ TBD |
| `warrior_hurt_v1.png` — HURT | 1 row × 2 frames | 128×64 | ✅ v1 active |
| `warrior_dying_v1.png` — DYING | 1 row × 6 frames | 384×64 | ✅ v1 active |
| `warrior_summoning_v1.png` — SUMMONING | 1 row × 6 frames | 384×64 | ✅ v1 active |

---

## Godot SpriteFrames Naming Convention

One `SpriteFrames` resource on the warrior node. Animation names follow `state_direction`.  
All 8 directions are explicit animations — no `flip_h` mirroring. `_DIR_ANIM` maps every direction to `flip_h = false`.

```
idle_s       idle_se      idle_e       idle_ne      idle_n       idle_nw      idle_w       idle_sw
startup_s    startup_se   startup_e    startup_ne   startup_n    startup_nw   startup_w    startup_sw
active_s     active_se    active_e     active_ne    active_n     active_nw    active_w     active_sw
recovery_s   recovery_se  recovery_e   recovery_ne  recovery_n   recovery_nw  recovery_w   recovery_sw
move_s       move_se      move_e       move_ne      move_n       move_nw      move_w       move_sw
hurt                      (universal — no direction suffix)
dying                     (universal)
summoning                 (universal)
```

**Note:** All 8 directions are explicitly drawn in `warrior_idle_attack.png` — no `flip_h` mirroring required for IDLE/ATTACK states.

---

## Shader Parameters Reference

Defined as uniform variables on the warrior's `ShaderMaterial`. All states read these at runtime.

```gdscript
# Hollow
uniform float hollow_intensity    : float = 1.0     # 0.0–1.0
uniform float hollow_radius       : float = 1.0     # 0.5–2.0 (multiplier)
uniform bool  hollow_pulse        : bool  = true
uniform float hollow_pulse_speed  : float = 1.0     # 0.5–2.0

# Particles
uniform float particle_scatter_density  : float = 1.0   # 0.5–2.0
uniform float particle_inward_ratio     : float = 0.0   # 0.0 = all outward, 1.0 = all inward
uniform float trail_intensity           : float = 1.0   # 0.0–2.0

# Form coherence
uniform float cloak_edge_definition    : float = 1.0   # 0.0 = max dissolve, 1.0 = most coherent
uniform float cloak_dissolution_rate   : float = 1.0
uniform float idle_anim_speed          : float = 1.0

# Health
uniform bool  low_health              : bool  = false
uniform float hollow_pulse_urgency    : float = 1.0
```

### HOLLOW_STRESS Level Values

```gdscript
const HOLLOW_STRESS_PARAMS = {
	0: { hollow_radius=1.0, hollow_center_brightness=1.0, particle_inward_ratio=0.0, trail_intensity=1.0 },
	1: { hollow_radius=1.2, hollow_center_brightness=0.85, particle_inward_ratio=0.25, trail_intensity=1.3 },
	2: { hollow_radius=1.5, hollow_center_brightness=0.65, particle_inward_ratio=0.6, trail_intensity=1.7 },
	3: { hollow_radius=1.9, hollow_center_brightness=0.4, particle_inward_ratio=0.9, trail_intensity=2.0 },
}
```

### TRIBE_COHERENCE Values (set at SUMMONING, held all run)

```gdscript
const TRIBE_COHERENCE_PARAMS = {
	"high":     { particle_scatter_density=0.6, cloak_edge_definition=1.2, hollow_pulse_speed=0.7, idle_anim_speed=0.9 },
	"medium":   { particle_scatter_density=1.0, cloak_edge_definition=1.0, hollow_pulse_speed=1.0, idle_anim_speed=1.0 },
	"low":      { particle_scatter_density=1.4, cloak_edge_definition=0.75, hollow_pulse_speed=1.3, idle_anim_speed=1.1 },
	"critical": { particle_scatter_density=1.9, cloak_edge_definition=0.5, hollow_pulse_speed=1.7, idle_anim_speed=1.2 },
}
```

---

## Godot Pixel Art Project Settings

Set once at project creation. Do not change after assets are imported.

```
Project Settings → Display → Window:
  Viewport Width:  480
  Viewport Height: 270
  Window Width:    1920
  Window Height:   1080

Project Settings → Rendering → Textures:
  Default Texture Filter: Nearest

Project Settings → Rendering → 2D:
  Snap 2D Transforms to Pixel: On
  Snap 2D Vertices to Pixel:   On

Project Settings → Display → Window → Stretch:
  Mode:   canvas_items
  Aspect: keep
```

---

## Generation Prompts — Sprite Sheets

### Generator: Pixellab (recommended)

Pixellab is purpose-built for pixel art sprites and produces harder, more consistent edges than general-purpose image generators (ChatGPT, Midjourney). Use the character turnaround flow.

**Reference image:** Use the 512×512 ChatGPT pixel art warrior image as the style reference in Pixellab — it is already at pixel art scale and style. Do not use the original concept art (too large, wrong style for the generator).

**Background removal:** Select "Yes" when Pixellab asks about removing the opaque background — the generator needs to understand the character boundary to produce correct transparent output.

**Generation order:** Step 1 (turnaround) first. Approve before generating animation sheets — every subsequent prompt uses the approved turnaround for consistency.

**Architecture note:** All prompts below describe the **base sprite only**. Do not request particles, trail, Lament arc, or atmospheric dissolving edges in generated frames — these are Godot nodes (see Node Architecture above). The sprite should contain: dark cloak form, crown, warm bleed, dark void at Hollow position.

---

**Palette (strict — no other colors permitted):**
- `#0D0A1E` — Void
- `#2A1448` — Body dark
- `#7B4EA0` — Cold glow
- `#C0A0F0` — Lavender highlight
- `#C4547A` — Warm bleed
- `#D4803A` — Amber bleed
- `#F0E8D8` — Hollow center
- `#A080E0` — Notation particles (used in animation frames only, not in base turnaround)

---

### Step 1 — Turnaround Reference (generate first, W=320 H=64)

> Pixel art character turnaround sheet. 5 panels side by side, each 64×64px. Total 320×64px. Strict pixel art — hard edges, no anti-aliasing, no blending. Transparent background. Strict 8-color palette: #0D0A1E, #2A1448, #7B4EA0, #C0A0F0, #C4547A, #D4803A, #F0E8D8, #A080E0.
>
> Character: The Summoned Warrior. A being assembled from dark matter — triangular hooded cloak, crown of upward spikes, burning void at chest center. Viewed from above (top-down perspective). No particles, no trail, no atmospheric edge effects — clean base form only.
>
> Panel 1 — S (facing down, toward camera): Wide dark triangular cloak, maximum spread. Crown at top: 2–3 spikes of #2A1448 tipped #C0A0F0. Hollow at vertical center: 3–4px #F0E8D8 surrounded by 1px #7B4EA0 halo then #0D0A1E void. Warm bleed: bottom rows shift #C4547A → #D4803A. Clean cloak boundary.
>
> Panel 2 — SE (three-quarter view): Cloak slightly rotated — wider left, narrower right. Hollow: 2px #F0E8D8 left of center. Crown tips top-left. Warm bleed bottom-left.
>
> Panel 3 — E (side profile): Cloak narrowed to half down-facing width. Crown: 1–2 spike tips at top-right. Hollow: 1px #F0E8D8 at left edge of form only. Warm bleed bottom-left.
>
> Panel 4 — NE (three-quarter rear): No Hollow visible. Crown tips at top-right. Warm bleed bottom-right.
>
> Panel 5 — N (facing away): Pure dark form from behind. Wide triangular silhouette. No Hollow. Interior #7B4EA0 at cloak center. Warm bleed at bottom.
>
> Style to preserve from reference: strict pixel art, hard pixel edges, top-down perspective, dark triangular cloak form, crown spikes, warm colour bleed at base.

---

### Legacy Prompts (v1 — for reference only)

> ⚠️ The prompts below were used for v1 generation. They describe baked-in particles and atmospheric dissolving edges, which conflict with the v2 node architecture. Retain as reference for frame count, layout, and directional detail. Do not use as-is for v2 generation.

---

### Prompt 1 — Reference Sheet (v1 legacy)

> True pixel art character reference sheet. No anti-aliasing, no blending, hard pixel edges. Transparent background. 5 panels arranged horizontally, each panel 32×48 pixels. Total sheet: 160×48 pixels.
>
> Character: The Summoned Warrior. A being assembled from shredded musical notation — torn staves, scattered noteheads, broken barlines — woven into dark matter. Not flesh. Not cloth. Pure dark form with a burning void at his chest. Each panel shows the same character from a different top-down angle.
>
> Strict 8-color palette throughout all panels: #0D0A1E, #2A1448, #7B4EA0, #C0A0F0, #C4547A, #D4803A, #F0E8D8, #A080E0. No other colors.
>
> Panel 1 — Down (S, facing camera): Wide dark triangular cloak at maximum spread. Crown at top: 2–3 upward spikes of #2A1448 tipped with #C0A0F0. Hollow at vertical center: 3–4 pixels of #F0E8D8, surrounded by 1px #7B4EA0 halo then #2A1448. Warm bleed: bottom 6 rows shift through #C4547A to #D4803A at base. Cloak boundary: scatter of #2A1448, #7B4EA0, #A080E0 — no clean edge.
>
> Panel 2 — Down-Right (SE, three-quarter view): Cloak slightly rotated — wider on the left side, narrower on the right. Hollow: 2 pixels of #F0E8D8 slightly left of center. Crown tips visible at top-left. Warm bleed at bottom-left corner.
>
> Panel 3 — Right (E, side profile): Cloak narrowed to roughly half the down-facing width. Crown: 1–2 spike tips at top-right. Hollow: 1 pixel of #F0E8D8 at the left edge of the form only. Warm bleed at bottom-left.
>
> Panel 4 — Up-Right (NE, three-quarter rear): Three-quarter rear view. No Hollow visible. Crown tips at top-right. Warm bleed at bottom-right corner.
>
> Panel 5 — Up (N, facing away): Pure dark form from behind. Same wide triangular silhouette. No Hollow. Interior #7B4EA0 glow visible at cloak interior. Warm bleed at the bottom.
>
> Label each panel below: "S / SE / E / NE / N". No borders, no background fill.

---

### Prompt 2 — IDLE (5 rows × 4 frames = 128×160px)

> True pixel art sprite sheet. 5 rows × 4 frames. Each frame 32×32 pixels. Total: 128×160 pixels. Transparent background. Strict 8-color palette. Match all silhouettes and Hollow positions to the reference sheet exactly.
>
> All rows: micro-animation only. Notation particle dots (1–2px of #A080E0) shift position slightly across frames. Cloak boundary pixels vary slightly each frame. The warrior is never fully still.
>
> Row 1 — S: Hollow pulses — frames 1 and 3 full brightness (3–4px #F0E8D8), frames 2 and 4 at 80% (replace 1 outer Hollow pixel with #C0A0F0). 3–4 particle dots drift slowly outward at cloak boundary.
>
> Row 2 — SE: Hollow (2px) pulses same rhythm as Row 1. Particle dots at cloak boundary. Crown tips micro-shift on frame 3.
>
> Row 3 — E: Single Hollow edge pixel pulses between #F0E8D8 and #C0A0F0. Particle dots at right cloak edge drift.
>
> Row 4 — NE: No Hollow. Particle dots at cloak boundary drift. 1-pixel variation in cloak edge width on frames 2 and 4.
>
> Row 5 — N: No Hollow. Particle dots at rear cloak boundary drift outward. Crown tips micro-shift on frame 3. Interior #7B4EA0 glow varies slightly between frames.
>
> Label rows on left margin: "S / SE / E / NE / N". Label frames above: "1 / 2 / 3 / 4".

---

### Prompt 3 — MOVE (5 rows × 2 frames = 64×160px)

> True pixel art sprite sheet. 5 rows × 2 frames. Each frame 32×32 pixels. Total: 64×160 pixels. Transparent background. Same 8-color palette. Match reference sheet for all silhouettes.
>
> Row 1 — S: Frame 1: cloak shifts left 1–2px at lower edge, trail particles to the right. Frame 2: cloak shifts right, trail particles to the left. Hollow stays centered. Crown stable.
>
> Row 2 — SE: Frame 1: cloak wider on one side (leading edge). Frame 2: shifts back. Trail particles trail toward NW. Partial Hollow stays in position.
>
> Row 3 — E: Frame 1: cloak slightly compressed (narrower — leading into movement). Frame 2: slightly expanded. Trail particles to the left. Single Hollow edge pixel visible both frames.
>
> Row 4 — NE: Frame 1: cloak wider on left side. Frame 2: wider on right. Trail particles trail toward SW. No Hollow.
>
> Row 5 — N: Frame 1: cloak shifts left 1–2px at lower edge. Frame 2: shifts right. Trail particles trail downward. No Hollow.
>
> Label rows: "S / SE / E / NE / N". Label frames: "1 / 2".

---

### Prompt 4 — ATTACK STARTUP + ACTIVE + RECOVERY (5 rows × 6 frames = 192×160px)

> True pixel art sprite sheet. 5 rows × 6 frames. Each frame 32×32 pixels. Total: 192×160 pixels. Transparent background. Same 8-color palette. Match reference sheet for all silhouettes.
>
> Each row: frames 1–2 STARTUP, frames 3–4 ACTIVE, frames 5–6 RECOVERY.
>
> STARTUP (frames 1–2, all rows): Particles pull inward. Cloak tightens slightly. Hollow brightens on frame 2 (outer halo shifts from #7B4EA0 to #C0A0F0). Notation fragments at cloak edge begin rotating toward the attack direction.
>
> ACTIVE (frames 3–4, all rows): Cloak at maximum extension. Hollow flares to maximum (full #F0E8D8 center). Crescent notation arc pixels visible around warrior in attack direction: #C4547A at arc core, #C0A0F0 at outer edge. Arc directions: Row 1 S → arc below; Row 2 SE → arc bottom-right; Row 3 E → arc right; Row 4 NE → arc top-right; Row 5 N → arc above.
>
> RECOVERY (frames 5–6, all rows): Arc pixels fade. Cloak returns to idle width. Hollow returns to idle brightness. Particle dots resume outward drift.
>
> Label rows: "S / SE / E / NE / N". Label frame groups: "STARTUP (1–2) / ACTIVE (3–4) / RECOVERY (5–6)".

---

### Prompt 5 — HURT (1 row × 2 frames = 64×32px, universal)

> True pixel art sprite sheet. 1 row × 2 frames. Each frame 32×32 pixels. Total: 64×32 pixels. Transparent background. Same 8-color palette. Use S-facing (down) silhouette. Applied to all directions in Godot.
>
> Frame 1: Cloak boundary explodes — notation particle dots scatter to extreme frame edges, some at corner pixels. Hollow dims: center shifts from #F0E8D8 to #C0A0F0, surrounding #7B4EA0 halo shrinks by 1px. Form intact but boundary at maximum scatter.
>
> Frame 2: Particles pull back toward form. Boundary still more scattered than idle but restabilising. Hollow still slightly dimmed. Recovery in progress.

---

### Prompt 6 — DYING (1 row × 6 frames = 192×32px, universal)

> True pixel art sprite sheet. 1 row × 6 frames. Each frame 32×32 pixels. Total: 192×32 pixels. Transparent background. Same 8-color palette. Start from S-facing idle pose.
>
> Frame 1: Full warrior at idle.
> Frame 2: 20% of outer cloak pixels become drifting #A080E0 dots. Hollow still lit.
> Frame 3: 40% of outer cloak pixels drifting. Visible gaps in form. Hollow still lit.
> Frame 4: 60% dissolved. Only body core, crown tips, and Hollow remain clearly defined.
> Frame 5: 80% dissolved. Crown (2–3px #2A1448 and #C0A0F0) and Hollow (3–4px #F0E8D8) only. Everything else gone or drifting.
> Frame 6: Hollow dims — #F0E8D8 shifts to #C0A0F0 then #7B4EA0. 2px only. Crown 1–2px #2A1448. Near-empty. The song is gone.

---

### Prompt 7 — SUMMONING (1 row × 6 frames = 192×32px, universal)

> True pixel art sprite sheet. 1 row × 6 frames. Each frame 32×32 pixels. Total: 192×32 pixels. Transparent background. Same 8-color palette. Frame 6 must match IDLE_S frame 1 exactly.
>
> Frame 1: 2–3 scattered #A080E0 dots at frame corners only. Near-empty.
> Frame 2: More particles drifting inward. Faint outline of cloak's widest point — 3–4px #2A1448 at mid-height only.
> Frame 3: Cloak outer edge recognisable but hollow. Crown tips appearing (2px #C0A0F0). No Hollow.
> Frame 4: Cloak fills in. Interior #2A1448 and #7B4EA0 mass forming. Warm bleed beginning at base. Crown fully defined. Hollow position dark — deliberate void.
> Frame 5: Full warrior form visible. Hollow position still dark — the absence is readable and intentional.
> Frame 6: Hollow opens — #F0E8D8 pixels appear at chest center. The wound reopens. Full warrior at S-direction idle. Matches IDLE_S frame 1 exactly.
