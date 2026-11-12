extends Node3D
## A-to-B landscape. Licensed scans are shared; routes remain capsule-clear.
var game
var rng=RandomNumberGenerator.new()
var bark: StandardMaterial3D
var leaf: ShaderMaterial
var rock_paths=[]
var stalk_transforms=[]
var leaf_transforms=[]
var low_quality=false

func setup(g):
	game=g
	rng.seed=20261107
	_lighting()
	_ground()
	_vegetation()
	_camp()
	_landmarks()
	_boundary()

func _lighting():
	var env=WorldEnvironment.new()
	var e=Environment.new()
	var sky=Sky.new()
	var s=ProceduralSkyMaterial.new()
	s.sky_top_color=Color("819ba3");s.sky_horizon_color=Color("d6dccc")
	s.ground_bottom_color=Color("485347");s.ground_horizon_color=Color("c4cbbb")
	sky.sky_material=s;e.background_mode=Environment.BG_SKY;e.sky=sky
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color("d7e0cb");e.ambient_light_energy=0.32
	e.ambient_light_sky_contribution=0.0
	e.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	e.fog_enabled=true;e.fog_density=0.0042;e.fog_light_color=Color("becbb8")
	env.environment=e;add_child(env)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-54,-38,0);sun.light_color=Color("f1eddd");sun.light_energy=0.85
	low_quality="--low-quality" in OS.get_cmdline_user_args()
	sun.shadow_enabled=not low_quality;sun.directional_shadow_max_distance=42
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias=0.06;add_child(sun)

func set_low_quality(value: bool):
	low_quality=value
	for child in get_children():
		if child is DirectionalLight3D:child.shadow_enabled=not low_quality

func _ground():
	var verts=PackedVector3Array();var normals=PackedVector3Array()
	var uvs=PackedVector2Array();var colors=PackedColorArray()
	for z in range(-116,28):
		for x in range(-56,56):
			var p=[Vector3(x,game.terrain_height(x,z),z),Vector3(x,game.terrain_height(x,z+1),z+1),Vector3(x+1,game.terrain_height(x+1,z),z),Vector3(x+1,game.terrain_height(x+1,z+1),z+1)]
			for tri in [[0,2,1],[2,3,1]]:
				var normal=(p[tri[2]]-p[tri[0]]).cross(p[tri[1]]-p[tri[0]]).normalized()
				for i in tri:
					verts.append(p[i]);normals.append(normal);uvs.append(Vector2(p[i].x,p[i].z)*0.28)
					colors.append(Color(clampf(game.Layout.road_distance(p[i].x,p[i].z)/4.5,0,1),0,0))
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var ground=MeshInstance3D.new();ground.name="ContinuousGround";ground.mesh=mesh
	var shader=Shader.new()
	shader.code="""shader_type spatial;
uniform sampler2D soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 pos;
void vertex(){pos=VERTEX;}
void fragment(){
 vec3 tex=texture(soil,UV).rgb;
 float edge=smoothstep(0.38,0.95,COLOR.r);
 float patch=0.5+0.5*sin(pos.x*0.27+sin(pos.z*0.21)*2.0);
 vec3 greenery=mix(vec3(0.29,0.34,0.19),vec3(0.42,0.43,0.27),patch);
 ALBEDO=mix(tex*vec3(0.55,0.49,0.36),tex*greenery*1.4,edge);
 NORMAL_MAP=texture(soil_normal,UV).rgb; NORMAL_MAP_DEPTH=0.5; ROUGHNESS=0.95;
}
"""
	var mat=ShaderMaterial.new();mat.shader=shader
	mat.set_shader_parameter("soil",load("res://assets/slice/ground_color.jpg"))
	mat.set_shader_parameter("soil_normal",load("res://assets/slice/ground_normal.jpg"))
	ground.material_override=mat;add_child(ground)
	var shape=HeightMapShape3D.new();shape.map_width=113;shape.map_depth=145
	var heights=PackedFloat32Array()
	for z in range(-116,29):
		for x in range(-56,57):heights.append(game.terrain_height(x,z))
	shape.map_data=heights
	game.Props.shape_body(self,shape,Vector3(0,0,-44)).name="GroundCollision"

func cylinder(parent,at: Vector3,height: float,radius: float,mat: Material):
	var m=MeshInstance3D.new();var c=CylinderMesh.new()
	c.height=height;c.top_radius=radius*0.84;c.bottom_radius=radius;c.radial_segments=7
	m.mesh=c;m.material_override=mat;m.position=at;parent.add_child(m)
	return m

