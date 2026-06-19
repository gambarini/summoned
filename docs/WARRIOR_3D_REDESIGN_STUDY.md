# Warrior — 3D Character Redesign Study

> A design study, not an implementation spec. Goal: decide what the Summoned Warrior
> should *look like* now that the world is low-res 3D isometric, by reconciling the
> source art (the two warrior concept sheets + how the warrior is drawn inside the five
> ring concepts) against the GDD identity and the current billboard.
>
> Sources read for this study:
> - `../idea/the_warrior_concept_1.png`, `../idea/the_warrior_concept_2.png` (character sheets)
> - In-world warrior depictions inside the ring concepts: `the_pale_reaches_concept_1.png`,
>   `the_singing_lands_concept_1.png`, `the_high_canopy_concept_1.png` ("THE SUMMONED WARRIOR"
>   portrait panel), `the_still_heart_concept_1.png`
> - GDD §03 "The Summoned Warrior" (identity) + §18 warrior state machine
> - Current build: `docs/WARRIOR.md`, `assets/sprites/warrior_8dir/*`, `scripts/warrior_sync.gd`,
>   `assets/shaders/warrior_hover_3d.gdshader`

---

## 1. The core problem: three visual languages that disagree

The warrior currently exists in **three incompatible visual registers**. A redesign has to
pick one as the anchor.

| | What it shows | Register | Where it lives |
|---|---|---|---|
| **A — Current billboard** (`warrior_8dir/`) | Broad, muscular, **hooded monk/cultist**; empty black face; all-purple; no weapon; Hollow/ember/notation are *separate nodes*, not in the sprite | Abstract-but-generic | What renders in-game today |
| **B — Concept sheets** (`the_warrior_concept_1/2`) | A **column of purple/magenta flame & woven notation**; crowned; dual energy blades; the Hollow gaping; edges fully dissolving | Fully supernatural / mythic | Pre-production mood |
| **C — In-world ring art** | A **dark armored knight** — closed helm, layered plate, pauldrons, split surcoat; carries a real weapon (sword in Still Heart, glyph-standard/spear in Singing Lands); supernatural identity present only as *accents* | Grounded + haunted | The most polished, most recent, drawn *at the iso angle we ship* |

The key observation: **these are not three different characters — they are three points on one
axis** (how literally the song-being is rendered vs. how much it reads as a person). The GDD
says the warrior is *meant* to slide along exactly that axis (see §3). And critically:

> **Register C (the in-world ring art) is the most resolved and the most legible — and it is
> the only one drawn at our actual isometric camera angle and pixel scale.** It is, in effect,
> the art team already answering "what does he look like in the game." The current billboard
> (A) is the *least* resolved of the three and is the one `WARRIOR.md` itself flags as "revisit
> if the angle reads wrong."

**Recommendation up front:** anchor the redesign on **Register C — the armored knight — and
carry the supernatural identity (B) as the accent layer**, which we have *already built as 3D
nodes/shaders* in Phase 2b. This is both the most faithful-to-the-best-art and the cheapest,
because the hard part (Hollow, notation drift, warm hem, ability rings, mood) already exists as
runtime layers — only the **base form** needs re-authoring.

---

## 2. What every source agrees on (the non-negotiables)

Across all three registers and the GDD text, these elements are constant and define him. A
redesign must keep all of them:

1. **The Hollow** — a void where the chest/heart should be. "Where his center should be, the
   song broke and never healed." Present in every depiction (chest void in Pale Reaches,
   gold seam in High Canopy, cold star in Still Heart). *Already a 3D node* (`WarriorSync` Hollow:
   void disc + ember + inward pull).
2. **Dissolving trailing edge → musical notation.** "His edges uncertain, dissolving into
   something between matter and music… shredded scores woven into what remains of him." The
   Pale Reaches figure literally frays into noteheads on the trailing side. *Already a 3D node*
   (`NotationDrift` → `GPUParticles3D`).
