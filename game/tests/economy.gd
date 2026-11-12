extends SceneTree
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func verify(ok: bool, text: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", text)

func distance_for(owned: Array) -> float:
	game.rules.profile.owned = owned
	game.player.clear_movement_input()
	game.player.position = Vector3(0, 0.1, 4.5)
	game.player.yaw = 0
	for i in 20: await physics_frame
	var start = game.player.position
	game.player.held_keys[KEY_W] = true
	for i in 60: await physics_frame
	game.player.clear_movement_input()
	return start.distance_to(game.player.position)

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_action(false)
	for i in 8:
		game.rules.add_loot("filled", 10, 1)
	var pickup = game.pickup_nodes[0]
	game.player.position = pickup.position + Vector3(0, 0.1, 1)
	await physics_frame
	game.interact()
	verify(game.rules.bag.size() == 8 and pickup.visible, "full bag preserves uncollected pickup")
	game.rules.bag.pop_back()
	game.interact()
	verify(game.rules.bag.size() == 8 and not pickup.visible, "space permits exactly one pickup")
	game.interact()
	verify(game.rules.bag.size() == 8, "repeated pickup cannot duplicate loot")
	game.rules.bag[0] = {"title": "量子词典原型机", "value": 320, "rarity": 5}

	# 16 wrong + 15 right => accuracy 48% (< 70%), score = 2*15 + 13*20 = 290 >= 260
	for i in 31:
		game.rules.open_question()
		game.rules.answer(i >= 16)
	verify(game.rules.score >= game.Rules.EXTRACTION_SCORE and not game.rules.crate_ready(1), "low accuracy preserves independent practice extraction access")
	game.player.position = game.exit_position
	game.interact()
	game.extraction_left = 0.01
	game._process(0.02)
	var banked = game.rules.profile.warehouse.size()
	verify(game.rules.phase == "result" and banked == 8, "extraction path banks loot once")
	verify("量子词典原型机" in game.rules.profile.collection, "legendary extracted item registers in camp trophy collection")
	game._end_run(true)
	verify(game.rules.profile.warehouse.size() == banked, "repeated settlement does not duplicate warehouse")
	game._sell()
	var coins = game.rules.profile.coins
	game._sell()
	verify(coins > 0 and game.rules.profile.coins == coins, "warehouse sale transfers value only once")

	game.rules.profile.coins = 3000
	verify(not game.rules.purchase("magazine2"), "tier-2 drum magazine requires tier-1 magazine first")
	for id in ["red_dot", "magazine", "magazine2", "shield_core", "backpack", "medkit_pack", "forest_skin", "scout", "reward_point"]:
		game._buy(id)
	verify(game.rules.capacity() == 14 and game.rules.magazine() == 20 and game.rules.max_shield() == 60 and game.rules.starter_medkits() == 3, "all nine tactical upgrades apply their gameplay bonuses")
	verify(game.rules.profile.points == 1, "reward coupon increments recorded offline points")

	game.profile_path_override = "user://qa-next-stage-economy.json"
	game._save()
	var restored = load("res://scripts/main.gd").new()
	restored.profile_path_override = game.profile_path_override
	restored._load_profile()
	verify(restored.rules.profile.coins == game.rules.profile.coins and restored.rules.profile.owned == game.rules.profile.owned and restored.rules.profile.collection == game.rules.profile.collection, "restart restores currency, upgrades, mastery and collection")
	restored.free()

	game.start_action(false)
	verify(game.player.ammo == 20 and game.rules.capacity() == 14 and game.player.medkits == 3, "next deployment equips purchased upgrades")
	var visible_skin = false
	for mesh in game.player.weapon_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override != null and mesh.material_override.albedo_color == Color("376c55"):
			visible_skin = true
	verify(visible_skin, "forest skin changes the rendered weapon material")
	var plain = await distance_for([])
	var scout = await distance_for(["scout"])
	verify(scout > plain * 1.09 and scout < plain * 1.15, "scout upgrade increases actual movement by twelve percent")

	game.rules.profile.warehouse = [{"title": "saved", "value": 10, "rarity": 1}]
	var saved_coins = game.rules.profile.coins
	game.rules.add_loot("lost", 20, 2)
	game.time_left = 0.01
	game._process(0.02)
	verify(game.rules.bag.is_empty() and game.rules.profile.warehouse.size() == 1 and game.rules.profile.coins == saved_coins, "timeout clears carried loot and preserves previous progress")
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("ECONOMY_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
