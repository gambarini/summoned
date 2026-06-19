extends Node

## THROWAWAY M2 verification: instances the REAL main.tscn and drives the warrior to
## check the mesh integration — facing follows world movement (no moonwalk) and the
## camera-relative Hollow gate updates while idle under camera orbit (advisor #1/#4).
## Windowed (headless can't render 3D). Captures root window to docs/gen/.

func _ready() -> void:
	var ring := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ring="):
			ring = int(a.split("=")[1])
	GameState.current_ring = ring

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	# Freeze enemies so a combat death can't change_scene_to_file and free us.
	await get_tree().create_timer(0.2).timeout
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.set_process(false)

	var sync = main._warrior_sync
	var rig = main._rig
	var warrior = main.get_node("Warrior")

	# Grief -> coherence-tier wiring (main.gd at summon, GDD §03): confirm the warrior was
	# reformed at the tier its grief reserve implies, and dump the full mapping.
	print("wired tier @ grief=", GameState.grief_reserve, " -> warrior.tier=", warrior.tribe_coherence_tier)
	var _g0: int = GameState.grief_reserve
	for g in [10, 6, 3, 0]:
		GameState.grief_reserve = g
		print("  grief=", g, " -> coherence_tier=", GameState.coherence_tier())
	GameState.grief_reserve = _g0

	for _n in range(150):  # cold shader compile headroom
		await get_tree().process_frame

	# 1) Drive TOWARD camera (screen-down): faces camera, Hollow visible.
	sync.raw_input_override = Vector2(0.0, 1.0)
	await _settle(40)
	print("toward: facing=", sync.get_facing(), " hollow=", sync.hollow_shown())
	_capture("res://docs/gen/warrior_integ_toward.png")

	# 2) Drive AWAY from camera (screen-up): faces away (cape), Hollow hidden.
	sync.raw_input_override = Vector2(0.0, -1.0)
	await _settle(40)
	print("away: facing=", sync.get_facing(), " hollow=", sync.hollow_shown())
	_capture("res://docs/gen/warrior_integ_away.png")

	# 3) Idle facing toward camera, then ORBIT 180: the gate must re-derive and hide
	#    the wound even though the warrior never moved (advisor #1).
	sync.raw_input_override = Vector2(0.0, 1.0)
	await _settle(30)
	sync.raw_input_override = Vector2.ZERO  # stop; hold facing
	await _settle(10)
	var before: bool = sync.hollow_shown()
	rig.orbit(180.0)
	await _settle(20)
	print("idle-orbit gate: before=", before, " after=", sync.hollow_shown())
	_capture("res://docs/gen/warrior_integ_orbit.png")

	# 4) Attack: face camera, trigger, capture during ATTACK_ACTIVE (lunge + sword up).
	rig.orbit(-180.0)  # back to the start yaw
	sync.raw_input_override = Vector2(0.0, 1.0)
	await _settle(24)
	sync.raw_input_override = Vector2.ZERO
	await _settle(6)
	warrior._try_attack()
	for _n in range(40):
		await get_tree().process_frame
		if warrior.vfx_state() == "ATTACK_ACTIVE":
			break
	await _settle(2)
	print("attack: state=", warrior.vfx_state())
	_capture("res://docs/gen/warrior_integ_attack.png")

	# 5) Coherence spectrum: the same warrior reformed at high (whole, concept-1) vs
	#    critical (raw, concept-2) tribe coherence — denser notation, a wider Hollow, a
	#    more splayed/tattered cape. Front shows Hollow + notation; back shows the cape.
	for tier in [0, 3]:
		warrior.tribe_coherence_tier = tier
		sync.raw_input_override = Vector2(0.0, 1.0)   # toward camera (Hollow visible)
		await _settle(24)
		sync.raw_input_override = Vector2.ZERO
		await _settle(80)   # let the notation field repopulate to the new density
		print("coherence tier=", tier, " notation_ratio=", "%.2f" % sync.notation_ratio())
		_capture("res://docs/gen/warrior_integ_coh%d_front.png" % tier)
		sync.raw_input_override = Vector2(0.0, -1.0)  # away (cape toward camera)
		await _settle(28)
		sync.raw_input_override = Vector2.ZERO
		await _settle(12)
		_capture("res://docs/gen/warrior_integ_coh%d_back.png" % tier)
	# Extreme: raw coherence AND max momentary stress — the Hollow at its widest. Confirm
	# the wound still reads as a wound on the breastplate, not an engulfing disc.
	warrior.tribe_coherence_tier = 3
	warrior.hollow_stress = 3
	sync.raw_input_override = Vector2(0.0, 1.0)
	await _settle(24)
	sync.raw_input_override = Vector2.ZERO
	await _settle(20)
	print("extreme: tier=3 stress=3")
	_capture("res://docs/gen/warrior_integ_coh3_stress3.png")
	warrior.hollow_stress = 0
	warrior.tribe_coherence_tier = 0   # reset before the summon/death captures

	# 6) Summon-assemble: face camera, re-enter SUMMONING, capture across the 2.5s arc
	#    (rise + assemble from nothing, final pose = idle).
	sync.raw_input_override = Vector2(0.0, 1.0)
	await _settle(20)
	sync.raw_input_override = Vector2.ZERO
	await _settle(6)
	warrior._change_state(warrior.State.SUMMONING)
	for i in range(3):
		await _settle(26)   # ~0.45s, 0.9s, 1.35s into the assemble
		print("summon[", i, "]: state=", warrior.vfx_state(), " form=", sync.form_amount())
		_capture("res://docs/gen/warrior_integ_summon_%d.png" % i)

	# Let the SummoningTimer (2.5s) return him to IDLE before we can damage him
	# (take_damage early-returns during SUMMONING).
	for _n in range(120):
		await get_tree().process_frame
		if warrior.vfx_state() == "IDLE":
			break
	print("post-summon: state=", warrior.vfx_state())

	# 7) Death-collapse: kill him (coherence -> 0 -> DYING) and capture the crumple +
	#    sink + notation disperse across the 2.5s arc. DYING is terminal (no re-summon
	#    after), so this must come last.
	warrior.take_damage(9999)
	for i in range(3):
		await _settle(26)
		print("death[", i, "]: state=", warrior.vfx_state(), " form=", sync.form_amount())
		_capture("res://docs/gen/warrior_integ_death_%d.png" % i)

	get_tree().quit()


func _settle(frames: int) -> void:
	for _n in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("captured ", path)
