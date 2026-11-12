extends Node3D
## Tabasco's CC0 rifle with locally authored view animation and gloved hands.
var game
var rifle: Node3D
var support: Node3D
var flash: MeshInstance3D
var light: OmniLight3D
var magazine: Node3D
var shot_left=0.0
var elapsed=0.0

func _ready():
	rifle=game._model(self,"res://assets/slice/rifle.glb",Vector3.ZERO,0.22,0)
	magazine=rifle.find_child("YS04_magazine",true,false)
	if is_instance_valid(magazine) and "magazine" in game.rules.profile.owned:magazine.scale.y=1.25
	for m in rifle.find_children("*","MeshInstance3D",true,false):
		m.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if "forest_skin" in game.rules.profile.owned:
			var skin=game._material(Color("376c55"));skin.metallic=0.55;skin.roughness=0.48;m.material_override=skin
	var glove=game._material(Color("343b30"));glove.roughness=0.82
	var cloth=game._material(Color("5f6650"))
	support=Node3D.new();add_child(support);support.position=Vector3(-0.03,0.11,-0.18)
	_hand(support,glove,cloth,false)
	var trigger=Node3D.new();trigger.position=Vector3(0.045,0.075,0.13);add_child(trigger)
	_hand(trigger,glove,cloth,true)
	flash=MeshInstance3D.new();var sphere=SphereMesh.new();sphere.radius=0.024;sphere.height=0.10
	flash.mesh=sphere;flash.rotation.x=PI/2;flash.position=Vector3(0,0.08,-0.36)
	flash.material_override=game._material(Color("ffd993"),true);flash.hide();add_child(flash)
	light=OmniLight3D.new();light.position=flash.position;light.omni_range=2.5;light.light_color=Color("ffd6a2");light.light_energy=0;add_child(light)

func _hand(parent,glove,cloth,right: bool):
	var palm=MeshInstance3D.new();var mesh=SphereMesh.new();mesh.radius=0.05;mesh.height=0.11
	palm.mesh=mesh;palm.scale=Vector3(0.75,0.72,1.3);palm.material_override=glove;parent.add_child(palm)
	for i in 4:
		var f=game._mesh_box(parent,Vector3(-0.035+i*0.021,0.018,-0.026),Vector3(0.018,0.04,0.06),Color("30382d"))
		f.rotation.x=-0.3
	var wrist=Vector3(0,-0.015,0.035)
	var elbow=Vector3(0.20 if right else -0.24,-0.30,0.40)
	var sleeve=MeshInstance3D.new();var c=CylinderMesh.new();c.top_radius=0.07;c.bottom_radius=0.04;c.height=wrist.distance_to(elbow);c.radial_segments=10
	sleeve.mesh=c;sleeve.material_override=cloth;sleeve.position=(wrist+elbow)/2
	sleeve.quaternion=Quaternion(Vector3.UP,(elbow-wrist).normalized());parent.add_child(sleeve)

func shot():
	shot_left=0.05

func animate(delta: float,reload_progress: float,moving: float,aimed: bool):
	elapsed+=delta
	shot_left=maxf(0,shot_left-delta)
	flash.visible=shot_left>0
	light.light_energy=1.4 if shot_left>0 else 0.0
	var dip=sin(reload_progress*PI)
	rifle.rotation.z=dip*-0.32
	support.position=Vector3(-0.03,0.11-dip*0.20,-0.18+dip*0.23)
	support.rotation.x=dip*0.75
	if is_instance_valid(magazine):
		magazine.position=Vector3(0,-dip*0.18,dip*0.08)
		magazine.rotation.x=-dip*0.15
	# Small sway remains readable while aiming at a word badge.
	position.x=sin(elapsed*7)*moving*(0.001 if aimed else 0.004)
	position.y=absf(sin(elapsed*7))*moving*0.003