func bamboo(at: Vector3,height: float):
	var pos=game.Layout.on_ground(at)
	stalk_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1,height,1)),pos+Vector3.UP*height/2))
	var shape=CylinderShape3D.new();shape.radius=0.13;shape.height=height
	var body=game.Props.shape_body(self,shape,pos+Vector3.UP*height/2);body.add_to_group("solid_props")
	for y in [height*0.48,height*0.67,height*0.86]:
		leaf_transforms.append(Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)),pos+Vector3.UP*y))

func _spray_mesh() -> ArrayMesh:
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in 24:
		var angle=rng.randf_range(0,TAU)
		var start=Vector3(sin(angle),0,cos(angle))*rng.randf_range(0.1,0.9)
		var tip=start+Vector3(sin(angle)*0.85,rng.randf_range(-0.3,0.35),cos(angle)*0.85)
		var width=Vector3(cos(angle),0,-sin(angle))*0.09
		for i in [0,1,2,0,2,3]:
			st.set_uv([Vector2(0.5,0),Vector2(0,0.45),Vector2(0.5,1),Vector2(1,0.45)][i])
			st.add_vertex([start,(start+tip)/2-width,tip,(start+tip)/2+width][i])
	st.generate_normals()
	return st.commit()

func _batch(mesh: Mesh,mat: Material,transforms: Array,shadows: bool):
	var node=MultiMeshInstance3D.new();var instances=MultiMesh.new()
	instances.transform_format=MultiMesh.TRANSFORM_3D;instances.mesh=mesh;instances.instance_count=transforms.size()
	for i in transforms.size():instances.set_instance_transform(i,transforms[i])
	node.multimesh=instances;node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _vegetation():
	bark=game._material(Color("5c6842"))
	var shader=Shader.new()
	shader.code="""shader_type spatial; render_mode cull_disabled;
void vertex(){VERTEX.x+=sin(TIME*1.3+NODE_POSITION_WORLD.x*0.7+VERTEX.y)*0.028*UV.y;}
void fragment(){ALBEDO=vec3(0.24,0.34,0.16)*(0.8+UV.y*0.3);ROUGHNESS=0.9;}
"""
	leaf=ShaderMaterial.new();leaf.shader=shader
	for i in 6:
		var path="res://assets/slice/rock_%d.glb"%i
		if ResourceLoader.exists(path):rock_paths.append(path)
	for i in 200:
		var x=rng.randf_range(-49,49);var z=rng.randf_range(-106,17)
		if game.Layout.clear_for_route(x,z,0.4):continue
		for j in 3:bamboo(Vector3(x+j*0.6,0,z+j*0.43),rng.randf_range(6,10))
	var stem=CylinderMesh.new();stem.height=1;stem.top_radius=0.10;stem.bottom_radius=0.12;stem.radial_segments=7
	_batch(stem,bark,stalk_transforms,true)
	_batch(_spray_mesh(),leaf,leaf_transforms,false)
	_trees()
	for i in 30:
		var x=rng.randf_range(-44,44);var z=rng.randf_range(-104,18)
		if not game.Layout.clear_for_route(x,z,1.5):rock(Vector3(x,0,z),rng.randf_range(1.0,3.5),i)
	for info in [[Vector3(-22,0,-18),2.1],[Vector3(-25,0,-35),3.5],[Vector3(5,0,-34),2.9],[Vector3(-3,0,-70),3.6],[Vector3(24,0,-91),4.2]]:rock(info[0],info[1],int(absf(info[0].z)))
	_backdrop()

func _hill_height(x: float,z: float) -> float:
	return 5+15*exp(-pow((x+65)/43,2)-pow((z+175)/45,2))+22*exp(-pow((x-45)/58,2)-pow((z+205)/60,2))+5*sin(x*0.025+z*0.018)

