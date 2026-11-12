extends Node3D
## Tactical YS-04 Carbine viewmodel with Reflex Optic, articulated ripstop sleeves, carbon-knuckle half-finger gloves, wrist watch & live mag-grab reload.

const TacticalProps = preload("res://scripts/tactical_props.gd")

var game
var rifle: Node3D
var optic_root: Node3D
var reticle_dot: MeshInstance3D
var support_grip: Node3D
var right_arm_rig: Node3D
var trigger_finger: Node3D
var left_hand_pivot: Node3D
var left_wrist_marker: Node3D
var left_sleeve: MeshInstance3D
var flash: MeshInstance3D
var light: OmniLight3D
var magazine: Node3D
var shot_left = 0.0
var elapsed = 0.0

var sleeve_mat: StandardMaterial3D
var cuff_mat: StandardMaterial3D
var glove_mat: StandardMaterial3D
var knuckle_mat: StandardMaterial3D
var skin_mat: StandardMaterial3D

func _ready():
	var has_skin = "forest_skin" in game.rules.profile.owned
	_init_arm_materials(has_skin)

	rifle = game._model(self, "res://assets/slice/rifle.glb", Vector3.ZERO, 0.22, 0)
	magazine = rifle.find_child("YS04_magazine", true, false)
	var has_mag2 = "magazine2" in game.rules.profile.owned
	var has_mag1 = "magazine" in game.rules.profile.owned
	if is_instance_valid(magazine):
		if has_mag2:
			magazine.scale = Vector3(1.18, 1.42, 1.15)
		elif has_mag1:
			magazine.scale.y = 1.25

	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color("376c55") if has_skin else Color("2b3136")
	body_mat.metallic = 0.62 if has_skin else 0.55
	body_mat.roughness = 0.38 if has_skin else 0.44

	var mag_mat = StandardMaterial3D.new()
	mag_mat.albedo_color = Color("234538") if has_skin else Color("3b423c")
	mag_mat.metallic = 0.35
	mag_mat.roughness = 0.62

	for m in rifle.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if is_instance_valid(magazine) and (m == magazine or magazine.is_ancestor_of(m)):
			m.material_override = mag_mat
		else:
			m.material_override = body_mat

	# Integrated under-barrel angled tactical handstop
	support_grip = Node3D.new()
	support_grip.position = Vector3(0.0, 0.126, -0.148)
	rifle.add_child(support_grip)
	var cradle = _box_part(support_grip, Vector3.ZERO, Vector3(0.030, 0.022, 0.088), cuff_mat)
	cradle.rotation.x = 0.06

	_build_reflex_optic()
	_build_right_firing_arm()
	_build_left_support_arm()

	# Muzzle flash aligned precisely with YS-04 barrel centerline (y = 0.158)
	flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.026
	sphere.height = 0.12
	flash.mesh = sphere
	flash.rotation.x = PI / 2
	flash.position = Vector3(0, 0.158, -0.37)
	flash.material_override = game._material(Color("ffe29a"), true)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.hide()
	add_child(flash)

	light = OmniLight3D.new()
	light.position = flash.position
	light.omni_range = 3.2
	light.light_color = Color("ffd699")
	light.light_energy = 0.0
	add_child(light)

func _init_arm_materials(has_skin: bool):
	sleeve_mat = StandardMaterial3D.new()
	sleeve_mat.albedo_texture = TacticalProps.ripstop_texture(has_skin)
	sleeve_mat.uv1_scale = Vector3(2.2, 3.0, 1.0)
	sleeve_mat.roughness = 0.88
	sleeve_mat.metallic = 0.04

	cuff_mat = StandardMaterial3D.new()
	cuff_mat.albedo_color = Color("1b2224")
	cuff_mat.roughness = 0.72
	cuff_mat.metallic = 0.18

	glove_mat = StandardMaterial3D.new()
	glove_mat.albedo_color = Color("22282b")
	glove_mat.roughness = 0.66
	glove_mat.metallic = 0.15

	knuckle_mat = StandardMaterial3D.new()
	knuckle_mat.albedo_color = Color("2b483d") if has_skin else Color("30383e")
	knuckle_mat.metallic = 0.52
	knuckle_mat.roughness = 0.34

	skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color("d8ab88")
	skin_mat.roughness = 0.78
	skin_mat.metallic = 0.0

func _box_part(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	m.mesh = b
	m.position = pos
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m

func _limb_segment(parent: Node3D, a: Vector3, b: Vector3, r_a: float, r_b: float, mat: Material, segs := 12) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var length := maxf(0.005, a.distance_to(b))
	cyl.top_radius = r_a
	cyl.bottom_radius = r_b
	cyl.height = length
	cyl.radial_segments = segs
	m.mesh = cyl
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	_orient_cylinder(m, a, b)
	return m

func _orient_cylinder(m: MeshInstance3D, a: Vector3, b: Vector3):
	var diff := a - b
	var length := maxf(0.005, diff.length())
	if m.mesh is CylinderMesh:
		(m.mesh as CylinderMesh).height = length
	var y_axis := diff / length
	var ref := Vector3.FORWARD if absf(y_axis.dot(Vector3.UP)) > 0.94 else Vector3.UP
	var x_axis := ref.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	m.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (a + b) * 0.5)

