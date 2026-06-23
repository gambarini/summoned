# Rendering — Low-Res 3D Isometric Pixel Art

> The recipe for Summoned's look: real 3D geometry, orthographic isometric camera,
> rendered low and palette-snapped so it reads as hand-drawn pixel art.
>
> **Reference implementation:** `scenes/ring1_iso_test.tscn` + `scripts/ring1_iso_test.gd`
> (a walled-off Ring 1 spike — the source of truth for this pipeline). Design intent:
> GDD §16 Art Direction.

---

## The pipeline at a glance

```
3D world (cel-shaded geometry + billboard characters)
   │   rendered by an ORTHOGRAPHIC Camera3D on a rotation pivot
   ▼
_world_viewport  (SubViewport, low internal res e.g. 320×180)
   │   sampled by a TextureRect with the pixel-art post shader
   ▼
_post_viewport   (SubViewport, same res)   ← this is what gets captured
   │   shown via a display TextureRect, scaled up nearest-neighbour
   ▼
window
```

Both SubViewports stay **locked at the internal render resolution**. The display is a
separate, full-rect `TextureRect` (`STRETCH_KEEP_ASPECT_CENTERED`, nearest filter) bound
to the post-viewport's texture. Keeping the render viewports out of any
`SubViewportContainer` is essential (see Gotchas).

---

## Camera

- **Orthographic `Camera3D`** on a `Node3D` pivot. Rotate the *pivot's* Y for camera
  orbit; keep the pitch fixed. Orthographic projection is the single decisive choice —
  it is what makes the scene read as *isometric* rather than "3D from above." Never
  perspective.
- Defaults that match the concept: pivot pitch **~−30°**, free continuous yaw, ortho
  `size` ~20–26 (zoom).
- **Keep the camera near the scene.** Ortho projection is distance-independent (only
  `size` controls zoom), but depth fog is distance-from-camera based — a far-back ortho
  camera makes fog wash the entire frame. Place it ~20 units out, not 50.

## Surfaces — cel shading (`assets/shaders/cel.gdshader`)

`shader_type spatial`. A custom `light()` quantises the directional term into a few hard
steps, so each surface is a **flat authored region with crisp boundaries** instead of a
smooth lighting ramp. Environment ambient provides the flat base value automatically.

- `bands` — number of light steps (2 reads well).
- `light_gain` — how much the directional adds. **Keep it low (~0.3)**: the concept is
  soft and low-contrast (measured dome lit vs. shadow differ only slightly).
- All geometry materials go through this (`_solid_material()` in the spike returns a
  `ShaderMaterial` using this shader, with `albedo` set per color).

This was the key fix for the "smooth gradient / everything blending" problem: posterizing
a *continuous* 3D lighting solution gives contour rings (no dither) or blur (with dither);
cel shading gives flat regions, which is what hand-drawn pixel art actually is.

## Palette post (`assets/shaders/pixel_post.gdshader`)

`shader_type canvas_item`, applied to the TextureRect that samples the world viewport.
Snaps every pixel to a fixed palette (`vec3 palette[16]`). Optional, off by default now:
- `dither_strength` — Bayer 4×4 ordered dither. **0 for crisp flat bands**; a small value
  adds pixel texture but can read as a smooth blend — use sparingly.
- `edge_strength` — Sobel luminance outline. **0** — the all-edges border looked wrong.
  If forms need separating from the background, a *depth-based silhouette-only* outline is
  the concept-correct version, not a luminance Sobel.

## Palette — sample it from the concept art

Don't guess colors. The Ring palette is **measured from that ring's concept art**:

```python
from PIL import Image
img = Image.open('idea/the_pale_reaches_concept_1.png').convert('RGB')
img.crop((0,0,w,int(h*0.74))).quantize(16).convert('RGB')  # drop the legend panel
```

Ring 1 (Pale Reaches) came out a tight, **light, desaturated cool blue-grey** ramp
(`#243041`→`#919ca6`), pale highlight `#cbd2d3`, one warm doorway accent `#c89a5e`. It is
light and low-contrast — not dark, not saturated. Set material albedos to the *measured*
surface values (concept ground `#7c8591`, dome `#667383`, sky/haze `#5a697d`) and verify by
re-sampling the render (`_update_warrior`-style PIL checks) — convert "looks wrong" into a
number.

