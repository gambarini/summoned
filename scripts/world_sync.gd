extends Node
class_name WorldSync

## Phase 3 hybrid binding for the *dynamic many*: enemies (and, below, transient
## attack arcs). Their 2D `CharacterBody2D` / `Area2D` bodies stay the source of
## truth (Option B); this drives a synced 3D billboard from each, every frame.
##
## Group-scan, not explicit registration: enemies already `add_to_group("enemies")`
## and `queue_free()` on death, so scanning the group lazily makes a billboard for
## each new member and frees billboards whose body has gone invalid — spawn and
## death are handled for free, and Phase 4's `main` needs no per-spawn wiring.
## (The persistent player keeps its own specialised `WarriorSync`; this is only
## for the spawn/despawn crowd.)
##
## Enemies are procedural `Polygon2D` tokens (no sprite sheet yet), so the
## billboard is a camera-facing flat mesh built from the *same* polygon, tinted
## from `_visual.color` each frame — the colour IS the gameplay signal (frequency
## reveal / amplified orange / hit flash), so it must mirror live, not once.
## Deferred juice (same split as Phase 2b): the fleer's explosion ring is a
## separate transient 2D node and won't render here.

const ENEMY_GROUP := "enemies"
const ENEMY_HOVER_Y := 1.0   # mesh centre; sits just above the plateau top (y=0.5)
const ARC_GROUP := "attack_arcs"
const ARC_Y := 0.6           # flat on the plateau top (0.5), a hair above to avoid z-fight

# Mood pip: a tiny vibrant dot above each enemy marking its frequency. The enemy
# token is only ~6 render px and shares hue with same-frequency terrain, so the
# frequency read can vanish into the ground (Ring 2 rose, Ring 3 frost). The pip
# carries the signal as a dot in clear air above the creature.
#
# The dot is drawn as a 2D overlay INSIDE the post-viewport, *after* the palette
# snap (a sibling of the snap TextureRect, so the snap never touches it). That
# gives the pip its own vibrant palette — unsnapped, so genuinely saturated hues
# that no terrain ramp contains, guaranteeing it stands out against any background
# or scenery on every ring at *zero* palette-slot cost. The enemy body is
# unchanged (still its muted signal colour); the pip is a separate marker.
const PIP_DISSONANT := Color("ff2d7e")  # hot magenta — terrain-absent, pops on everything
const PIP_HARMONIC := Color("16e8ff")   # electric cyan — terrain-absent, pops on everything
const PIP_OUTLINE := Color(0.04, 0.04, 0.08, 0.95)  # near-black frame so it pops on light terrain too
const PIP_RISE_Y := 2.0      # world Y to unproject (above the head) for the dot's screen position
const PIP_CORE := 2.0        # render px; the vibrant core (kept tiny)
const PIP_BORDER := 1.0      # render px; dark frame on every side
# Mirror of enemy.gd's NEUTRAL_COLOR / frequency enum. The pip only shows when
# there's a frequency to read, so it hides while the body is the hidden/neutral
# grey and appears on reveal/amplify — otherwise every idle enemy would wear a
# marker, over-tagging creatures meant to read as ambiguous. The phaser (always
# coloured) shows its pip continuously for free; base/fleer gate on reveal.
const NEUTRAL_COLOR := Color(0.533, 0.596, 0.659, 1)
const FREQ_DISSONANT := 0

var _rig: IsoRig
var _enemy_meshes := {}       # CharacterBody2D -> MeshInstance3D
var _arc_meshes := {}         # Node2D (AttackArc) -> MeshInstance3D
var _pip_overlay: Node2D      # unsnapped dot layer in the post-viewport
var _pip_draws: Array = []    # [{pos: Vector2, color: Color}] rebuilt each frame


func setup(rig: IsoRig) -> void:
	_rig = rig
	# A 2D layer on top of the snap TextureRect (added last -> drawn last). Drawing
	# here escapes the palette snap, so the dots keep their vibrant unsnapped hues.
	_pip_overlay = Node2D.new()
	_pip_overlay.name = "PipOverlay"
	_rig.get_post_viewport().add_child(_pip_overlay)
	_pip_overlay.draw.connect(_redraw_pips)


## Live enemy-billboard count (for verification of the spawn/reap bookkeeping).
func enemy_billboard_count() -> int:
	return _enemy_meshes.size()


# Visual sync runs after physics, so it reads bodies' post-move state.
func _process(_delta: float) -> void:
	_sync_enemies()
	_sync_arcs()
	_update_pips()


# --- Enemies -------------------------------------------------------------

func _sync_enemies() -> void:
	# Reap billboards whose body has been freed (death -> queue_free).
	for body in _enemy_meshes.keys():
		if not is_instance_valid(body):
			_enemy_meshes[body].queue_free()
			_enemy_meshes.erase(body)

	for body in get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not _enemy_meshes.has(body):
			var mi := _make_enemy_billboard(body)
			if mi == null:
				continue
			_rig.add_world_child(mi)
			_enemy_meshes[body] = mi
			# The billboard is the enemy now: suppress the 2D Polygon2D so it can't
			# draw over the 3D display (the 2D camera is off, so it would otherwise
			# render at raw sim coords). Physics/Area2D/combat are unaffected.
			(body as Node2D).visible = false
		_update_enemy_billboard(body, _enemy_meshes[body])


func _make_enemy_billboard(body: Node2D) -> MeshInstance3D:
	var visual := body.get_node_or_null("Visual") as Polygon2D
	if visual == null:
		push_warning("WorldSync: enemy %s has no Visual node; skipping billboard" % body.name)
		return null
	var mi := MeshInstance3D.new()
	mi.name = "EnemyBillboard"
	mi.mesh = _polygon_to_vertical_mesh(visual.polygon)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # flash / reveal alpha
	mat.albedo_color = visual.color
	mi.material_override = mat
	return mi