3. **A warm ember the world recolors.** A single warm light at the chest/hem that each ring's
   palette re-tints: amber-burning hem in Singing Lands, vertical **gold** glyph-seam in High
   Canopy, **cold pale-white** star in Still Heart ("he has something left"). *Already a 3D
   layer* (`warrior_hover_3d.gdshader` hem + the Hollow ember).
4. **Dark, faceless, cool-dominant body** with the warm accent as the only heat. Black/indigo
   silhouette; no readable face (empty hood, or closed helm, or pale glowing eye-points).
5. **Voiceless / "leaves behind what shouldn't be heard."** Expressed as the trail of score
   debris that persists in the world (`local_coords=false` on the drift). Keep.

The GDD's one-line identity to hold in mind throughout:
> *"I am not made of flesh. I am what remains of a song that wasn't allowed to end."*

---

## 3. The identity is a *spectrum*, and the two concept sheets are its two ends

The single most useful thing the GDD says for a redesign:

> *"Each re-summoning reforms him from the tribe's current emotional state. A tribe that is
> healing calls back a warrior slightly more whole. A tribe deep in suffering calls back
> something rawer — more powerful in its despair, harder to direct."*

This means the warrior is **not one silhouette** — he is a coherence-driven range. And the two
concept sheets are literally the two ends of that range:

- **`the_warrior_concept_1` (regal, crowned, cooler purple, contained, dual blades)** ≈ the
  **more whole** end — high tribe coherence. Edges hold; form is upright and composed.
- **`the_warrior_concept_2` ("The Summoned Warrior": web-of-light dissolving, the Hollow
  gaping wide, warm magenta, frantic resonance/lament)** ≈ the **raw** end — low/critical
  coherence. Form barely held together; the wound dominates.
- **The in-world ring knight** ≈ the **medium/default** read you see most of the time.

We already model this spectrum in code and just never tie it to the *silhouette*:

- `HOLLOW_STRESS_PARAMS` (radius↑, center-brightness↓, inward-ratio↑, trail↑) — momentary stress.
- `TRIBE_COHERENCE_PARAMS` (scatter-density, **cloak_edge_definition** 1.2→0.5, pulse-speed,
  anim-speed) — set at summon, held all run.

**Redesign principle:** treat the base form as the *medium* knight, and let `cloak_edge_definition`
/ hollow size / notation density push it visually toward concept-1 (whole) or concept-2 (raw).
The accent layers already respond to these params; the base form should be authored so that
"more dissolve" reads as "more concept-2" and "more coherent" reads as "more concept-1."

---

## 4. Element-by-element redesign spec

Anchored on the armored knight (C), keeping the §2 non-negotiables, built to flex along the §3
spectrum.

### Silhouette / anatomy
- **From:** broad hooded monk, no legs, no weapon, blob-bottom.
- **To:** human-proportioned **armored figure on two legs**, narrower waist, a **split
  surcoat/cloak** whose trailing edge frays into notation. Reads as a person at a glance — which
  is what makes the Hollow *wrong* and unsettling (you expect a chest, you get a hole).
- Carries a **weapon at rest**: a long dark blade (Still Heart) is the cleanest default and
  doubles as the Lament source; the glyph-topped staff/standard (Singing Lands) is the
  alternate read. Pick one as canonical (recommend the blade — it grounds the attack).

### Head / face
- **From:** empty black hood opening.
- **To:** **closed helm or deep cowl with two pale glowing eye-points** (clearly present in
  Pale Reaches). The pale eyes are the "still a person in there" hook and the cheapest bit of
  life. No mouth — he is voiceless.

### The Hollow (keep the node, retune for the new chest)
- Sits at the **chest plate center**. Because the body now reads as armored, the void should
  look like it's *punched through the breastplate* — a dark recess with a torn lip, the ember
  sunk inside. The current 3-node build (void disc / ember core / inward pull) already does this;
  only the **vertical position** (`HOLLOW_Y`) and **radius vs. the new torso** need re-measuring.

### Cloak + notation dissolve
- The **trailing half** of the surcoat is where the frizz-to-notation happens (Pale Reaches shows
  it streaming off one side, not radially). Drive direction from velocity so the dissolve trails
  *behind* — `NotationDrift` already does world-space trailing; bias emission to the cloak's back
  edge rather than all around.
