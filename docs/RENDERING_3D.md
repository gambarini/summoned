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

---

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
- **Edge pixel-shimmer/crawl during rotation** is the standard low-res-3D tax. Acceptable
  in the prototype; fix later with camera pixel-snap / sub-pixel smoothing.

## Tuning knobs (where the look lives)

| Knob | Where | Effect |
|------|-------|--------|
| `RENDER_SIZE` | spike script | pixel chunkiness vs. detail (256–480 wide) |
| camera `size` | `_make_camera_rig` | zoom |
| pivot pitch | `_make_camera_rig` | iso angle (~−30°) |
| `light_gain` / `bands` | `cel.gdshader` via `_solid_material` | shading contrast / banding |
| `fog_density` | `_make_environment` | aerial haze at distance (keep light) |
| palette | `PALETTE` const | the entire color identity — per ring |
