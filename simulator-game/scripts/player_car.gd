extends CharacterBody3D
class_name PlayerCar

signal crashed(severity)

var speed := 0.0
var fuel := 45.0
var fuel_capacity := 45.0
var damage := 0.0

var engine_level := 0
var brake_level := 0
var tank_level := 0
var armor_level := 0

var controls_locked := false
var crash_cooldown := 0.0
var wheels := []
var headlights := []

const BASE_MAX_SPEED := 31.0
const BASE_ACCEL := 8.2
const BASE_BRAKE := 15.0
const BASE_REVERSE := 8.0

func _ready():
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(50.0)
	_build_visuals()

func _build_visuals():
	var body_mat = _material(Color(0.08, 0.28, 0.72))
	var glass_mat = _material(Color(0.08, 0.13, 0.18))
	glass_mat.metallic = 0.15
	glass_mat.roughness = 0.2
	var dark_mat = _material(Color(0.035, 0.04, 0.045))

	var body = MeshInstance3D.new()
	var body_mesh = BoxMesh.new()
	body_mesh.size = Vector3(1.9, 0.55, 4.2)
	body.mesh = body_mesh
	body.position = Vector3(0, 0.72, 0)
	body.material_override = body_mat
	add_child(body)

	var cabin = MeshInstance3D.new()
	var cabin_mesh = BoxMesh.new()
	cabin_mesh.size = Vector3(1.62, 0.68, 2.05)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0, 1.26, 0.15)
	cabin.material_override = glass_mat
	add_child(cabin)

	var bumper_front = MeshInstance3D.new()
	var bumper_mesh = BoxMesh.new()
	bumper_mesh.size = Vector3(1.82, 0.18, 0.16)
	bumper_front.mesh = bumper_mesh
	bumper_front.position = Vector3(0, 0.48, -2.12)
	bumper_front.material_override = dark_mat
	add_child(bumper_front)

	var bumper_back = bumper_front.duplicate()
	bumper_back.position.z = 2.12
	add_child(bumper_back)

	for x in [-0.98, 0.98]:
		for z in [-1.34, 1.34]:
			var wheel = MeshInstance3D.new()
			var wheel_mesh = CylinderMesh.new()
			wheel_mesh.top_radius = 0.38
			wheel_mesh.bottom_radius = 0.38
			wheel_mesh.height = 0.28
			wheel.mesh = wheel_mesh
			wheel.rotation_degrees.z = 90
			wheel.position = Vector3(x, 0.43, z)
			wheel.material_override = dark_mat
			add_child(wheel)
			wheels.append(wheel)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.82, 1.05, 4.0)
	collision.shape = shape
	collision.position = Vector3(0, 0.75, 0)
	add_child(collision)

	for x in [-0.58, 0.58]:
		var lamp = SpotLight3D.new()
		lamp.position = Vector3(x, 0.83, -2.14)
		lamp.spot_range = 24.0
		lamp.spot_angle = 34.0
		lamp.light_energy = 4.2
		lamp.shadow_enabled = false
		lamp.visible = false
		add_child(lamp)
		headlights.append(lamp)

	var camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.55, 0.85)
	camera_pivot.rotation_degrees.x = -13.0
	add_child(camera_pivot)

	var spring = SpringArm3D.new()
	spring.spring_length = 8.5
	spring.margin = 0.25
	spring.collision_mask = 1
	camera_pivot.add_child(spring)

	var camera = Camera3D.new()
	camera.fov = 72.0
	camera.current = true
	spring.add_child(camera)

func _physics_process(delta):
	crash_cooldown = max(0.0, crash_cooldown - delta)

	var throttle = 0.0
	var brake = 0.0
	var steer = 0.0
	var handbrake = false

	if not controls_locked:
		throttle = Input.get_action_strength("move_forward")
		brake = Input.get_action_strength("move_back")
		steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		handbrake = Input.is_action_pressed("handbrake")

	if fuel <= 0.01:
		throttle = 0.0

	var max_speed = (BASE_MAX_SPEED + engine_level * 3.0) * (1.0 - min(damage / 180.0, 0.36))
	var accel = BASE_ACCEL + engine_level * 1.15
	var brake_power = BASE_BRAKE + brake_level * 1.9
	var reverse_speed = BASE_REVERSE + engine_level * 0.35

	if throttle > 0.01:
		if speed < -0.2:
			speed = move_toward(speed, 0.0, brake_power * delta)
		else:
			speed = move_toward(speed, max_speed, accel * throttle * delta)

	if brake > 0.01:
		if speed > 0.45:
			speed = move_toward(speed, 0.0, brake_power * brake * delta)
		else:
			speed = move_toward(speed, -reverse_speed, (accel * 0.72) * brake * delta)

	if throttle < 0.01 and brake < 0.01:
		speed = move_toward(speed, 0.0, (1.25 + abs(speed) * 0.035) * delta)

	if handbrake:
		speed = move_toward(speed, 0.0, (25.0 + brake_level * 2.0) * delta)

	var speed_factor = clamp(abs(speed) / 11.0, 0.18, 1.0)
	var steer_rate = lerp(1.55, 0.68, clamp(abs(speed) / max(max_speed, 1.0), 0.0, 1.0))
	if abs(speed) > 0.12:
		var reverse_sign = 1.0 if speed >= 0.0 else -1.0
		rotation.y -= steer * steer_rate * speed_factor * reverse_sign * delta

	var previous_speed = abs(speed)
	var forward = -global_transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	velocity.y = -1.0
	move_and_slide()

	if get_slide_collision_count() > 0 and previous_speed > 7.5 and crash_cooldown <= 0.0:
		var raw = (previous_speed - 7.5) * 1.25
		var armor_factor = 1.0 - armor_level * 0.09
		var severity = clamp(raw * armor_factor, 1.0, 20.0)
		damage = clamp(damage + severity, 0.0, 100.0)
		speed *= 0.46
		crash_cooldown = 0.7
		crashed.emit(severity)

	if throttle > 0.01 and speed > 0.1:
		var load = 0.0045 + (abs(speed) / max(max_speed, 1.0)) * 0.0105
		fuel = max(0.0, fuel - load * throttle * delta)

	for wheel in wheels:
		wheel.rotate_x(speed * delta * 1.25)

	if global_position.y < -5.0:
		global_position = Vector3(4, 1.0, 0)
		speed = 0.0

func set_headlights(enabled):
	for light in headlights:
		light.visible = enabled

func apply_upgrade(kind):
	match kind:
		"engine":
			engine_level += 1
		"brakes":
			brake_level += 1
		"tank":
			tank_level += 1
			fuel_capacity = 45.0 + tank_level * 8.0
			fuel = min(fuel, fuel_capacity)
		"armor":
			armor_level += 1

func get_speed_kmh():
	return abs(speed) * 3.6

func _material(color):
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.72
	return mat
