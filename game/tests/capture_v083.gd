extends SceneTree

var game

func _initialize():
	call_deferred("run")

func frames(count: int):
	for _i in count:
		await process_frame
		await physics_frame

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await frames(6)

	# 1) Camp Courtyard: Standing Camp Liaison NPC '陈向导' + Ready golden Ranger Skill HUD ('⚡ 少羽 · [V] 天生神力 · 就绪！')
	game.start_action(true, "normal")
	if is_instance_valid(game.wildlife):
		game.wildlife.frozen_for_capture = true
	game.player.position = game.Layout.on_ground(Vector3(0.4, 0.0, 5.2)) + Vector3(0, 0.14, 0)
	var npc_look: Vector3 = game.rangers.camp_npc_node.global_position + Vector3(0, 1.35, 0)
	var d_npc: Vector3 = npc_look - game.player.camera.global_position
	game.player.yaw = atan2(-d_npc.x, -d_npc.z)
	game.player.pitch = atan2(d_npc.y, Vector2(d_npc.x, d_npc.z).length())
	await frames(6)
	game._capture("v083_camp_liaison_npc.png")

	# 2) Camp Liaison Ranger & Reputation Bounty Modal
	game.rangers.open_npc_modal()
	await frames(4)
	game._capture("v083_bounty_modal.png")
	game.rangers.close_npc_modal()

	# 3) Live Combat: Shaoyu [V] '天生神力' Ground Slam shockwave ring + 2 Mistbound word soldiers knocked flat on ground + cooldown HUD!
	var c0: Vector3 = game.combat.zone_center(0)
	game.player.position = game.Layout.on_ground(c0 + Vector3(0.0, 0.0, 5.2)) + Vector3(0, 0.14, 0)
	game.combat.engage_camp(0)
	var placed := 0
	for s in game.combat.troops[0]:
		if is_instance_valid(s) and not s.defeated:
			var x_off := -1.45 if placed == 0 else (1.55 if placed == 1 else 0.05)
			var z_off := 0.8 if placed < 2 else -0.4
			s.position = game.Layout.on_ground(c0 + Vector3(x_off, 0.0, z_off))
			s.rotation.y = 0.0
			placed += 1
			if placed >= 3:
				break
	var look_c: Vector3 = game.Layout.on_ground(c0 + Vector3(0.0, 0.85, 1.0))
	var d_c: Vector3 = look_c - game.player.camera.global_position
	game.player.yaw = atan2(-d_c.x, -d_c.z)
	game.player.pitch = atan2(d_c.y, Vector2(d_c.x, d_c.z).length())
	await frames(3)
	game.player.use_ranger_skill()
	await frames(8)
	game._capture("v083_shaoyu_v_skill_knockdown.png")

	# 3B) Yanxia Cave Acoustic Warden with protruding glowing cyan chest core, 3D floating HP bar & hit/stagger feedback
	game.combat.disengage_active_camp(false)
	var cw = game.cave_warden
	cw.reset()
	cw.root_node.position = Vector3(-41.60, 6.53, -61.80)
	cw.root_node.rotation.y = 0.0
	game.player.position = Vector3(-41.60, 6.58, -56.40)
	var cw_look: Vector3 = cw.root_node.global_position + Vector3(0.0, 1.55, 0.0)
	var d_cw: Vector3 = cw_look - game.player.camera.global_position
	game.player.yaw = atan2(-d_cw.x, -d_cw.z)
	game.player.pitch = atan2(d_cw.y, Vector2(d_cw.x, d_cw.z).length())
	await frames(3)
	cw.hit_bullet(cw.core_area)
	await frames(3)
	game._capture("v083_cave_warden_weakpoint.png")

	# 4) Compendium -> '👤 人物小记' Character Codex Tab (showing Shaoyu, Chen Guide & unlocked enemy dossiers)
	game.rangers.unlock_card("mistbound_syndicate", false)
	game.rangers.unlock_card("vanguard_boss", false)
	game.rangers.unlock_card("cave_warden", false)
	game._end_run(false)
	await frames(3)
	game.loot_ui.open_compendium("characters")
	await frames(4)
	game._capture("v083_character_codex.png")
	game.loot_ui.close_compendium()

	game.queue_free()
	await process_frame
	print("CAPTURE_V083_DONE")
	quit(0)
