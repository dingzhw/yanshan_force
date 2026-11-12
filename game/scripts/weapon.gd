extends Node3D
## Tactical YS-04 Carbine viewmodel with Reflex Optic, two-tone metallic finish, and clean grip (no cylinder arms).

var game
var rifle: Node3D
var optic_root: Node3D
var reticle_dot: MeshInstance3D
var support_grip: Node3D
var flash: MeshInstance3D
var light: OmniLight3D
var magazine: Node3D
var shot_left = 0.0
var elapsed = 0.0

func _ready():
	rifle = game._model(self, "res://assets/slice/rifle.glb", Vector3.ZERO, 0.22, 0)
	magazine = rifle.find_child("YS04_magazine", true, false)
	var has_mag2 = "magazine2" in game.rules.profile.owned
	var has_mag1 = "magazine" in game.rules.profile.owned
	if is_instance_valid(magazine):
		if has_mag2:
			magazine.scale = Vector3(1.18, 1.42, 1.15)
		elif has_mag1:
			magazine.scale.y = 1.25

	var has_skin = "forest_skin" in game.rules.profile.owned
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

	# Integrated under-barrel tactical handguard foregrip (centered cleanly under barrel)
	var glove = StandardMaterial3D.new()
	glove.albedo_color = Color("1e2524")
	glove.metallic = 0.35
	glove.roughness = 0.65
	support_grip = Node3D.new()
	support_grip.position = Vector3(0.0, 0.112, -0.15)
	add_child(support_grip)
	var cradle = MeshInstance3D.new()
	var cradle_box = BoxMesh.new()
	cradle_box.size = Vector3(0.032, 0.026, 0.092)
	cradle.mesh = cradle_box
	cradle.material_override = glove
	cradle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	support_grip.add_child(cradle)

	_build_reflex_optic()

	# Crisp multi-fin muzzle flash
	flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.028
	sphere.height = 0.13
	flash.mesh = sphere
	flash.rotation.x = PI / 2
	flash.position = Vector3(0, 0.135, -0.42)
	flash.material_override = game._material(Color("ffe29a"), true)
	flash.hide()
	add_child(flash)

	light = OmniLight3D.new()
	light.position = flash.position
	light.omni_range = 3.2
	light.light_color = Color("ffd699")
	light.light_energy = 0.0
	add_child(light)

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

	# Rail mount base + open reflex hood
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

	# Subtle anti-reflective glass window
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

	# Glowing precision reticle dot inside glass
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
	var dip = sin(reload_progress * PI)
	rifle.rotation.z = dip * -0.30
	optic_root.rotation.z = rifle.rotation.z
	support_grip.position = Vector3(0.0, 0.112 - dip * 0.14, -0.15 + dip * 0.14)
	if is_instance_valid(magazine):
		magazine.position = Vector3(0, -dip * 0.18, dip * 0.08)
		magazine.rotation.x = -dip * 0.15
	position.x = sin(elapsed * 7.5) * moving * (0.0006 if aimed else 0.0035)
	position.y = absf(sin(elapsed * 7.5)) * moving * (0.0005 if aimed else 0.0025)