## Characters — billboards

Camera-facing `Sprite3D` (`billboard = ENABLED`, `texture_filter = NEAREST`,
`shaded = false`) from the existing pixel sheets. The 8-direction sheet selects a facing
from **movement direction relative to camera yaw** (project the move vector onto the
camera's ground right/forward, pick nearest of 8). At this camera distance a billboard is
indistinguishable from a mesh and keeps the hand-drawn character identity. See
`_update_warrior` in the spike.

## Terrain — blockout, not models

CSG primitives / `BoxMesh` instances for plateau, cliffs, domes, arches, stairs, bunting,
grass tufts. At low res + far camera, **silhouette + palette + soft shading is the
concept** — don't model detail that won't survive the downscale. Fill the frame with a
large ground plane (a rotated square reads as a diamond; oversize it so the frame corners
are covered) so terrain reaches every edge instead of showing a void.

## Ground style — flat colour + macro-noise + decals (`ground_style.gd`)

The shared recipe for **walkable ground** in every ring + the villa. One source of truth:
`GroundStyle` (`scripts/ground_style.gd`); each world passes its own ground colour.

**Why.** A tiling pixel-art ground texture (`ground_tile.png`, sampled `filter_nearest`)
reads as fine **"TV static"** at the iso distance — that's *undersampling aliasing* (~3–4
texels per screen pixel, no mipmaps), not a bad texture. Re-authoring or coarsening the
texture only half-helps. Dropping the texture entirely reads cleaner. (Full diagnosis:
`memory ground_texture_spike`; throwaway A/B harness: `scenes/ground_spike.tscn`.)

**The three layers:**

1. **Flat cel base colour.** Walkable surfaces (plateau/plaza/paths) use
   `GroundStyle.ground_mat(rig, tint)` — a `cel_triplanar` material fed a 1×1 white texture
   so `ALBEDO` collapses to the flat `tint`. No grain, no static.
2. **Smooth macro value-drift.** Same material adds a *very low-frequency* world-space noise
   (`macro_noise`/`macro_scale`/`macro_strength` in `cel_triplanar.gdshader`) that modulates
   ground **value** → broad worn-earth mottle. World-sampled, so it doesn't swim under orbit;
   it's value drift so it survives the palette snap. **`macro_scale` must stay low** (~0.015,
   ~65u period) — a higher freq reintroduces visible large-scale repetition, and a *very*
   high FastNoiseLite frequency (≳0.1) degenerates back into fine static.
3. **Scattered flat decals.** `GroundStyle.scatter_decals(parent, rig, half, ground_col)`
   lays alpha-cut sprite quads (`sprite_cel.gdshader`, `billboard=false`) flat on the ground
   — pebbles / gravel / cracks (`assets/textures/detail_*.png`, generated by
   `scripts/gen_ground_detail.py`). Only **hard-structured** detail survives the 16-colour
   snap; the sprites are authored at the Ring 1 grey value and **tinted per ring** to the
   ground hue. They cover the hub (rejecting only the tight `is_central` combat band) and
   thin toward the rim.

**Rules of thumb.**
- **Decals are MultiMesh** (one `MultiMeshInstance3D` per detail texture = one draw call) —
  never one material/node per decal, or draw calls explode on the explore-scale plateau.
- **Flat decals only** for ground detail — a tiny `DECAL_Y` offset (0.52, just above the
  0.5 plateau top) keeps the depth outline from rimming them. Upright (`billboard=true`)
  sprites *do* get rimmed by the outline — reserve them for sparse foliage if at all.
- **Cliffs, sub-plateaus and stone ruins keep their own materials.** Cliffs are vertical, so
  the world-XZ macro sampling would streak down the face; ruins use the coarse masonry
  `stone_pale.png` tiling texture (coarse enough not to alias). Only *flat walkable* ground
  uses the recipe.

---

## t3ssel8r follow-camera + sub-pixel pipeline (live in `iso_rig.gd`)