func _build_right_firing_arm():
	# Attached to rifle so grip hand moves 1:1 with recoil & reload tilt
	right_arm_rig = Node3D.new()
	rifle.add_child(right_arm_rig)

	var wrist := Vector3(0.024, 0.076, 0.168)
	var elbow := Vector3(0.172, -0.092, 0.445)
	_limb_segment(right_arm_rig, wrist, elbow, 0.031, 0.049, sleeve_mat, 14)
	_limb_segment(right_arm_rig, Vector3(0.019, 0.082, 0.154), wrist + Vector3(0.006, -0.006, 0.014), 0.029, 0.032, cuff_mat, 12)

	# Gloved right palm & carbon knuckle guard wrapping pistol grip
	var palm = _box_part(right_arm_rig, Vector3(0.016, 0.084, 0.136), Vector3(0.022, 0.054, 0.042), glove_mat)
	palm.rotation = Vector3(-0.22, 0.08, 0.12)
	var knuckle = _box_part(right_arm_rig, Vector3(0.027, 0.090, 0.134), Vector3(0.007, 0.044, 0.032), knuckle_mat)
	knuckle.rotation = palm.rotation

	# Articulated index trigger finger
	trigger_finger = Node3D.new()
	trigger_finger.position = Vector3(0.019, 0.109, 0.118)
	right_arm_rig.add_child(trigger_finger)
	_limb_segment(trigger_finger, Vector3.ZERO, Vector3(-0.004, 0.005, -0.022), 0.0065, 0.0060, glove_mat, 8)
	_limb_segment(trigger_finger, Vector3(-0.004, 0.005, -0.022), Vector3(-0.013, 0.004, -0.032), 0.0056, 0.0048, skin_mat, 8)

	# Three curled fingers wrapping front of pistol grip
	for idx in 3:
		var fy := 0.094 - float(idx) * 0.015
		var fz := 0.116 + float(idx) * 0.004
		_limb_segment(right_arm_rig, Vector3(0.018, fy, fz + 0.012), Vector3(0.002, fy, fz - 0.005), 0.0068, 0.0062, glove_mat, 8)
		_limb_segment(right_arm_rig, Vector3(0.002, fy, fz - 0.005), Vector3(-0.013, fy + 0.002, fz + 0.004), 0.0058, 0.0050, skin_mat, 8)

	# Right thumb wrapping upper-left grip web
	_limb_segment(right_arm_rig, Vector3(0.012, 0.112, 0.150), Vector3(-0.008, 0.118, 0.136), 0.0078, 0.0068, glove_mat, 8)
	_limb_segment(right_arm_rig, Vector3(-0.008, 0.118, 0.136), Vector3(-0.016, 0.114, 0.122), 0.0064, 0.0054, skin_mat, 8)

func _build_left_support_arm():
	# Dynamic left support hand: grips forend in fire/ADS, reaches down to swap magazine during reload
	left_hand_pivot = Node3D.new()
	left_hand_pivot.position = Vector3(-0.008, 0.122, -0.148)
	add_child(left_hand_pivot)

	var palm = _box_part(left_hand_pivot, Vector3(-0.012, -0.004, 0.006), Vector3(0.024, 0.032, 0.052), glove_mat)
	palm.rotation = Vector3(0.10, -0.14, -0.45)
	var knuckle = _box_part(left_hand_pivot, Vector3(-0.022, -0.010, 0.008), Vector3(0.008, 0.026, 0.042), knuckle_mat)
	knuckle.rotation = palm.rotation

	# Four fingers curling under foregrip onto lower-right rail
	for idx in 4:
		var fz := -0.018 + float(idx) * 0.013
		_limb_segment(left_hand_pivot, Vector3(-0.006, -0.014, fz), Vector3(0.016, -0.006, fz), 0.0065, 0.0060, glove_mat, 8)
		_limb_segment(left_hand_pivot, Vector3(0.016, -0.006, fz), Vector3(0.022, 0.012, fz), 0.0056, 0.0048, skin_mat, 8)

	# Left thumb resting forward along left handguard cheek (stays well below top optic sightline)
	_limb_segment(left_hand_pivot, Vector3(-0.018, 0.010, 0.016), Vector3(-0.022, 0.024, -0.010), 0.0076, 0.0066, glove_mat, 8)
	_limb_segment(left_hand_pivot, Vector3(-0.022, 0.024, -0.010), Vector3(-0.021, 0.029, -0.030), 0.0062, 0.0052, skin_mat, 8)

	# Cuff + Tactical left-wrist telemetry watch
	left_wrist_marker = Node3D.new()
	left_wrist_marker.position = Vector3(-0.024, -0.016, 0.046)
	left_hand_pivot.add_child(left_wrist_marker)
	_limb_segment(left_hand_pivot, Vector3(-0.016, -0.008, 0.026), left_wrist_marker.position + Vector3(-0.006, -0.005, 0.012), 0.028, 0.031, cuff_mat, 12)

	var watch_case = _box_part(left_hand_pivot, Vector3(-0.020, 0.010, 0.036), Vector3(0.024, 0.009, 0.020), knuckle_mat)
	watch_case.rotation = Vector3(0.18, -0.15, -0.42)
	var watch_screen = _box_part(left_hand_pivot, Vector3(-0.018, 0.014, 0.036), Vector3(0.017, 0.003, 0.013), game._material(Color("6ef2c8"), true))
	watch_screen.rotation = watch_case.rotation

	left_sleeve = _limb_segment(self, left_hand_pivot.position + left_wrist_marker.position, Vector3(-0.47, -0.085, 0.38), 0.030, 0.048, sleeve_mat, 14)

