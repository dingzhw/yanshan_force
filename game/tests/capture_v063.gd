extends SceneTree
## Captures GPU-rendered 1280x720 screenshots & Standard-Quality (real-time shadows ON) FPS benchmark for v0.6.3:
## 1) 01-menu-v063.png: Camp menu v0.6.3 with unlocked treasures, career Red/Gold extraction stats & Compendium button;
## 2) 02-cipher-magnifying-reveal-mythic-red.png: Tier-3 Cipher Vault mid-Magnifying-Glass Slot-by-Slot Reveal ('旷世·大红' Jackpot + High-Energy Scan);
## 3) 03-open-world-loose-relic-and-bird-nest.png: First-person open-world view of spinning Tier-6 3D relic + crimson beam + Jackpot Toast + Bird Nest;
## 4) 04-3d-relic-inspect-turntable.png: [I] 3D Rotating Relic Showcase Modal inspecting '烟山之心·赤金龙印' (Heart of Yanshan Dragon Seal);
## 5) 05-tactical-backpack-grid.png: [B] 4-column Tactical Backpack & Appraisal Modal with mixed 6-tier loot;
## 6) 06-compendium-bilingual-gallery.png: Camp '🏆 烟山奇珍图鉴' bilingual gallery with Tier-6 Crimson Red & Tier-5 Gold cards.

var game
var frame_samples_ms: Array[float] = []
var sampling_active := false

func _initialize():
	run()

func _process(delta: float) -> bool:
	if sampling_active and delta > 0.0:
		frame_samples_ms.append(delta * 1000.0)
	return false

func wait_render(frames: int = 8):
	await process_frame
	for _i in frames:
		await process_frame
		await physics_frame
	await RenderingServer.frame_post_draw

func aim_player_exact(foot_pos: Vector3, look_target: Vector3, stance_mode: int = 0):
	game.player.clear_movement_input()
	game.player.velocity = Vector3.ZERO
	game.player.reset_stance()
	if stance_mode != 0:
		game.player.set_stance(stance_mode, true)
	game.player.current_eye_y = 1.04 if stance_mode == 1 else 1.58
	game.player.camera.position.y = game.player.current_eye_y
	game.player.position = foot_pos
	var eye_pos: Vector3 = foot_pos + Vector3(0.0, float(game.player.current_eye_y), 0.0)
	var d: Vector3 = look_target - eye_pos
	game.player.yaw = atan2(-d.x, -d.z)
	var flat := maxf(0.05, Vector2(d.x, d.z).length())
	game.player.pitch = clampf(atan2(d.y, flat), -1.25, 1.25)

func ground_foot(x: float, z: float, extra_y: float = 0.06) -> Vector3:
	return Vector3(x, float(game.terrain_height(x, z)) + extra_y, z)