The rig follows the warrior (pivot tracks his world position; he stays ~centred, the world
scrolls) and renders crawl-free crisp pixels. Ported from the proven spike
(`docs/PIXELART_T3_SPIKE.md`); the integration write-up is `memory pixelart_t3_integration`.

- **Padded render target.** Both render SubViewports are `render_size + 2·PAD` (PAD=3); the
  ortho `size` is scaled by `_padded.y/render_size.y` so `world_per_texel = cam_size /
  render_size.y` is constant. The overscan is headroom for the sub-pixel slide.
- **Texel-snap follow** (`set_follow_target` → `_apply_follow`): decompose the follow target
  onto the camera's screen right/up/forward axes, snap right & up to whole texels (keep
  forward continuous), and replay the snapped-away fraction as the display blit offset.
- **Device-res offset carrier.** The offset can't live in the project's stretched 480×270
  `canvas_items` canvas (pixel-snapped, coarse). So a `_screen_viewport` is built at the
  device framebuffer size; the padded post is blit into it NEAREST at the integer
  `_upscale`, **offset baked in there**, then shown FULL_RECT → it maps 1:1 to device. The
  2D HUD (its own `CanvasLayer`) cannot move with the offset by construction.
- **Depth outline** (`assets/shaders/pixel_outline_t3.gdshader`): a transparent quad child of
  the camera; silhouette + crease from depth only. Faded to 0 during active orbit.
- **`world_to_render(world)`** un-does PAD + the sub-pixel offset so screen→world aim
  (`warrior_sync.aim_dir_from_screen`) stays correct — without it, attack aim skews by ~PAD.
- **Verify windowed** (`--headless` can't render 3D): capture the deterministic
  `get_screen_viewport()`, not the OS window. `use_taa=false`, `msaa_3d=DISABLED` on the
  world viewport or TAA dominates orbit shimmer.

## Gotchas (all learned the hard way)

- **`SubViewportContainer` with `stretch = true` resizes its child SubViewport to the
  window**, silently overriding `SubViewport.size`. Symptom: your low-res render sits in a
  corner with a dark margin, and captures come out at window size. Fix: keep render
  viewports as plain children of root; display via a separate `TextureRect`.
- **`--headless` cannot render 3D** (dummy renderer, no GPU): `SubViewport.get_texture()`
  is blank and `await RenderingServer.frame_post_draw` never fires. Capture frames
  **windowed** instead — the spike runs `... res://scenes/ring1_iso_test.tscn -- --capture`
  and parses `OS.get_cmdline_user_args()`. (See `memory headless_test_workflow`.)
- **Orthographic camera + depth fog** washes the whole frame if the camera is far back —
  fog is distance-from-camera based. Keep the camera close.
- **Edge pixel-shimmer/crawl during *translation*** is solved (see the t3ssel8r section
  below). Crawl during pure camera **orbit** is structural (reprojection — no 2D offset can
  cancel it); the depth outline is faded out while orbiting because it amplifies it.

## Tuning knobs (where the look lives)

| Knob | Where | Effect |
|------|-------|--------|
| `render_size` | `main.gd` / `base.gd` set `_rig.render_size` (**480×270**); default `iso_rig.gd` 320×180 | pixel chunkiness vs. detail. 480 = current game res (sharper ground/ruins; ~2× GPU cost vs 320). Warrior is a mesh (scales fine); enemy/notation sprites are fixed-res |
| camera `size` | `iso_rig.gd` `cam_size` | zoom |
| pivot pitch | `iso_rig.gd` `pivot_pitch` | iso angle (~−30°) |
| `light_gain` / `bands` | `cel.gdshader` / `cel_triplanar.gdshader` | shading contrast / banding |
| `fog_density` | per-world `apply_environment` | aerial haze at distance (keep light) |
| palette | per-world `palette()` | the entire color identity — per ring |
| `MACRO_SCALE` / `MACRO_STRENGTH` | `ground_style.gd` | ground mottle period / depth (keep scale low ~0.015) |
| decal counts / sizes | `ground_style.gd` `scatter_decals` | density + size of stone/crack detail |
