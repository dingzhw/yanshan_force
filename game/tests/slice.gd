extends SceneTree
var game
var checks=0
var failures=0
func _initialize():call_deferred("run")
func verify(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",message)
func frames(n: int):
	for i in n:await physics_frame
func node_for(id: String):
	for n in game.exploration.nodes:
		if n.get_meta("explore_id")==id:return n
	return null
func enter(id: String):
	var node=node_for(id)
	game.player.clear_movement_input();game.player.position=node.position+Vector3(0,0.1,2)
	await frames(3)
	game.interact()
func ray(a: Vector3,b: Vector3):
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1,[game.player.get_rid()]))
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.start_action()
	await frames(3)
	verify(game.VERSION=="0.4.0" and game.words.size()==175,"slice uses the preserved 175-entry word pack")
	for raw in [game.Layout.SPAWN,game.Layout.POEM,game.Layout.MATH,game.Layout.STATIONS[1].at,game.Layout.STATIONS[2].at,game.exit_position,Vector3(-48,0,-100)]:
		var at=game.Layout.on_ground(raw)
		var hit=ray(at+Vector3.UP*5,at-Vector3.UP*2)
		verify(not hit.is_empty(),"continuous terrain collider beneath "+str(raw))
	var batches=game.landscape.find_children("*","MultiMeshInstance3D",true,false)
	verify(batches.size()>=2,"bamboo stems and leaves are instanced instead of thousands of draw nodes")
	var old_id=game.question.id
	await enter("clue")
	verify(game.exploration.busy and game.paused and game.exploration.states.clue,"E opens a reachable English exploration clue and freezes the run")
	var time=game.time_left;var ammo=game.player.ammo
	game.player.shoot();await frames(20)
	verify(is_equal_approx(game.time_left,time) and game.player.ammo==ammo,"reading does not consume timer or permit shooting")
	game.exploration.close()
	await enter("english")
	verify(game.exploration.states.english and game.rules.bag.size()==1 and not node_for("english").visible,"following next to collects the physical supply and removes its collider")
	var bag=game.rules.bag.size()
	game.exploration.open(node_for("english"))
	verify(game.rules.bag.size()==bag,"English discovery cannot be claimed twice")
	await enter("poem")
	verify(game.exploration.busy,"stone tablet is reachable from its branch")
	game.exploration.buttons[1].pressed.emit()
	verify(not game.exploration.states.poem and game.rules.bag.size()==bag,"wrong poem answer gives feedback without a reward")
	game.exploration.buttons[0].pressed.emit()
	verify(game.exploration.states.poem and game.exploration.states.poem_claimed and game.rules.bag.size()==bag+1,"correct poem answer unlocks and rewards the stone compartment")
	game.exploration.choose(0)
	verify(game.rules.bag.size()==bag+1,"repeated solved-puzzle click cannot duplicate loot")
	game.exploration.close()
	verify(game.question.id==old_id and game.rules.score==0 and game.rules.answered==0,"optional learning keeps the pending English question and its accuracy untouched")
	while game.rules.bag.size()<game.rules.capacity():game.rules.add_loot("filled",1)
	var gate_at=game.exploration.gate.global_position+Vector3(1.4,1.1,0)
	verify(not ray(gate_at+Vector3(0,0,3),gate_at-Vector3(0,0,3)).is_empty(),"closed shortcut gate blocks a real world ray")
	await enter("math")
	game.exploration.buttons[0].pressed.emit()
	verify(game.exploration.states.math and not game.exploration.states.math_claimed,"full bag preserves the solved math reward for later")
	await frames(2)
	verify(ray(gate_at+Vector3(0,0,3),gate_at-Vector3(0,0,3)).is_empty(),"solved translation puzzle opens the gate's collision")
	game.exploration.close()
	await enter("math")
	verify(not game.exploration.states.math_claimed and game.exploration.swap_button.visible,"revisiting a full-bag puzzle keeps its unclaimed reward")
	game.exploration.swap_button.pressed.emit()
	verify(game.exploration.states.math_claimed and game.rules.bag.size()==game.rules.capacity(),"full-bag UI swaps one lowest-value item for the pending reward")
	game.exploration.swap_button.pressed.emit()
	verify(game.rules.bag.size()==game.rules.capacity(),"repeated reward swap cannot duplicate an item")
	game.exploration.close()
	verify(game.exploration.completed()==3,"all three optional discoveries complete independently")
	game.player.ammo=1;game.player.reload();await frames(8)
	await enter("poem")
	var reload=game.player.reload_left
	await frames(30)
	verify(is_equal_approx(game.player.reload_left,reload),"puzzle reading freezes an in-progress reload")
	game.exploration.close();await frames(95)
	verify(game.player.ammo==game.rules.magazine(),"closing the puzzle resumes and finishes the same reload")
	for i in 19:
		game.rules.open_question();game.rules.answer(i>=9)
	verify(game.rules.score==100 and not game.rules.crate_ready(1),"low accuracy still unlocks extraction and leaves accuracy crates locked")
	game.player.position=game.exit_position;await frames(3);game.interact()
	verify(game.rules.phase=="extracting","B extraction starts with 100 points independently of puzzle status")
	await frames(190)
	verify(game.rules.phase=="result" and game.rules.profile.warehouse.size()>0,"actual three-second extraction banks the exploration backpack")
	var saved_count=game.rules.profile.warehouse.size();game._end_run(true)
	verify(game.rules.profile.warehouse.size()==saved_count,"repeated extraction settlement cannot duplicate discovery loot")
	game.start_action()
	verify(game.exploration.completed()==0 and not game.exploration.states.clue and node_for("english").visible,"a new run resets route discoveries and restores collectible collision")
	verify(is_instance_valid(game.player.weapon_view) and game.player.weapon_view.get_parent()==game.player.weapon_root,"new deployment binds the new animated rifle instance")
	verify(is_instance_valid(game.player.weapon_view.magazine),"rifle has a separate animated magazine")
	game.player.ammo=1;game.player.reload();await frames(40)
	verify(game.player.weapon_view.magazine.position.y< -0.06,"reload physically withdraws the magazine")
	game._end_run(false);game.rules.profile.owned.append("magazine");game.start_action()
	verify(game.player.ammo==14 and game.player.weapon_view.magazine.scale.y>1.2,"magazine upgrade changes both capacity and visible magazine size")
	game.queue_free();await process_frame;await create_timer(0.2).timeout
	print("SLICE_CHECKS=",checks," FAILURES=",failures);quit(1 if failures else 0)