func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await wait_render(10)

	game.landscape.set_low_quality(false)
	await wait_render(6)

	# Seed representative career progress for Camp Menu & Compendium showcase
	game.rules.profile.coins = 3680
	game.rules.profile.runs = 12
	game.rules.profile.extractions = 9
	game.rules.profile.red_extracted = 3
	game.rules.profile.gold_extracted = 6
	game.rules.profile.best_haul = 2480
	game.rules.profile.best_item_title = "烟山之心·赤金龙印"
	game.rules.profile.best_item_value = 1313
	game.rules.profile.collection = [
		"烟山之心·赤金龙印",
		"越窑秘色青瓷盏",
		"烟山千年紫芝王",
		"烟山先民竹简",
		"烟山古铜虎符",
		"量子战术主控核",
		"烟霞岩画残拓",
		"竹海古玉挂坠",
		"军用抗扰电台"
	]

	# 1. Camp Menu v0.6.3 with unlocked Compendium counter & career stats
	game._refresh_menu("烟山基地 v0.6.3 · 真摸金 6 阶大红爆率与双语奇珍图鉴")
	await wait_render(8)
	game._capture("01-menu-v063.png")

	# 6. Camp Bilingual Treasure Compendium ('🏆 烟山奇珍图鉴')
	game.loot_ui.open_compendium()
	await wait_render(8)
	game._capture("06-compendium-bilingual-gallery.png")
	game.loot_ui.close_compendium()
	await wait_render(4)

	# Start Confidential Operation & run Standard-Quality GPU FPS benchmark!
	game.start_action(true, "confidential")
	game.landscape.set_low_quality(false)
	await wait_render(18)

	var bench_views := [
		{"name": "south_valley_vista_with_loot", "foot": ground_foot(6.5, 14.5, 0.12), "look": Vector3(16.5, 1.5, 38.0)},
		{"name": "bamboo_maze_south_gate", "foot": ground_foot(-40.8, -32.4, 0.10), "look": Vector3(-41.6, 8.0, -38.0)},
		{"name": "yanxia_chiseled_petroglyph", "foot": Vector3(-40.85, 6.526, -60.95), "look": Vector3(-44.90, 8.15, -61.15)},
		{"name": "yanxia_inner_sanctum", "foot": Vector3(-41.35, 6.526, -63.15), "look": Vector3(-41.85, 7.65, -67.15)}
	]
	frame_samples_ms.clear()
	var per_view := {}
	for bv in bench_views:
		var foot_v: Vector3 = bv["foot"]
		var look_v: Vector3 = bv["look"]
		var vname: String = str(bv["name"])
		aim_player_exact(foot_v, look_v, 0)
		for _w in 18:
			await process_frame
		var local_ms: Array[float] = []
		sampling_active = true
		var start_idx := frame_samples_ms.size()
		for _s in 75:
			await process_frame
		sampling_active = false
		for k in range(start_idx, frame_samples_ms.size()):
			local_ms.append(frame_samples_ms[k])
		var sum_local := 0.0
		for v in local_ms:
			sum_local += v
		per_view[vname] = snappedf(1000.0 * float(local_ms.size()) / maxf(0.001, sum_local), 0.1)

	var total_ms := 0.0
	for m in frame_samples_ms:
		total_ms += m
	var sorted_ms: Array[float] = frame_samples_ms.duplicate()
	sorted_ms.sort()
	var avg_fps: float = 1000.0 * float(sorted_ms.size()) / maxf(0.001, total_ms)
	var p95_ms: float = sorted_ms[int(float(sorted_ms.size() - 1) * 0.95)] if not sorted_ms.is_empty() else 0.0
	print("STANDARD_FPS_BENCHMARK ", JSON.stringify({
		"gpu": RenderingServer.get_video_adapter_name(),
		"low_quality": game.landscape.low_quality,
		"frames": sorted_ms.size(),
		"average_fps": snappedf(avg_fps, 0.1),
		"p95_frame_ms": snappedf(p95_ms, 0.2),
		"per_view_fps": per_view
	}))

	# Prepare curated 6-tier items for deterministic showcase
	var red_seal := {
		"title": "烟山之心·赤金龙印",
		"en": "Heart of Yanshan Dragon Seal",
		"value": 1313,
		"base_value": 980,
		"rarity": 6,
		"cond": "极品孤本",
		"grid": "2×2",
		"icon": "seal",
		"lore": "烟山深脉秘藏镇山龙印，赤玉镶金，铭刻先民“耕读传家”古篆，万中无一的旷世大红！"
	}
	var red_celadon := {
		"title": "越窑秘色青瓷盏",
		"en": "Yue Secret Celadon Bowl",
		"value": 1004,
		"base_value": 640,
		"rarity": 6,
		"cond": "崭新",
		"grid": "2×2",
		"icon": "celadon",
		"lore": "九秋风露越窑开，夺得千峰翠色来。江南古洞封存千年的秘色莲花盏。"
	}
	var gold_slips := {
		"title": "烟山先民竹简",
		"en": "Yanshan Bamboo Slips",
		"value": 533,
		"base_value": 340,
		"rarity": 5,
		"cond": "崭新",
		"grid": "2×2",
		"icon": "slips",
		"lore": "记录诚庄先民山居岁时与农桑歌谣的古竹简，极具历史研究价值。"
	}
	var gold_core := {
		"title": "量子战术主控核",
		"en": "Quantum Tactical Core",
		"value": 486,
		"base_value": 360,
		"rarity": 5,
		"cond": "标准",
		"grid": "2×2",
		"icon": "quantum",
		"lore": "军规级三防超导主控模块，撤离结算时的硬通货大金。"
	}
	var epic_rubbing := {
		"title": "烟霞岩画残拓",
		"en": "Yanxia Petroglyph Rubbing",
		"value": 236,
		"base_value": 175,
		"rarity": 4,
		"cond": "标准",
		"grid": "2×1",
		"icon": "rubbing",
		"lore": "拓印自烟霞古洞西壁《烟山耕读》先民岩凿石刻的宣纸孤本。"
	}
	var epic_radio := {
		"title": "军用抗扰电台",
		"en": "Tactical Encrypted Radio",
		"value": 257,
		"base_value": 190,
		"rarity": 4,
		"cond": "标准",
		"grid": "2×1",
		"icon": "radio",
		"lore": "双频段跳频野战通讯电台，在群山竹海中依然信号满格。"
	}
	var rare_fan := {
		"title": "紫竹折扇",
		"en": "Purple Bamboo Folding Fan",
		"value": 115,
		"base_value": 85,
		"rarity": 3,
		"cond": "标准",
		"grid": "1×2",
		"icon": "fan",
		"lore": "取烟山向阳紫竹手工打磨的文人折扇，扇骨温润如玉。"
	}
	var uncom_shoot := {
		"title": "烟山春笋干",
		"en": "Dried Bamboo Shoots",
		"value": 65,
		"base_value": 48,
		"rarity": 2,
		"cond": "标准",
		"grid": "1×1",
		"icon": "shoot",
		"lore": "江南山村柴火焙制的鲜嫩春笋干，清香扑鼻。"
	}

	# 2. Tier-3 Cipher Vault mid-Magnifying-Glass Slot-by-Slot Reveal!
	game.wildlife.frozen_for_capture = true
	await create_timer(1.5).timeout
	for _q in 14:
		game.rules.open_question()
		game.rules.answer(true)
	var vault3: Node3D = game.crate_nodes[2]
	game.cipher_terminal.open_for_crate(vault3)
	game.cipher_terminal.unlocked = true
	game.cipher_terminal.perfect_crack = true
	game.cipher_terminal.input_box.editable = false
	game.cipher_terminal.input_box.text = "We have a good time."
	game.cipher_terminal.submit_button.disabled = true
	game.cipher_terminal.close_button.text = "收下返回 [Esc]"
	var showcase_crate_items := [red_seal, red_celadon, gold_slips]
	game.cipher_terminal.displayed_loot = showcase_crate_items
	game.cipher_terminal._render_loot_cards(showcase_crate_items, true)
	# Reveal Slot 0 as Mythic Red Jackpot, put Slot 1 at 68% high-energy crimson scan, keep Slot 2 as [2x2] mystery!
	game.cipher_terminal.set_process(false)
	game.cipher_terminal._reveal_single_slot(0, true)
	game.cipher_terminal.reveal_slots[0].card.scale = Vector2(1.03, 1.03)
	game.cipher_terminal.reveal_cursor = 1
	game.cipher_terminal._apply_card_mystery_style(game.cipher_terminal.reveal_slots[1], true)
	game.cipher_terminal.reveal_slots[1].bar_fill.size.x = float(game.cipher_terminal.reveal_slots[1].bar_max) * 0.68
	game.cipher_terminal.status_label.text = "★ 完美破译全通（机密估值×1.35）— 放大镜正在逐格揭晓高爆率战利品！"
	game.cipher_terminal.status_label.add_theme_color_override("font_color", game.MINT)
	await wait_render(8)
	game._capture("02-cipher-magnifying-reveal-mythic-red.png")
	game.cipher_terminal.set_process(true)
	game.cipher_terminal.close()
	await wait_render(4)

	# 3. Open-World 3D Loose Relic Pedestal + Crimson Beam + HUD Jackpot Toast + Bird Nest in background!
	game.rules.bag.clear()
	game.rules.add_loot_item(red_seal)
	game.rules.add_loot_item(gold_slips)
	game.combat.health = 100
	game.combat.shield = game.rules.max_shield()
	game.feedback_left = 0.0
	game.feedback_panel.hide()
	game.wildlife.visible = false
	# Place glowing Tier-6 '越窑秘色青瓷盏' on Shrine Pedestal cleanly beside Camphor Bird Nest (7.4, -13.6)
	var shrine_ped: Node3D = game.world_loot.loose_nodes[1]
	shrine_ped.position = game.Layout.on_ground(Vector3(9.8, 0.0, -14.0))
	shrine_ped.visible = true
	shrine_ped.set_meta("loot_item", red_celadon)
	var holder: Node3D = shrine_ped.get_node("RelicHolder")
	for ch in holder.get_children():
		ch.queue_free()
	game.world_loot._populate_loose_visual(holder, red_celadon)
	game.cached_interactables.clear()

	var ped_pos: Vector3 = shrine_ped.global_position
	var cam_foot: Vector3 = ground_foot(9.45, -11.55, 0.06)
	aim_player_exact(cam_foot, Vector3(9.10, ped_pos.y + 0.56, -13.95), 0)
	game._update_interaction()
	game.loot_ui.trigger_loot_toast(red_seal, "烟霞古洞秘藏")
	game.screen_flash.color = Color(1.0, 0.26, 0.32, 0.08)
	await wait_render(8)
	game._capture("03-open-world-loose-relic-and-bird-nest.png")
	game.wildlife.visible = true

	# 4. [I] 3D Rotating Relic Showcase Modal ('烟山之心·赤金龙印')
	game.loot_ui.inspect_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game.loot_ui.open_inspect_item(red_seal)
	game.loot_ui.set_process(false)
	game.loot_ui.inspect_turntable.rotation = Vector3(0.10, 0.58, 0.0)
	game.loot_ui.inspect_turntable.position = Vector3.ZERO
	await wait_render(12)
	game._capture("04-3d-relic-inspect-turntable.png")
	game.loot_ui.set_process(true)
	game.loot_ui.close_inspect()
	await wait_render(4)

	# 5. [B] 4-Column Tactical Backpack & Appraisal Modal
	game.rules.bag.clear()
	for it in [red_seal, red_celadon, gold_slips, gold_core, epic_radio, epic_rubbing, rare_fan, uncom_shoot]:
		game.rules.add_loot_item(it)
	game.loot_ui.toggle_backpack()
	await wait_render(8)
	game._capture("05-tactical-backpack-grid.png")
	game.loot_ui.close_backpack()
	await wait_render(4)

	game.queue_free()
	await process_frame
	quit(0)
