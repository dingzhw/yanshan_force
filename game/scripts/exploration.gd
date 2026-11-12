extends Node3D
## Optional learning discoveries. Reading freezes the whole run, never scores English.
var game
var nodes=[]
var states={}
var data={}
var busy=false
var active_id=""
var overlay: Control
var title: Label
var body: Label
var explanation: Label
var source: Label
var buttons=[]
var swap_button: Button
var gate: Node3D
var grace=0.0
var began=0.0

func setup(g):
	game=g
	data=JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration/grade5a.json"))
	_mark("clue",game.Layout.CLUE,"巡护员的纸条",Color("d1c79b"))
	_mark("english",game.Layout.CLUE_LOOT,"路牌旁的封存补给",Color("7c8b5b"))
	_mark("poem",game.Layout.POEM,"山居秋暝 · 石刻",Color("777b68"))
	_mark("math",game.Layout.MATH,"巡护站 · 近道机关",Color("5d6a50"))
	var center=game.Layout.on_ground(Vector3(10,0,-62))
	gate=Node3D.new();gate.position=center+Vector3(-1.4,0,0);add_child(gate)
	for x in [-1.5,1.5]:game._mesh_box(self,center+Vector3(x,0.9,0),Vector3(0.18,1.8,0.18),Color("67563b"),true)
	game._mesh_box(gate,Vector3(1.4,1.1,0),Vector3(2.8,0.18,0.15),Color("776548"),true)
	game._mesh_box(gate,Vector3(1.4,0.55,0),Vector3(2.8,0.15,0.15),Color("776548"),true)
	_ui()
	reset()

func _mark(id: String,at: Vector3,label: String,color: Color):
	var node=Node3D.new();node.position=game.Layout.on_ground(at);node.set_meta("explore_id",id);node.set_meta("prompt",label);add_child(node)
	if id=="poem":
		game._model(node,"res://assets/slice/rock_3.glb",Vector3.ZERO,1.5,0,"convex")
		var carving=game._label3d(node,"山居秋暝\n明月松间照",Vector3(0,0.95,0.78),31,Color("eee9cc"))
		carving.pixel_size=0.0045;carving.billboard=BaseMaterial3D.BILLBOARD_DISABLED
	elif id=="english":
		game._model(node,"res://assets/slice/crate.glb",Vector3.ZERO,0.5,0,"convex")
	else:
		game._mesh_box(node,Vector3(0,0.52,0),Vector3(0.12,1.04,0.13),Color("655940"),true)
		game._mesh_box(node,Vector3(0,1.0,0),Vector3(1.1,0.7,0.12),color,true)
		var paper=game._mesh_box(node,Vector3(0,1.0,0.07),Vector3(0.88,0.5,0.015),Color("d6d3b2"))
		var text=game._label3d(node,"巡护记录\nnext to" if id=="clue" else "近道控制\nE 读操作记录",Vector3(0,1.0,0.09),26,Color("28392b"))
		text.pixel_size=0.0038;text.outline_size=0;text.billboard=BaseMaterial3D.BILLBOARD_DISABLED
	var prompt=game._label3d(node,label+" · E",Vector3(0,1.85,0),28,game.GOLD)
	prompt.visibility_range_end=12
	nodes.append(node)

func _ui():
	overlay=Control.new();overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);game.ui.add_child(overlay)
	var veil=ColorRect.new();veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);veil.color=Color(0.03,0.055,0.035,0.91);overlay.add_child(veil)
	game._panel(overlay,Rect2(240,86,800,550),Color("192c25"))
	title=game._text(overlay,"",Vector2(275,110),Vector2(690,42),29,game.MINT)
	body=game._text(overlay,"",Vector2(275,174),Vector2(730,145),25)
	body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for i in 3:
		buttons.append(game._button(overlay,"",Rect2(275+i*244,337,230,54),choose.bind(i)))
	explanation=game._text(overlay,"",Vector2(275,414),Vector2(730,100),20,game.GOLD)
	explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	source=game._text(overlay,"",Vector2(275,521),Vector2(710,51),13,Color("a7b8a2"));source.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	game._button(overlay,"返回山路  [Esc]",Rect2(790,578,215,37),close)
	swap_button=game._button(overlay,"替换最低值物资",Rect2(550,578,220,37),replace_reward)
	swap_button.hide()
	game._text(overlay,"阅读时暂停计时与战斗",Vector2(275,582),Vector2(260,30),15,game.MINT)
	overlay.hide()