func _backdrop():
	var vertices=PackedVector3Array();var normals=PackedVector3Array()
	for z in range(-260,-116,8):
		for x in range(-184,184,8):
			var points=[Vector3(x,_hill_height(x,z),z),Vector3(x,_hill_height(x,z+8),z+8),Vector3(x+8,_hill_height(x+8,z),z),Vector3(x+8,_hill_height(x+8,z+8),z+8)]
			for i in [0,2,1,2,3,1]:
				var p=points[i]
				vertices.append(p)
				normals.append(Vector3(_hill_height(p.x-0.5,p.z)-_hill_height(p.x+0.5,p.z),1,_hill_height(p.x,p.z-0.5)-_hill_height(p.x,p.z+0.5)).normalized())
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var ridge=MeshInstance3D.new();ridge.mesh=mesh;ridge.material_override=game._material(Color("6f8274"))
	ridge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(ridge)

func _trees():
	var trunk_material=game._material(Color("9a9681"))
	trunk_material.albedo_texture=load("res://assets/slice/tree_bark.jpg")
	trunk_material.uv1_scale=Vector3(1,5,1)
	var shader=Shader.new()
	shader.code="""shader_type spatial; render_mode cull_disabled;
uniform sampler2D needles : source_color,filter_linear_mipmap;
uniform sampler2D mask : filter_linear_mipmap;
void vertex(){VERTEX.x+=sin(TIME+MODEL_MATRIX[3].x+VERTEX.y)*0.035*UV.y;}
void fragment(){ALBEDO=texture(needles,UV).rgb*0.8; ALPHA=texture(mask,UV).r;ALPHA_SCISSOR_THRESHOLD=0.48;ROUGHNESS=0.92;}
"""
	var mat=ShaderMaterial.new();mat.shader=shader
	mat.set_shader_parameter("needles",load("res://assets/slice/tree_needles.jpg"))
	mat.set_shader_parameter("mask",load("res://assets/slice/tree_alpha.jpg"))
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners=[Vector3(-1.5,-1.7,0),Vector3(1.5,-1.7,0),Vector3(1.5,1.7,0),Vector3(-1.5,1.7,0)]
	var uv=[Vector2(0,0.45),Vector2(0.22,0.45),Vector2(0.22,0),Vector2(0,0)]
	for i in [0,2,1,0,3,2]:st.set_uv(uv[i]);st.add_vertex(corners[i])
	st.generate_normals()
	var crowns=[];var trunks=[]
	for raw in [Vector3(-17,0,-4),Vector3(18,0,-8),Vector3(-29,0,-19),Vector3(17,0,-24),Vector3(-37,0,-30),Vector3(24,0,-42),Vector3(-32,0,-53),Vector3(28,0,-63),Vector3(-25,0,-76),Vector3(33,0,-91),Vector3(-7,0,-107),Vector3(40,0,-12)]:
		var at=game.Layout.on_ground(raw);var h=rng.randf_range(9,13)
		trunks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1,h,1)),at+Vector3.UP*h/2))
		var shape=CylinderShape3D.new();shape.radius=0.28;shape.height=h
		game.Props.shape_body(self,shape,at+Vector3.UP*h/2)
		for level in 4:
			var radius=1.8-level*0.36
			for i in 5:
				var angle=TAU*i/5+level*0.7
				var pos=at+Vector3(sin(angle)*radius,h*(0.56+0.085*level),cos(angle)*radius)
				crowns.append(Transform3D(Basis(Vector3.UP,angle).scaled(Vector3(1.3-level*0.17,1.2-level*0.14,1)),pos))
	var cylinder_mesh=CylinderMesh.new();cylinder_mesh.height=1;cylinder_mesh.bottom_radius=0.28;cylinder_mesh.top_radius=0.09;cylinder_mesh.radial_segments=10
	_batch(cylinder_mesh,trunk_material,trunks,true)
	_batch(st.commit(),mat,crowns,true)

func rock(at: Vector3,height: float,index: int):
	var path="res://assets/nature/rock_largeA.glb" if rock_paths.is_empty() else rock_paths[index%rock_paths.size()]
	return game._model(self,path,game.Layout.on_ground(at)-Vector3.UP*0.08,height,rng.randf_range(0,TAU),"convex")

func signpost(at: Vector3,text: String):
	var root=Node3D.new();root.position=game.Layout.on_ground(at);add_child(root)
	game._mesh_box(root,Vector3(0,0.95,0),Vector3(0.14,1.9,0.15),Color("695b42"),true)
	game._mesh_box(root,Vector3(0,1.85,0),Vector3(2.5,0.95,0.14),Color("4f5740"),true)
	var label=game._label3d(root,text,Vector3(0,1.86,0.09),31,Color("e5e4c4"))
	label.billboard=BaseMaterial3D.BILLBOARD_DISABLED;label.pixel_size=0.0068