- `cloak_edge_definition` (coherence) controls how far up the cloak the dissolve eats: high
  coherence = only the hem frays; critical = half the figure is notation (toward concept-2).

### Warm hem / ember — and the palette problem
- The warm hem (`warrior_hover_3d.gdshader`, amber `#D4803A`) and the Hollow ember are the
  **only heat** on him and the thing each ring recolors. **Known issue from the migration:** the
  shipped cool 16-color palette has *no warm slot*, so under the palette snap the **ember reads
  pink** (snaps to the dissonant signal hue) and the **amber hem snaps near-cloak grey**
  (accepted as-is for now — see `MIGRATION_3D.md`). For the redesign this becomes a real
  decision (see §6): if the warm ember is core identity, the palette needs a reserved warm
  slot; otherwise we lean into "the cool world cools his fire" and author the ember in
  palette-present hues (pale `#F0E8D8` + lavender `#C0A0F0`).
- **Per-ring recolor is a feature, not a bug:** Singing=amber, Canopy=gold, Still Heart=cold
  white. If we keep a warm slot, drive the ember tint from the active ring's palette so the
  world visibly "tunes" his fire each ring — directly on-theme.

### Palette
- Body stays the cool ramp (`#0D0A1E` void → `#2A1448` → `#7B4EA0` → `#C0A0F0`). This already
  matches both the in-world figure and concept-1.
- The **crown spikes** from the current design are *not* in the in-world art — they read as a
  cultist trope. Recommend **dropping the crown** in favor of the helm/cowl, *unless* we
  explicitly reserve it for the concept-1 (most-whole) end of the spectrum as a "becoming regal
  again" payoff.

---

## 5. Production path: billboard re-author vs. true 3D mesh

"Redesign as a 3D char" has two honest readings. Both keep all the §2 accent nodes unchanged.

### Path A — Re-author the billboard sheets (cheapest, lowest risk)
Keep the `Sprite3D` billboard; regenerate the 8-direction sheets to the **armored-knight** read
(helm, plate, split surcoat, weapon, pale eyes, dark void left for the Hollow node). Pixellab,
same 64×64, same palette + helm/blade. The whole node/shader stack (`WarriorSync`, Hollow, drift,
hem) is untouched — it already expects "dark form, Hollow as a hole."
- **Pro:** days not weeks; zero pipeline change; proven.
- **Con:** billboards don't truly rotate — a flat knight at a hard iso angle can read stiff;
  `WARRIOR.md` already flags "billboard reads wrong at iso angle" as the open risk. 8 dirs may
  need to become 16, or a dedicated iso-angle sheet.

### Path B — Low-poly cel-shaded 3D mesh (true "3D char")
Model the warrior as a **low-poly mesh** lit by the existing **`cel.gdshader`** and snapped by
`pixel_post.gdshader` — i.e. he becomes a real 3D object in the same pipeline as the terrain,
not a billboard.
- **Pro:** rotates correctly with the camera (kills the iso-angle problem and the billboard
  crawl); cel + palette-snap make a low-poly mesh read as the *same* hand-pixelled style as the
  world (this is exactly the look the whole migration is built on); the Hollow can be real
  geometry; lighting is free.
- **Con:** biggest scope — rigging, an animation set (idle/move/attack/hurt/die/summon) to
  replace the sheets, and the Hollow/hem/notation accents must re-anchor to mesh bones instead
  of the billboard. It's the "right" long-term answer but it's a project, not a task.
- **Note:** the accents are already 3D nodes, so they port to a mesh more easily than it sounds —
  they just need bone/attachment anchors instead of the billboard's fixed offsets.

### Path C — Hybrid / phased (recommended sequencing)
1. **Now:** Path A re-author to lock the *design* (armored knight) cheaply and see it in-game.
2. **Later, if the flat read disappoints at the iso angle:** promote to Path B for the player
   only (enemies stay billboards — they're tiny tokens with the mood pip and don't need it).