func _update_enemy_billboard(body: Node2D, mi: MeshInstance3D) -> void:
	mi.position = SimSpace.to_world(body.global_position, ENEMY_HOVER_Y)
	var visual := body.get_node_or_null("Visual") as Polygon2D
	if visual:
		mi.material_override.albedo_color = visual.color
		# Death shrink (body.scale) + amplify punch (visual.scale) ride along for
		# free — both tweens run on the hidden 2D nodes.
		var s := body.scale * visual.scale
		mi.scale = Vector3(s.x, s.y, 1.0)


# --- Attack arcs (transient; self-grouped in attack_arc.gd) --------------

func _sync_arcs() -> void:
	for arc in _arc_meshes.keys():
		if not is_instance_valid(arc):
			_arc_meshes[arc].queue_free()
			_arc_meshes.erase(arc)

	for arc in get_tree().get_nodes_in_group(ARC_GROUP):
		# The player's slash is drawn off the sword tip by WarriorSync, not as a flat
		# ground decal — skip those (flagged in warrior.gd:_spawn_attack_arc).
		if arc.has_meta("skip_world_mirror"):
			continue
		if not _arc_meshes.has(arc):
			var mi := _make_arc_billboard(arc)
			if mi == null:
				continue
			_rig.add_world_child(mi)
			_arc_meshes[arc] = mi
			(arc as Node2D).visible = false  # 3D slash replaces the 2D polygons
		_update_arc_billboard(arc, _arc_meshes[arc])


func _make_arc_billboard(arc: Node2D) -> MeshInstance3D:
	var core := arc.get_node_or_null("ArcCore") as Polygon2D
	if core == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "ArcBillboard"
	# Flat on the ground (the slash sweeps the floor in front of the warrior), so
	# the 2D polygon's XY maps to world XZ — direction is preserved (unlike a
	# camera-billboard, which would lose it).
	mi.mesh = _polygon_to_ground_mesh(core.polygon)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = core.color
	mi.material_override = mat
	return mi


func _update_arc_billboard(arc: Node2D, mi: MeshInstance3D) -> void:
	mi.position = SimSpace.to_world(arc.global_position, ARC_Y)
	# 2D rotation about screen-Z -> world rotation about +Y (ground normal). 2D
	# y-down flips the handedness, so negate.
	mi.rotation = Vector3(0.0, -arc.rotation, 0.0)
	var s := arc.scale
	mi.scale = Vector3(s.x, 1.0, s.y)
	var core := arc.get_node_or_null("ArcCore") as Polygon2D
	if core:
		# Mirror the fade: the 2D arc tweens ArcCore's modulate alpha to 0.
		var col: Color = core.color
		col.a = core.modulate.a * arc.modulate.a
		mi.material_override.albedo_color = col


# --- Mood pip (unsnapped overlay) ----------------------------------------

# Rebuild the dot list each frame: for every revealed enemy, unproject a point
# above its head to render-space and queue a vibrant dot there. Hidden bodies
# (neutral grey) contribute nothing — the gate keeps idle enemies un-tagged.
func _update_pips() -> void:
	if _pip_overlay == null:
		return
	_pip_draws.clear()
	var cam := _rig.get_camera()
	for body in _enemy_meshes.keys():
		if not is_instance_valid(body):
			continue
		var visual := body.get_node_or_null("Visual") as Polygon2D
		if visual == null or visual.color.is_equal_approx(NEUTRAL_COLOR):
			continue
		var world := SimSpace.to_world(body.global_position, PIP_RISE_Y)
		if cam.is_position_behind(world):
			continue
		var freq: int = body.frequency if "frequency" in body else FREQ_DISSONANT
		var color := PIP_DISSONANT if freq == FREQ_DISSONANT else PIP_HARMONIC
		_pip_draws.append({"pos": cam.unproject_position(world).round(), "color": color})
	_pip_overlay.queue_redraw()


# Drawn into the post-viewport (render-space px), so coords are pixel-aligned and
# the dots scale up nearest-neighbour with the rest of the display.
func _redraw_pips() -> void:
	for d in _pip_draws:
		var p: Vector2 = d["pos"]
		var b := PIP_CORE + PIP_BORDER * 2.0
		_pip_overlay.draw_rect(Rect2(p.x - b * 0.5, p.y - b * 0.5, b, b), PIP_OUTLINE)
		_pip_overlay.draw_rect(Rect2(p.x - PIP_CORE * 0.5, p.y - PIP_CORE * 0.5, PIP_CORE, PIP_CORE), d["color"])


# --- Polygon -> flat mesh helpers ----------------------------------------

# Upright, in the XY plane (Y up). For a camera-facing billboard (enemies).
func _polygon_to_vertical_mesh(poly: PackedVector2Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	for p in poly:
		# 2D +y is down -> negate so the silhouette stands upright.
		verts.append(Vector3(p.x / SimSpace.PIXELS_PER_UNIT, -p.y / SimSpace.PIXELS_PER_UNIT, 0.0))
	return _triangulated_mesh(poly, verts)


# Flat, in the XZ plane (lying on the ground). For the directional slash (arcs).
func _polygon_to_ground_mesh(poly: PackedVector2Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	for p in poly:
		verts.append(Vector3(p.x / SimSpace.PIXELS_PER_UNIT, 0.0, p.y / SimSpace.PIXELS_PER_UNIT))
	return _triangulated_mesh(poly, verts)


func _triangulated_mesh(poly: PackedVector2Array, verts: PackedVector3Array) -> ArrayMesh:
	var indices := Geometry2D.triangulate_polygon(poly)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if indices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
