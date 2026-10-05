extends CharacterBody3D
class_name TrafficCar

const BLENDER_CAR := "res://assets/models/sport_sedan.glb"

var route := []
var route_index := 0
var cruise_speed := 9.0
var current_speed := 0.0

func setup(points, start_index, car_color, desired_speed):
	route = points
	route_index = (start_index + 1) % route.size()
	global_position = route[start_index]
	cruise_speed = desired_speed
	current_speed = desired_speed * 0.6
	_build_visuals(car_color)

func _ready():
	collision_layer = 4
	collision_mask = 1 | 2 | 4

func _physics_process(delta):
	if route.size() < 2:
		return

	var target = route[route_index]
	var flat = target - global_position
	flat.y = 0.0

	if flat.length() < 2.4:
		route_index = (route_index + 1) % route.size()
		target = route[route_index]
		flat = target - global_position
		flat.y = 0.0

	var dir = flat.normalized()
	if dir.length() < 0.1:
		return

	var target_yaw = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * 2.8)

	var desired = cruise_speed
	if get_slide_collision_count() > 0:
		desired = 2.0
	current_speed = move_toward(current_speed, desired, delta * 4.0)

	var forward = -global_transform.basis.z
	velocity = forward * current_speed
	velocity.y = -0.5
	move_and_slide()

func _build_visuals(car_color):
	var loaded := false
	if ResourceLoader.exists(BLENDER_CAR):
		var packed = load(BLENDER_CAR)
		if packed is PackedScene:
			var model = packed.instantiate()
			model.scale = Vector3(0.92, 0.92, 0.92)
			add_child(model)
			loaded = true

	if not loaded:
		var body_mat = StandardMaterial3D.new()
		body_mat.albedo_color = car_color
		body_mat.metallic = 0.52
		body_mat.roughness = 0.28

		var glass_mat = StandardMaterial3D.new()
		glass_mat.albedo_color = Color(0.04, 0.08, 0.12)
		glass_mat.roughness = 0.16

		var body = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1.75, 0.5, 3.75)
		body.mesh = box
		body.position.y = 0.62
		body.material_override = body_mat
		add_child(body)

		var cabin = MeshInstance3D.new()
		var cabin_box = BoxMesh.new()
		cabin_box.size = Vector3(1.5, 0.58, 1.75)
		cabin.mesh = cabin_box
		cabin.position = Vector3(0, 1.12, 0.08)
		cabin.material_override = glass_mat
		add_child(cabin)

	var shape_node = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.72, 0.95, 3.65)
	shape_node.shape = shape
	shape_node.position = Vector3(0, 0.65, 0)
	add_child(shape_node)