The player is the one character the camera circles and the eye rests on, so he is the single
best (and possibly only) candidate for a true mesh. Everything else in the world earns its
billboard.

---

## 6. Decisions this study surfaces (for you)

> **Locked (2026-06-19):**
> - **Anchor look = the armored knight, read as a *burning song-being*.** Dark layered plate +
>   pauldrons + split/tattered cape + a helm-cowl with two glowing eyes; the supernatural
>   identity carried as bright warm accents (the Hollow chest-wound + a burning cloak hem),
>   glow balanced so the armored *form* reads primary and the fire reads as accent. Validated
>   in-engine over six blockout passes (§8).
> - **Production path = Path B, true low-poly cel-shaded mesh** (rotates correctly in the
>   existing `cel.gdshader` + `pixel_post.gdshader` pipeline; enemies stay billboards).
> - **Palette = reserve one warm slot** so the ember/hem survive the snap and recolor per ring.
>
> Decisions 1–3 below are now settled by the above; 4–6 carry into the mesh build (§9).


1. **Anchor register** — adopt the **armored-knight (C)** as the canonical look? (Study's
   recommendation: yes.) Or keep the abstract being and push it toward concept-1/2 instead?
2. **Weapon** — canonical **blade** (grounds Lament) vs. **glyph-standard/spear** (more ritual,
   less martial)?
3. **Crown** — drop it for the helm/cowl, or reserve it as the "most-whole" spectrum payoff?
4. **Warm slot in the palette** — reserve one 16th-slot warm color so the ember/hem survive the
   snap and can recolor per ring? Or keep "the cool world cools his fire" and re-author the
   ember in cool hues? (This is the one decision that touches the shared palette.)
