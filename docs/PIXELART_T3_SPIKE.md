# Spike — Authentic 3D Pixel-Art Rendering (t3ssel8r / David Holland technique)

> **Status:** exploratory spike, **walled off** — own scene/script/shader, not wired
> into the game. Branch `experiment/3d-pixelart-t3ssel8r`.
>
> **Files:** `scenes/pixelart_t3_test.tscn`, `scripts/pixelart_t3_test.gd`,
> `assets/shaders/pixel_outline_t3.gdshader` (+ reuses `cel.gdshader`,
> `pixel_post.gdshader`). Capture evidence: `docs/gen/t3_*.png`.
>
> **Goal:** tackle the edge pixel-shimmer/crawl that the prior look-match spike
> accepted as an "unsolved tax", using the more rigorous t3ssel8r pipeline:
> low-res render → pixel-perfect camera snap → sub-pixel smoothing → depth outlines
> → banded lighting + stable dither. Refs: davidhol.land/articles/3d-pixel-art-rendering,
> Unity-forum t3ssel8r thread.

## Pipeline

```
3D world (cel-shaded geometry + depth-outline overlay quad, ortho iso camera that
          FOLLOWS the warrior)
  → _world_viewport  (SubViewport, PADDED = 320x180 + 3px overscan each side,
                      TAA/MSAA OFF)
  → palette post (pixel_post.gdshader: palette snap + optional Bayer dither)
  → _post_viewport   (PADDED)
  → _display TextureRect, NEAREST x4, position offset by the sub-pixel remainder
  → _screen_viewport (1280x720, the deterministic composited output that is captured)
```

Key geometry: `world_per_texel = ortho_size / render_height`. The viewport is padded
so the final blit can slide by the fractional remainder without revealing a gap. The
composited output is rendered into its own SubViewport (not the OS window) so capture
is deterministic regardless of the project's window/content-scale settings.

## The five techniques — results (all measured, not eyeballed)

Verification = capture a pan in known **0.25-texel/frame** steps along the screen-right
axis, then measure (a) the low-res RT's frame-to-frame change = the *crawl* metric, and
(b) the composited image's apparent shift = the *motion* metric.

| Pipeline | Composited motion | Low-res RT crawl (consec MAD) |
|----------|-------------------|-------------------------------|
| baseline (no snap) *= the IsoRig-equivalent, the comparison the task asked for* | 4px texel jumps **+ crawl** (resid 0.2–0.4) | changes every frame (~0.18) |
| snap                    | 4px texel jumps (clean but choppy)          | **stable** within texel (0.038) |
| **subpixel (headline)** | **smooth 1px/frame** (`[0,1,2,3,4,5]`)      | **stable** within texel (0.038) |

1. **Low-res render** — SubViewport at 320×180, NEAREST upscale. ✓
2. **Pixel-perfect camera snap** — decompose the follow target onto the camera's
   screen-right/up axes, snap each to whole texels, keep depth continuous. Kills the
   crawl: RT MAD 0.18 → 0.038 (≈5× more stable). ✓
3. **Sub-pixel smoothing (headline)** — offset the final blit by `-frac · UPSCALE`
   screen px. Gives **smooth motion of crisp, stable pixels** simultaneously — the
   composited image advances 1px/frame while the RT only changes at texel boundaries.
   Sign was inverted on first try (measured `snap − frac`, fixed to `snap + frac`). ✓
4. **Depth-based outlines** (`pixel_outline_t3.gdshader`) — transparent overlay quad in
   the transparent pass (DEPTH_TEXTURE only, no normal-roughness buffer → renderer-
   portable). Silhouette = foreshorten-corrected depth first-difference (tolerance ÷
   |view-normal.z|, so slanted ground does **not** false-edge); creases = depth
   Laplacian (spikes at slope changes, ~0 on flat/slanted planes). Reads as hand-drawn
   ink on silhouettes + box/dome creases, **no false grid on the ground**. ✓
5. **Banded lighting + stable dither** — `cel.gdshader` (bands=2, light_gain=0.3,
   tunable) gives flat authored regions. Bayer dither is anchored to the low-res RT
   grid → deterministic per screen pixel → **does not crawl** under pan (RT MAD
   unchanged at 0.037 with dither=0.06). Left **off by default** (matches the prior
   look-match finding that it reads as a smooth blend); tunable via `dither=`. ✓

## The honest limitation — orbit is the residual hard case

The sub-pixel trick is a **translation** fix. Captured pure orbit (warrior stationary,
yaw 0.5°/frame), consecutive-frame RT MAD:

| baseline | snap | subpixel | full (+outline) |
|----------|------|----------|-----------------|
| 0.309    | 0.337| 0.337    | **0.605**       |

> The absolute MAD here is *mostly the legitimate rotation* — at 0.5°/frame a mid-screen
> edge (~160px radius) genuinely moves ~1.4px from the orbit itself, so 0.31 is not the
> shimmer-artifact magnitude. The **relative** deltas are the signal: snap≈baseline (no-op)
> and full≫both (outline amplification).

- snap/subpixel ≈ baseline: a pure orbit never translates the follow target, so the
  snap/sub-pixel machinery is a **structural no-op** for rotation. Each frame is
  individually crisp, but successive yaws reproject the scene → silhouettes shift
  sub-texel → crawl persists. The offset trick **cannot** fix this (there is no single
  2D shift that compensates a reprojection).
- The **outline pass ~doubles** measured orbit crawl: high-contrast ink edges flicker
  as the scene reprojects.

This squarely reframes the prior "accepted tax": the technique **fully solves the
motion the game does most (camera follow-pan)** and **free orbit is the irreducible
residual** — a real tension with the project's committed "keep full rotation" choice.
The only lever for orbit crawl is quantizing yaw to discrete steps (choppy tradeoff) —
noted as a design option, not implemented. A cheaper mitigation: fade the outline
strength toward 0 while the camera is actively orbiting.

## If/when wiring into the live game (IsoRig)

- The single display offset only re-centers the **follow target**. Independent movers
  (enemies, arcs) at their own sub-texel world positions will still crawl — each would
  need its own per-sprite sub-texel correction, or accept it (they are billboards, less
  affected than geometry).
- The padded-viewport + sub-pixel-offset blit is the new machinery; the IsoRig camera
  rig and SubViewport chain are otherwise reusable.
- Capture/verify windowed only (`--headless` can't render 3D). The spike captures the
  deterministic `_screen_viewport`, not the OS window.

## Repro

```
# pan (headline):   pipeline ∈ baseline|snap|subpixel|outline|full
godot --path . res://scenes/pixelart_t3_test.tscn -- --capture pipeline=full motion=pan frames=6 step=0.25
# orbit (residual): step = degrees/frame
godot --path . res://scenes/pixelart_t3_test.tscn -- --capture pipeline=full motion=orbit frames=6 step=0.5
# interactive: WASD walk the warrior (camera follows), Q/E orbit
```