func _build_reflex_optic():
	optic_root = Node3D.new()
	optic_root.position = Vector3(0.0, 0.212, 0.03)
	add_child(optic_root)

	var upgraded = "red_dot" in game.rules.profile.owned
	var frame_color = Color("233833") if upgraded else Color("1e2428")
	var frame_mat = StandardMaterial3D.new()
	frame_mat.albedo_color = frame_color
	frame_mat.metallic = 0.65
	frame_mat.roughness = 0.35

	var base = game._mesh_box(optic_root, Vector3(0, 0.0, 0), Vector3(0.036, 0.012, 0.075), frame_color)
	base.material_override = frame_mat
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side_x in [-0.019, 0.019]:
		var wall = game._mesh_box(optic_root, Vector3(side_x, 0.022, 0), Vector3(0.004, 0.034, 0.056), frame_color)
		wall.material_override = frame_mat
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top_hood = game._mesh_box(optic_root, Vector3(0, 0.039, 0), Vector3(0.042, 0.004, 0.056), frame_color)
	top_hood.material_override = frame_mat
	top_hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var glass = MeshInstance3D.new()
	var quad = BoxMesh.new()
	quad.size = Vector3(0.034, 0.030, 0.002)
	glass.mesh = quad
	glass.position = Vector3(0, 0.022, -0.01)
	var glass_mat = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.35, 0.88, 0.82, 0.11)
	glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.material_override = glass_mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	optic_root.add_child(glass)

	reticle_dot = MeshInstance3D.new()
	var dot_mesh = SphereMesh.new()
	dot_mesh.radius = 0.0024 if upgraded else 0.0030
	dot_mesh.height = dot_mesh.radius * 2.0
	reticle_dot.mesh = dot_mesh
	reticle_dot.position = Vector3(0, 0.022, -0.011)
	reticle_dot.material_override = game._material(Color("5cffd6") if upgraded else Color("ff5964"), true)
	reticle_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	optic_root.add_child(reticle_dot)

func shot():
	shot_left = 0.055

func animate(delta: float, reload_progress: float, moving: float, aimed: bool):
	elapsed += delta
	shot_left = maxf(0, shot_left - delta)
	flash.visible = shot_left > 0
	light.light_energy = 1.6 if shot_left > 0 else 0.0
	if is_instance_valid(trigger_finger):
		trigger_finger.rotation.x = 0.18 if shot_left > 0 else 0.0

	var dip = sin(reload_progress * PI)
	rifle.rotation.z = dip * -0.30
	optic_root.rotation.z = rifle.rotation.z
	if is_instance_valid(magazine):
		magazine.position = Vector3(0, -dip * 0.18, dip * 0.08)
		magazine.rotation.x = -dip * 0.15

	# Left hand grips handguard normally, and smoothly drops to grip & swap magazine during reload
	if is_instance_valid(left_hand_pivot) and is_instance_valid(left_sleeve):
		var grip_pose := Vector3(-0.008, 0.122, -0.148)
		var mag_pose := Vector3(-0.008, 0.055 - dip * 0.145, -0.006 + dip * 0.065)
		var blend := smoothstep(0.02, 0.25, dip)
		left_hand_pivot.position = grip_pose.lerp(mag_pose, blend)
		left_hand_pivot.rotation = Vector3(-0.24 * blend, 0.18 * blend, rifle.rotation.z * (1.0 - blend * 0.5))
		var wrist_local: Vector3 = left_hand_pivot.transform * left_wrist_marker.position
		var parent_offset: Vector3 = get_parent().position if get_parent() is Node3D else Vector3(0.21, -0.245, -0.58)
		var left_elbow: Vector3 = Vector3(-0.27, -0.33, -0.20) - parent_offset
		_orient_cylinder(left_sleeve, wrist_local, left_elbow)

	position.x = sin(elapsed * 7.5) * moving * (0.0006 if aimed else 0.0035)
	position.y = absf(sin(elapsed * 7.5)) * moving * (0.0005 if aimed else 0.0025)