func reset():
	states={"clue":false,"english":false,"math":false,"poem":false,"math_claimed":false,"poem_claimed":false}
	busy=false;active_id="";grace=0;began=0
	if is_instance_valid(overlay):overlay.hide()
	game.Props.set_enabled(gate,true);gate.rotation=Vector3.ZERO
	for n in nodes:game.Props.set_enabled(n,true)

func safe() -> bool:
	return busy or grace>0 or game.player.position.distance_to(game.exit_position)<4.7

func update(delta: float):
	grace=maxf(0,grace-delta)
	if game.rules.phase in ["active","extracting"]:began+=delta

func open(node: Node3D):
	var id: String=node.get_meta("explore_id")
	if id=="english":
		if not states.clue:game._notice("补给有封条，附近巡护员纸条上写着寻找线索。")
		elif states.english:game._notice("这份补给已收集。")
		elif game.rules.add_loot("英文线索补给",40):
			states.english=true;game.Props.set_enabled(node,false);game._notice("找到 next to：在路牌旁！补给已装入背包。",game.MINT)
		else:game._notice("背包已满，补给会留在这里。")
		return
	active_id=id;busy=true;game.paused=true;game.player.active=false;game.player.clear_movement_input();game.hud.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	overlay.show();explanation.text="";source.text="";swap_button.hide();buttons[0].grab_focus()
	if id=="clue":
		states.clue=true;title.text="巡护员留下的纸条"
		body.text="补给藏在路牌旁。\n关键词：next to\n读懂方位，再去山路右侧找一找。"
		source.text="next to 来自当前175条词包。此处探索奖励不计入单词射击正确率。"
		for i in 3:buttons[i].hide()
		explanation.text="可选中文提示：next to = 在……旁边。找到封存补给后按E。"
	else:
		var item=data[id];title.text=item.title;body.text=item.question;source.text=item.source
		for i in 3:
			buttons[i].show();buttons[i].text=item.options[i];buttons[i].disabled=false
		if states[id]:_reward(id)

func choose(index: int):
	if not busy or active_id not in data:return
	var item=data[active_id]
	if index!=int(item.answer):
		explanation.text="再想一想。"+("平移的格数看起点与终点之间的距离。" if active_id=="math" else "想一想诗人眼前的山林、月光与泉水。")
		return
	states[active_id]=true
	if active_id=="math":
		gate.rotation.y=-PI/2
	_reward(active_id)

func _reward(id: String):
	var key=id+"_claimed";var item=data[id]
	swap_button.hide()
	var suffix="这处奖励已领取。"
	if not states[key]:
		if game.rules.add_loot(item.reward_title,int(item.reward_value)):
			states[key]=true;suffix="奖励已装入背包。"
		else:
			suffix="背包已满。可点下方“替换最低值物资”换入奖励，或直接返回。"
			swap_button.show()
	explanation.text=item.explanation+"\n"+suffix
	for b in buttons:b.disabled=true

func replace_reward():
	if not busy or active_id not in data or not states[active_id] or states[active_id+"_claimed"]:return
	if game.rules.bag.is_empty():return
	var lowest=0
	for i in range(1,game.rules.bag.size()):
		if int(game.rules.bag[i].value)<int(game.rules.bag[lowest].value):lowest=i
	var previous=game.rules.bag[lowest]
	game.rules.bag.remove_at(lowest)
	var item=data[active_id]
	if game.rules.add_loot(item.reward_title,int(item.reward_value)):states[active_id+"_claimed"]=true
	else:game.rules.bag.insert(lowest,previous)
	_reward(active_id)

func close():
	if not busy:return
	busy=false;overlay.hide();game.paused=false;game.player.active=true;game.player.clear_movement_input();game.hud.show()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;grace=4.0

func completed() -> int:
	return int(states.get("english",false))+int(states.get("math",false))+int(states.get("poem",false))

func status_text() -> String:
	return "探索 %d/3：英语线索 / 古诗石刻 / 平移机关"%completed()
