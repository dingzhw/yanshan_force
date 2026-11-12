"""One-time, guarded source integration; keeps original encoding/newline style."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[1]
BASE=json.loads((ROOT/'docs/backups/20261107-pre-v040/baseline.json').read_text(encoding='utf-8'))

def edit(rel,transform):
    p=ROOT/rel;raw=p.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=BASE[str(Path(rel))]:raise RuntimeError('Concurrent or already modified file: '+rel)
    style='\r\n' if b'\r\n' in raw else '\n'
    t=raw.decode('utf-8').replace('\r\n','\n');t=transform(t)
    p.write_bytes(t.replace('\n',style).encode('utf-8'))

def main(t):
    t=t.replace('const VERSION = "0.3.1"','const VERSION = "0.4.0"\nconst SliceWorld = preload("res://scripts/slice_world.gd")\nconst WeaponView = preload("res://scripts/weapon.gd")\nconst Exploration = preload("res://scripts/exploration.gd")')
    t=t.replace('var combat_label: Label','var combat_label: Label\nvar exploration\nvar landscape')
    t=t.replace('\t_build_ui()\n\t_refresh_menu()', '\t_build_ui()\n\texploration = Exploration.new()\n\tadd_child(exploration)\n\texploration.setup(self)\n\t_refresh_menu()')
    start=t.index('func _build_world():');end=t.index('func _build_tower(',start)
    t=t[:start]+'''func _build_world():
	landscape = SliceWorld.new()
	add_child(landscape)
	landscape.setup(self)

'''+t[end:]
    start=t.index('func attach_weapon(');end=t.index('func play_sound(',start)
    t=t[:start]+'''func attach_weapon(parent: Node3D):
	var view = WeaponView.new()
	view.game = self
	parent.add_child(view)
	return view

'''+t[end:]
    t=t.replace('N  /  林间训练区','N  /  A → B 山路')
    t=t.replace('词兵行动：35 秒热身 → 林间或怪石区 → 撤离\\n绿色终端旁按 E 开始热身。\\nWASD 移动 · R 换弹 · Esc 暂停','建议游玩 5–8 分钟 · A营地 → B竹林\\n35秒热身，沿路探索、识词与搜集。\\n100分撤离 · 数学/古诗机关可选')
    t=t.replace('热身成绩影响词兵火力。\\n看中文，射击胸牌上对应的英文。\\n实战答对 +10 分，100 分开启撤离。','山脚出发，沿竹林小路前往B补给点。\\n找纸条、解石刻和机关，带回物资。\\n答对+10分，100分撤离；机关可选。')
    t=t.replace('\t\trules.start_run()','\t\trules.start_run()\n\t\texploration.reset()')
    t=t.replace('player.position = Vector3(0,0.15,4.5)','player.position = Layout.on_ground(Layout.SPAWN)+Vector3.UP*0.15')
    t=t.replace('营地 → 林间补给区 → 怪石区 → 山口撤离点','A山脚营地 → 林间前哨 → B竹林补给点')
    t=t.replace('\tcombat.update(delta)','\texploration.update(delta)\n\tcombat.update(delta)')
    t=t.replace('ammo_label.text = "YS-01  /  训练步枪','ammo_label.text = "YS-04  /  训练步枪')
    t=t.replace('\t_update_guide()','\t_update_guide()\n\tif not combat.in_warmup(): guide_label.text += "\\n\\n"+exploration.status_text()')
    t=t.replace('for node in pickup_nodes+crate_nodes+stations:','for node in pickup_nodes+crate_nodes+stations+exploration.nodes:')
    t=t.replace('\t\tif closest_interaction.has_meta("station_id"):', '\t\tif closest_interaction.has_meta("explore_id"):\n\t\t\tinteraction_label.text = "[E] "+closest_interaction.get_meta("prompt")\n\t\telif closest_interaction.has_meta("station_id"):')
    t=t.replace('\tif closest_interaction.has_meta("station_id"):', '\tif closest_interaction.has_meta("explore_id"):\n\t\texploration.open(closest_interaction)\n\t\treturn\n\tif closest_interaction.has_meta("station_id"):')
    t=t.replace('拾取普通补给 · 估值20币','拾取普通补给 · 估值25币').replace('已拾取普通补给 · 估值20币','已拾取普通补给 · 估值25币')
    t=t.replace('山口撤离点','B点撤离圈')
    t=t.replace('\t\t\tclosest_interaction.get_child(closest_interaction.get_child_count()-1).modulate = MINT','\t\t\tclosest_interaction.get_child(closest_interaction.get_child_count()-1).modulate = MINT')
    t=t.replace('\tif event is InputEventKey and event.pressed and not event.echo:\n', '\tif event is InputEventKey and event.pressed and not event.echo:\n\t\tif is_instance_valid(exploration) and exploration.busy and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):\n\t\t\texploration.close()\n\t\t\tget_viewport().set_input_as_handled()\n\t\t\treturn\n')
    marker='\tif wrong_words.size() > 0:\n\t\tmenu_summary.text += '
    t=t.replace(marker,'\tmenu_summary.text += "探索 %d/3 · 用时 %d分%02d秒\\n" % [exploration.completed(),int(exploration.began)/60,int(exploration.began)%60]\n'+marker)
    t=t.replace('Vector2(465,115),19','Vector2(465,115),17')
    return t

def player(t):
    t=t.replace('var held_keys = {}','var held_keys = {}\nvar aiming = false\nvar weapon_view\nconst RELOAD_SECONDS = 1.5')
    t=t.replace('\theld_keys.clear()','\theld_keys.clear()\n\taiming = false')
    t=t.replace('\tgame.attach_weapon(weapon_root)','\tweapon_view = game.attach_weapon(weapon_root)')
    t=t.replace('\t\t\tcamera.fov = 58','\t\t\taiming = true').replace('\t\tcamera.fov = 75','\t\taiming = false')
    t=t.replace('func _physics_process(delta):','func _physics_process(delta):\n\tif game.paused:\n\t\tvelocity = Vector3.ZERO\n\t\treturn')
    t=t.replace('camera.rotation.x = pitch + recoil * 0.08','camera.rotation.x = pitch + recoil * 0.035\n\tcamera.fov = lerpf(camera.fov,58.0 if aiming else 75.0,minf(delta*12,1))')
    t=t.replace('\tweapon_root.position = Vector3(0.38, -0.32 - sin(clampf(reload_left, 0, 1.0) * PI) * 0.28, -0.64 + recoil * 0.14)','\tvar progress = clampf(reload_left/RELOAD_SECONDS,0,1)\n\tvar target_pose = Vector3(0.0,-0.13,-0.55) if aiming else Vector3(0.27,-0.26,-0.60)\n\ttarget_pose.y -= sin(progress*PI)*0.18\n\ttarget_pose.z += recoil*0.07\n\tweapon_root.position = weapon_root.position.lerp(target_pose,minf(delta*14,1))\n\tif is_instance_valid(weapon_view): weapon_view.animate(delta,progress,Vector2(velocity.x,velocity.z).length(),aiming)')
    t=t.replace('position.x = clampf(position.x, -47, 47)','position.x = clampf(position.x, game.Layout.MIN_X+1.5,game.Layout.MAX_X-1.5)')
    t=t.replace('position.z = clampf(position.z, -47, 47)','position.z = clampf(position.z, game.Layout.MIN_Z+1.5,game.Layout.MAX_Z-1.5)')
    t=t.replace('reload_left = 1.1','reload_left = RELOAD_SECONDS')
    t=t.replace('func shoot():','func shoot():\n\tif not active or game.paused: return')
    t=t.replace('\trecoil = 1.0','\trecoil = 1.0\n\tif is_instance_valid(weapon_view): weapon_view.shot()')
    return t

edit('game/scripts/main.gd',main)
edit('game/scripts/player.gd',player)
print('Integrated main and player; preserved original line endings.')
