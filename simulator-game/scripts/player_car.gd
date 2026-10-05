extends CharacterBody3D
class_name PlayerCar

signal crashed(severity)

const PBRLibrary = preload("res://scripts/pbr_library.gd")

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
var front_wheels := []
var headlights := []
var brake_lights := []
var camera: Camera3D
var body_visual: Node3D

var engine_low: AudioStreamPlayer3D
var engine_high: AudioStreamPlayer3D
var wind_player: AudioStreamPlayer3D
var road_player: AudioStreamPlayer3D
var start_player: AudioStreamPlayer3D
var impact_player: AudioStreamPlayer3D

const BASE_MAX_SPEED := 43.0
const BASE_ACCEL := 9.4
const BASE_BRAKE := 17.0
const BASE_REVERSE := 9.0

func _ready():
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(50.0)
	_build_visuals()
	_setup_audio()

func _build_visuals():
	body_visual = Node3D.new()
	body_visual.name = "CarVisual"
	add_child(body_visual)

	var paint = PBRLibrary.paint(Color(0.025, 0.20, 0.68), 0.84, 0.17)
	var glass = PBRLibrary.glass()
	var dark = _material(Color(0.018, 0.021, 0.026), 0.56, 0.15)
	var rubber = _material(Color(0.015, 0.017, 0.018), 0.96, 0.0)
	var chrome = _material(Color(0.38, 0.41, 0.44), 0.16, 0.92)
	var lamp_white = _emissive(Color(0.90, 0.96, 1.0), 5.0)
	var lamp_red = _emissive(Color(1.0, 0.02, 0.01), 3.0)

	_add_visual_box(Vector3(1.92, 0.42, 4.28), Vector3(0, 0.68, 0), paint)
	_add_visual_box(Vector3(1.82, 0.22, 1.25), Vector3(0, 0.92, -1.25), paint)
	_add_visual_box(Vector3(1.76, 0.18, 0.92), Vector3(0, 0.88, 1.53), paint)
	_add_visual_box(Vector3(1.64, 0.58, 1.92), Vector3(0, 1.24, 0.18), glass)
	_add_visual_box(Vector3(1.70, 0.11, 1.98), Vector3(0, 1.55, 0.18), paint)
	_add_visual_box(Vector3(1.84, 0.15, 0.13), Vector3(0, 0.46, -2.15), dark)
	_add_visual_box(Vector3(1.84, 0.15, 0.13), Vector3(0, 0.46, 2.15), dark)

	for x in [-0.55, 0.55]:
		_add_visual_box(Vector3(0.42, 0.16, 0.08), Vector3(x, 0.78, -2.17), lamp_white)
		var rear = _add_visual_box(Vector3(0.38, 0.16, 0.08), Vector3(x, 0.76, 2.17), lamp_red)
		brake_lights.append(rear)

	var grille = _add_visual_box(Vector3(1.2, 0.28, 0.045), Vector3(0, 0.60, -2.22), dark)
	grille.rotation_degrees.x = 4.0
	_add_visual_box(Vector3(0.52, 0.06, 0.055), Vector3(0, 0.46, -2.24), chrome)

	for x in [-0.98, 0.98]:
		for z in [-1.38, 1.38]:
			var wheel_root = Node3D.new()
			wheel_root.position = Vector3(x, 0.43, z)
			body_visual.add_child(wheel_root)

			var tire = MeshInstance3D.new()
			var tire_mesh = CylinderMesh.new()
			tire_mesh.top_radius = 0.39
			tire_mesh.bottom_radius = 0.39
			tire_mesh.height = 0.29
			tire_mesh.radial_segments = 24
			tire.mesh = tire_mesh
			tire.rotation_degrees.z = 90
			tire.material_override = rubber
			wheel_root.add_child(tire)

			var rim = MeshInstance3D.new()
			var rim_mesh = CylinderMesh.new()
			rim_mesh.top_radius = 0.235
			rim_mesh.bottom_radius = 0.235
			rim_mesh.height = 0.305
			rim_mesh.radial_segments = 18
			rim.mesh = rim_mesh
			rim.rotation_degrees.z = 90
			rim.material_override = chrome
			wheel_root.add_child(rim)

			wheels.append(wheel_root)
			if z < 0.0:
				front_wheels.append(wheel_root)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.84, 1.05, 4.02)
	collision.shape = shape
	collision.position = Vector3(0, 0.76, 0)
	add_child(collision)

	for x in [-0.58, 0.58]:
		var lamp = SpotLight3D.new()
		lamp.position = Vector3(x, 0.79, -2.18)
		lamp.spot_range = 36.0
		lamp.spot_angle = 31.0
		lamp.light_energy = 5.8
		lamp.shadow_enabled = false
		lamp.visible = false
		add_child(lamp)
		headlights.append(lamp)

	var camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.55, 0.9)
	camera_pivot.rotation_degrees.x = -12.5
	add_child(camera_pivot)

	var spring = SpringArm3D.new()
	spring.spring_length = 8.1
	spring.margin = 0.25
	spring.collision_mask = 1
	camera_pivot.add_child(spring)

	camera = Camera3D.new()
	camera.fov = 70.0
	camera.current = true
	spring.add_child(camera)