5. **Production path** — start with **Path A** (billboard re-author) now, Path B (mesh) only if
   the flat read fails? (Study's recommendation: yes, phased.)
6. **Spectrum scope** — author *one* base form and let shaders flex it (cheap), or author
   distinct sheets/forms for high vs. low coherence (concept-1 vs concept-2; expensive, more
   payoff)?

---

## 8. In-engine blockout validation (2026-06-19)

A low-poly **primitive blockout** (`scripts/warrior_blockout.gd` + `scenes/warrior_blockout.tscn`,
throwaway, kept as the preview tool) was rendered through the *real* pipeline — `IsoRig` +
`cel.gdshader` + palette snap — at the warrior's spot, facing the camera, captured windowed at
yaw 45/135 on Ring 1 (pale grey) and Ring 2 (saturated rose). Captures:
`docs/gen/warrior_blockout_ring{1,2}_yaw{45,135}.png`. Six passes converged on the locked look.
Findings the *real mesh build must carry* (this is the value of the blockout):

1. **Silhouette reads at the iso angle on both pale and saturated terrain, both yaws.** A dark
   armored figure (helm + pauldrons + surcoat) is legible against grey *and* rose ground. The
   armored-knight anchor is confirmed at game fidelity, not just on paper.
2. **The Hollow must be a *substantial* chest feature.** At the warrior's ~2.8-unit game height a
   small wound dot vanishes. What read: a layered disc stack — restrained warm **halo** → dark
   **void** → amber **ember** → hot pale **core**. Bright core + small halo = "fire as accent";
   a big halo washes the figure out (the dialed-back final).
3. **Two warm accents carry the identity.** The Hollow *and* a **burning cloak hem** bracket the
   dark form and sell "a song that learned to walk." Both rely on the **reserved warm slot** to
   survive the palette snap (the preview used the palette-present `c89a5e`).
4. **Metal must avoid the signal hues.** A pale blade snapped to **lavender `c0a0f0`** on Ring 2 —
   the *harmonic-enemy* signal hue. The warrior must stay neutral (migration rule), so the mesh's
   blade/metal needs a neutral tone clear of `c0a0f0` (harmonic) and `c4547a` (dissonant), or he
   reads as an enemy. **Constraint for the mesh.**
5. **Pale notation debris washes out on pale Ring 1**, reads on darker/colored rings — atmospheric,
   acceptable; the real `NotationDrift` node already lives with this. If it must always read,
   apply the mood-pip lesson (draw unsnapped to escape the muted palette).
6. **Camera-facing worked** (the blockout faced camera at both yaws by setting `rotation.y = yaw`);
   the real mesh instead **rotates with movement/camera via the rig**, like the billboard does —
   true 3D, so no 8-direction sheet is needed.
7. **Glow balance:** bright wound core, *restrained* halo + underglow → armored form primary,
   fire as accent. This is the locked intensity.

## 9. Next phase — building the real mesh (scope)

- **Mesh:** low-poly — helm-cowl (dark face recess + two glowing eyes), pauldrons, breastplate
  with a **modeled Hollow recess**, split/tattered surcoat, legs, a neutral-metal **sword**.
  Cel-shaded via `cel.gdshader`, palette-snapped, **~2.8–2.9 world units tall** to match the
  billboard scale (`SimSpace` PPU + `BILLBOARD_PIXEL_SIZE` reference).
- **Palette:** add the reserved warm slot to `IsoRig.palette` (drop a near-duplicate grey to stay
  at the `palette[16]` ceiling); drive ember/hem tint from the active ring palette in
  `WarriorSync` so the world recolors his fire per ring (amber → gold → cold-white).
- **Animation set** (replaces the sheets): idle, move, attack startup/active/recovery, hurt,
  dying, summoning (+ echo). Rig + skinned anims, not 8-dir frames.
- **Re-anchor the accent nodes** already built in Phase 2b from billboard offsets to mesh
  bones/attach points: `WarriorSync` Hollow (becomes real recess geometry or a disc at a chest
  bone), `NotationDrift`, the hem shader, ground pulses, hover bob.
- **Coherence spectrum:** drive `cloak_edge_definition` / Hollow size / notation density to flex
  the form whole↔raw (concept-1 ↔ concept-2) per `TRIBE_COHERENCE_PARAMS`.
- **Swap-in:** the mesh replaces the `Sprite3D` billboard inside `WarriorSync` (position/facing
  plumbing stays; the 2D body remains the Option-B source of truth). Enemies stay billboards.
- **Validate:** re-render on a dark and a pale ring (Still Heart vs. Pale Reaches) — legibility
  vs. ground is the recurring trap.

---

## Appendix — per-source observations (raw notes)

- **`the_warrior_concept_1`** — Tall regal flame-being; crowned; two energy blades; voiceless;
  "shredded scores woven into what remains"; cooler purple; details panel: "voiceless yet it
  hurts to listen / the song broke here / he leaves behind what shouldn't be heard."
- **`the_warrior_concept_2` ("The Summoned Warrior")** — Iso web-of-light figure; the Hollow as a
  black hole in the chest; warm magenta/pink; conical robe of woven notation; named detail panels:
  Shredded Score, The Hollow, Resonance (concentric rings), Trail. This sheet *is* the source for
  the Phase-2b effect set.
- **Pale Reaches (outermost ring)** — Clearest in-game-scale read: navy hooded figure, **two pale
  glowing eyes**, layered shoulder armor, **circular Hollow void in chest**, cloak **fraying into
  noteheads on the trailing side**. The de-facto "default" warrior.
- **Singing Lands** — Helmeted knight, layered plate, holding a **tall glyph-standard/spear**,
  **cloak hem burning warm amber/orange** at the bottom edge.
- **High Canopy ("THE SUMMONED WARRIOR" portrait)** — Tall faceless robed knight, **gold
  glyph-script woven down the robe**, vertical **gold ember-seam** at the chest, long dark **sword**
  at the side. Caption: "He belongs here. That is the thing to be afraid of."
- **Still Heart** — Dark armored knight, layered plate + split surcoat, **long sword** lowered, the
  ember rendered as a **cold pale-white star** above the chest ("He has something left"). Best
  evidence that the ember is the one element the world recolors.
- **Current billboard (`warrior_8dir/south.png`)** — Broad hooded monk, empty black face, all
  purple, no weapon, no in-sprite Hollow. The weakest of the three registers and the one to replace.