func shelter(at: Vector3,title: String):
	var root=Node3D.new();root.position=game.Layout.on_ground(at);add_child(root)
	for x in [-2.5,2.5]:
		for z in [-1.8,1.8]:game._mesh_box(root,Vector3(x,1.7,z),Vector3(0.18,3.4,0.18),Color("66583f"),true)
	for z in [-1.5,-0.6,0.3,1.2]:game._mesh_box(root,Vector3(0,3.25,z),Vector3(5.7,0.12,0.85),Color("555c48"),true)
	game._mesh_box(root,Vector3(0,1,-1.35),Vector3(3.5,0.12,0.8),Color("71644b"),true)
	for x in [-1.5,1.5]:game._mesh_box(root,Vector3(x,0.5,-1.35),Vector3(0.15,1,0.6),Color("5a513d"),true)
	var l=game._label3d(root,title,Vector3(0,2.55,1.9),32,Color("e3dcb6"));l.billboard=BaseMaterial3D.BILLBOARD_DISABLED

func _camp():
	game._model(self,"res://assets/survival/tent-canvas.glb",Vector3(10,0,10),3.5,PI*0.75,"trimesh").set_meta("kind","tent")
	game._model(self,"res://assets/survival/barrel.glb",Vector3(7,0,10),1.0,0,"convex")
	game._model(self,"res://assets/survival/box-large.glb",Vector3(7.8,0,11),0.7,0,"convex")
	game._model(self,"res://assets/nature/rock_largeA.glb",Vector3(-6,0,10),0.55,0,"convex").set_meta("kind","low_rock")
	game._build_tower(game.Layout.on_ground(Vector3(-34,0,-102)))
	shelter(Vector3(14,0,-88),"竹林补给棚")
	shelter(Vector3(1,0,-58),"山路巡护站")
	for data in game.Layout.STATIONS:
		var station=game.Challenge.new();game.add_child(station);station.setup(game,data);game.stations.append(station)
	for info in [[Vector3(-9,0,7),"烟山基地\nA · 山脚营地"],[Vector3(-12,0,-17),"竹林补给点  ↑\n石刻支路  ←"],[Vector3(-20,0,-28),"← 古诗石刻\n主路  →"],[Vector3(-14,0,-53),"巡护站  →\n竹林营地  ↑"],[Vector3(14,0,-72),"B · 临时撤离\n100分开启"]]:signpost(info[0],info[1])

func _landmarks():
	game._make_crate("前哨补给箱",1,game.Layout.on_ground(Vector3(-6,0,-39)))
	game._make_crate("竹林精密箱",2,game.Layout.on_ground(Vector3(13,0,-88)))
	if ResourceLoader.exists("res://assets/slice/crate.glb"):
		for crate in game.crate_nodes:
			game.Props.set_enabled(crate.get_child(0),false)
			var label=crate.get_child(1)
			game._model(crate,"res://assets/slice/crate.glb",Vector3.ZERO,0.72,0,"convex")
			crate.move_child(label,crate.get_child_count()-1)
	var pad=MeshInstance3D.new();var ring=TorusMesh.new()
	ring.inner_radius=2.9;ring.outer_radius=3.04;ring.rings=32;ring.ring_segments=8
	pad.mesh=ring;pad.position=game.exit_position+Vector3.UP*0.1;pad.material_override=game._material(game.MINT,true);add_child(pad)
	game._label3d(self,"B · 临时撤离\n100分 · E后停留3秒",game.exit_position+Vector3.UP*2.7,43,game.MINT)
	for at in [Vector3(4,0,7),Vector3(-23,0,-29),Vector3(-4,0,-57),Vector3(16,0,-87)]:
		var pickup=Node3D.new();pickup.position=game.Layout.on_ground(at);pickup.set_meta("value",25);game.add_child(pickup)
		game._model(pickup,"res://assets/survival/box.glb",Vector3.ZERO,0.42,0,"convex")
		game._label3d(pickup,"补给 · E",Vector3(0,0.85,0),27,game.GOLD);game.pickup_nodes.append(pickup)

func _boundary():
	for i in 17:
		rock(Vector3(-52,0,22-i*8),rng.randf_range(3,5),i)
		rock(Vector3(52,0,22-i*8),rng.randf_range(3,5),i+2)