func _setup_audio():
	start_player = _audio3d("res://assets/audio/engine_start.wav", false, -2.0)
	engine_low = _audio3d("res://assets/audio/engine_low.wav", true, -3.0)
	engine_high = _audio3d("res://assets/audio/engine_high.wav", true, -28.0)
	road_player = _audio3d("res://assets/audio/road.wav", true, -26.0)
	wind_player = _audio3d("res://assets/audio/wind.ogg", true, -36.0)
	impact_player = _audio3d("res://assets/audio/impact.wav", false, -5.0)

	if start_player and start_player.stream:
		start_player.play()
	if engine_low and engine_low.stream:
		engine_low.play()
	if engine_high and engine_high.stream:
		engine_high.play()
	if road_player and road_player.stream:
		road_player.play()
	if wind_player and wind_player.stream:
		wind_player.play()

func _audio3d(path: String, looped: bool, volume: float) -> AudioStreamPlayer3D:
	var p = AudioStreamPlayer3D.new()
	p.unit_size = 3.0
	p.max_distance = 70.0
	p.volume_db = volume
	if ResourceLoader.exists(path):
		p.stream = load(path)
		if looped:
			if p.stream is AudioStreamWAV:
				p.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			elif p.stream is AudioStreamOggVorbis:
				p.stream.loop = true
	add_child(p)
	return p

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

	var max_speed = (BASE_MAX_SPEED + engine_level * 3.2) * (1.0 - min(damage / 180.0, 0.36))
	var accel = BASE_ACCEL + engine_level * 1.18
	var brake_power = BASE_BRAKE + brake_level * 2.0
	var reverse_speed = BASE_REVERSE + engine_level * 0.38

	if throttle > 0.01:
		if speed < -0.2:
			speed = move_toward(speed, 0.0, brake_power * delta)
		else:
			var accel_falloff = lerp(1.0, 0.34, clamp(abs(speed) / max(max_speed, 1.0), 0.0, 1.0))
			speed = move_toward(speed, max_speed, accel * accel_falloff * throttle * delta)

	if brake > 0.01:
		if speed > 0.45:
			speed = move_toward(speed, 0.0, brake_power * brake * delta)
		else:
			speed = move_toward(speed, -reverse_speed, (accel * 0.72) * brake * delta)

	if throttle < 0.01 and brake < 0.01:
		var drag = 0.72 + abs(speed) * 0.048 + speed * speed * 0.0012
		speed = move_toward(speed, 0.0, drag * delta)

	if handbrake:
		speed = move_toward(speed, 0.0, (27.0 + brake_level * 2.0) * delta)

	var speed_ratio = clamp(abs(speed) / max(max_speed, 1.0), 0.0, 1.0)
	var speed_factor = clamp(abs(speed) / 11.0, 0.16, 1.0)
	var steer_rate = lerp(1.48, 0.48, speed_ratio)
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
		if impact_player and impact_player.stream:
			impact_player.pitch_scale = randf_range(0.82, 1.08)
			impact_player.play()
		crashed.emit(severity)

	if throttle > 0.01 and speed > 0.1:
		var load = 0.0045 + speed_ratio * 0.0105
		fuel = max(0.0, fuel - load * throttle * delta)

	for wheel in wheels:
		wheel.rotate_x(speed * delta * 1.25)
	for wheel in front_wheels:
		wheel.rotation.y = lerp(wheel.rotation.y, steer * 0.42, delta * 8.0)

	if body_visual:
		body_visual.rotation.z = lerp(body_visual.rotation.z, -steer * speed_ratio * 0.045, delta * 5.5)
		body_visual.rotation.x = lerp(body_visual.rotation.x, (brake - throttle * 0.35) * 0.018, delta * 5.0)

	if camera:
		camera.fov = lerp(camera.fov, 70.0 + speed_ratio * 8.0, delta * 2.8)

	for lamp in brake_lights:
		var m = lamp.material_override as StandardMaterial3D
		if m:
			m.emission_energy_multiplier = 7.0 if brake > 0.08 else 2.7

	_update_audio(speed_ratio, throttle, handbrake)

	if global_position.y < -5.0:
		global_position = Vector3(4, 1.0, 0)
		speed = 0.0

func _update_audio(speed_ratio: float, throttle: float, handbrake: bool):
	if engine_low:
		engine_low.pitch_scale = 0.78 + speed_ratio * 0.68 + throttle * 0.10
		engine_low.volume_db = lerp(-2.0, -11.0, speed_ratio)
	if engine_high:
		engine_high.pitch_scale = 0.84 + speed_ratio * 0.72
		engine_high.volume_db = lerp(-28.0, -1.5, clamp((speed_ratio - 0.22) / 0.78, 0.0, 1.0))
	if road_player:
		road_player.pitch_scale = 0.78 + speed_ratio * 0.46
		road_player.volume_db = lerp(-32.0, -7.0, speed_ratio)
	if wind_player:
		wind_player.pitch_scale = 0.82 + speed_ratio * 0.52
		wind_player.volume_db = lerp(-40.0, -8.0, speed_ratio)
		if handbrake and speed_ratio > 0.22:
			wind_player.volume_db += 3.0

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

func _add_visual_box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = material
	body_visual.add_child(mesh)
	return mesh

func _material(color: Color, roughness := 0.72, metallic := 0.0) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.18
	return mat
