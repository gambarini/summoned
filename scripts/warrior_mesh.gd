extends Node3D
class_name WarriorMesh

## The Summoned Warrior as a low-poly, cel-shaded 3D mesh — the redesign locked in
## `docs/WARRIOR_3D_REDESIGN_STUDY.md` (armored knight read as a burning song-being).
## Procedurally built from primitives (the codebase convention; see ring*_world.gd),
## cel-shaded via `IsoRig.solid_material()` + the palette snap, so it reads as the same
## hand-pixelled style as the world and rotates correctly with the camera.
##
## Scope: this builds the **body** only — armour, tattered cape, surcoat + burning hem,
## helm/cowl + glowing eyes, sword, and a dark chest socket for the Hollow. The dynamic
## glowing accents (the stress-gated Hollow ember/pull, notation drift, ground pulses)
## stay owned by `WarriorSync`, which floats them at the chest socket / warrior position.
##
## Front faces local +Z; feet at local y=0. The caller positions + rotates the root
## (face the movement/aim direction in world — true 3D, not camera-facing).

# Chest socket centre + hem level (local units) — exposed so WarriorSync can anchor the
# dynamic Hollow and (later) per-ring hem tint to the same spots the body reserves.
const CHEST_Y := 2.00
const CHEST_Z := 0.22       # socket front face, local +Z
const HEM_Y := 0.71
const TOTAL_HEIGHT := 2.94   # helm crest top; ~matches the billboard's pixel_size scale

# --- Palette (snaps to the active ring palette in the post pass) -------------
const ARMOR_DARK := Color("241a33")   # deep indigo plate -> dark blue-grey
const ARMOR_MID  := Color("4a4560")   # lit plate / pauldrons -> mid
const SURCOAT    := Color("2e2440")   # cloak / surcoat
const VOID_COL   := Color("0d0a1e")   # the chest socket -> darkest
const EMBER_COL  := Color("c89a5e")   # warm hem (palette-present warm; reserved slot in M4)
const EYE_COL    := Color("cbd2d3")   # pale glowing eyes
# Blade: a MID steel grey, deliberately away from the light end — a pale blade snaps to
# the harmonic signal hue c0a0f0 (blockout finding §8.4); the warrior must stay neutral.
const BLADE_COL  := Color("6e7480")

var _rig: IsoRig


## Build the body under this node, using `rig` for cel materials. `hem_tint` is the
## per-ring warm (or cold, on Still Heart) the burning hem snaps to — see WarriorSync.
## Idempotent-ish: call once after adding to the tree (geometry needs no _ready).
func build(rig: IsoRig, hem_tint := EMBER_COL) -> void:
	_rig = rig
	var armor := rig.solid_material(ARMOR_DARK)
	var lit := rig.solid_material(ARMOR_MID)
	var coat := rig.solid_material(SURCOAT)
	var blade := rig.solid_material(BLADE_COL)
	var hem := _unshaded(hem_tint)

	# Tattered cape behind the body — a primary read when walking away from camera,
	# so it's a full cloak panel plus two ragged side tatters, all flared back.
	_box(Vector3(0.56, 1.74, 0.05), Vector3(0.0, 1.04, -0.22), coat, 0.0, 8.0)    # main cloak
	_box(Vector3(0.16, 1.34, 0.04), Vector3(-0.31, 0.95, -0.20), coat, 7.0, 9.0)  # left tatter
	_box(Vector3(0.14, 1.50, 0.04), Vector3(0.31, 1.02, -0.21), coat, -6.0, 7.0)  # right tatter
	# Legs
	_box(Vector3(0.20, 0.95, 0.24), Vector3(-0.16, 0.47, 0.04), armor)
	_box(Vector3(0.20, 0.95, 0.24), Vector3(0.16, 0.47, 0.04), armor)
	# Surcoat skirt (faceted cone) + burning hem band at its base
	_cyl(0.26, 0.50, 1.05, Vector3(0.0, 1.18, 0.0), coat)
	_cyl(0.46, 0.54, 0.22, Vector3(0.0, HEM_Y, 0.0), hem)
	# Torso / breastplate + chest plate + dark Hollow socket
	_box(Vector3(0.60, 0.74, 0.40), Vector3(0.0, 1.98, 0.0), armor)
	_box(Vector3(0.34, 0.48, 0.10), Vector3(0.0, 2.04, 0.20), lit)
	_disc_z(0.30, Vector3(0.0, CHEST_Y, CHEST_Z), _unshaded(VOID_COL))  # the socket
	# Pauldrons (angled, prominent)
	_box(Vector3(0.34, 0.30, 0.42), Vector3(-0.44, 2.22, 0.0), lit, -18.0)
	_box(Vector3(0.34, 0.30, 0.42), Vector3(0.44, 2.22, 0.0), lit, 18.0)
	# Neck + helm/cowl with crest, brow, dark face recess + glowing eyes
	_box(Vector3(0.18, 0.14, 0.18), Vector3(0.0, 2.42, 0.0), armor)
	_box(Vector3(0.40, 0.46, 0.40), Vector3(0.0, 2.70, 0.0), armor)
	_box(Vector3(0.10, 0.16, 0.30), Vector3(0.0, 2.96, -0.02), lit)   # crest fin
	_box(Vector3(0.42, 0.07, 0.06), Vector3(0.0, 2.88, 0.18), lit)    # brow ridge
	_box(Vector3(0.28, 0.30, 0.06), Vector3(0.0, 2.70, 0.20), _unshaded(VOID_COL))  # face recess
	_box(Vector3(0.09, 0.10, 0.04), Vector3(-0.08, 2.72, 0.23), _unshaded(EYE_COL))
	_box(Vector3(0.09, 0.10, 0.04), Vector3(0.08, 2.72, 0.23), _unshaded(EYE_COL))
	# Sword: lowered, resting point-down at the right side
	_box(Vector3(0.10, 1.30, 0.05), Vector3(0.40, 0.78, 0.12), blade)  # blade, tip near feet
	_box(Vector3(0.32, 0.08, 0.10), Vector3(0.40, 1.50, 0.12), lit)    # crossguard
	_box(Vector3(0.07, 0.13, 0.07), Vector3(0.40, 1.60, 0.12), armor)  # grip/pommel
	_box(Vector3(0.16, 0.22, 0.18), Vector3(0.38, 1.44, 0.12), armor)  # gauntlet/hand


# --- Primitive builders ------------------------------------------------------

func _box(size: Vector3, pos: Vector3, mat: Material, roll := 0.0, pitch := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(pitch, 0.0, roll)
	add_child(mi)


func _cyl(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = h
	c.radial_segments = 8  # faceted, reads pixel-chunky
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


# A thin disc facing local +Z (the chest socket) — reads as a hole on the breastplate.
func _disc_z(r: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.04
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = 90.0
	add_child(mi)


# Unshaded bright material (eyes / hem) — pops past the cel banding, still snaps.
func _unshaded(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m
