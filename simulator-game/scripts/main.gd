extends Node3D

const PlayerCarScript = preload("res://scripts/player_car.gd")
const TrafficCarScript = preload("res://scripts/traffic_car.gd")

var rng = RandomNumberGenerator.new()
var player
var sun
var world_environment
var marker_root
var marker_label
var marker_base_position := Vector3.ZERO

var cash := 2500.0
var mission_phase := 0
var mission_pickup := Vector3.ZERO
var mission_dropoff := Vector3.ZERO
var mission_payout := 0.0
var cargo_name := ""
var road_points := []
var traffic := []

var speed_label
var stats_label
var mission_label
var notify_label
var notify_time := 0.0
var garage_panel
var garage_buttons := {}
var touch_nodes := []
var touch_visuals := []

var time_of_day := 10.0
var garage_position := Vector3(0, 0, 0)
var fuel_position := Vector3(100, 0, 4)
var save_path := "user://roadlife_save.json"

var asphalt_mat
var sidewalk_mat
var grass_mat
var line_mat
var building_mats := []

func _ready():
	rng.seed = 2232026
	_setup_input_map()
	_setup_environment()
	_create_materials()
	_build_city()
	_spawn_player()
	_spawn_traffic()
	_build_marker()
	_build_ui()
	_load_game()
	_new_mission()
	_notify("RoadLife Simulator – dein erster Auftrag ist markiert.")

func _setup_input_map():
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_forward", KEY_UP)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_back", KEY_DOWN)
	_add_key_action("steer_left", KEY_A)
	_add_key_action("steer_left", KEY_LEFT)
	_add_key_action("steer_right", KEY_D)
	_add_key_action("steer_right", KEY_RIGHT)
	_add_key_action("handbrake", KEY_SPACE)
	_add_key_action("interact", KEY_E)

	_add_joy_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_axis("move_back", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_joy_button("handbrake", JOY_BUTTON_A)
	_add_joy_button("interact", JOY_BUTTON_X)

func _add_key_action(action_name, keycode):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev = InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)

func _add_joy_axis(action_name, axis, value):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action_name, ev)

func _add_joy_button(action_name, button_index):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev = InputEventJoypadButton.new()
	ev.button_index = button_index
	InputMap.action_add_event(action_name, ev)

func _setup_environment():
	world_environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.40, 0.63, 0.79)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.76, 0.86)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = env
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 95.0
	add_child(sun)

func _create_materials():
	asphalt_mat = _material(Color(0.085, 0.095, 0.105), 0.95)
	sidewalk_mat = _material(Color(0.34, 0.36, 0.38), 0.92)
	grass_mat = _material(Color(0.12, 0.34, 0.16), 0.96)
	line_mat = _material(Color(0.88, 0.85, 0.58), 0.8)

	var colors = [
		Color(0.53, 0.58, 0.62),
		Color(0.58, 0.43, 0.35),
		Color(0.42, 0.50, 0.61),
		Color(0.64, 0.61, 0.52),
		Color(0.39, 0.44, 0.47),
		Color(0.53, 0.46, 0.58)
	]
	for c in colors:
		building_mats.append(_material(c, 0.88))

func _build_city():
	_add_box("Ground", Vector3(400, 0.2, 400), Vector3(0, -0.1, 0), grass_mat, true)

	for i in range(-3, 4):
		var c = i * 48.0
		_add_box("Road_NS_%d" % i, Vector3(12, 0.04, 360), Vector3(c, 0.02, 0), asphalt_mat, false)
		_add_box("Road_EW_%d" % i, Vector3(360, 0.04, 12), Vector3(0, 0.021, c), asphalt_mat, false)

		for s in range(-10, 11):
			var d = s * 16.0
			_add_box("Mark_NS", Vector3(0.14, 0.025, 5.2), Vector3(c, 0.047, d), line_mat, false)
			_add_box("Mark_EW", Vector3(5.2, 0.025, 0.14), Vector3(d, 0.048, c), line_mat, false)

	for bx in range(-3, 3):
		for bz in range(-3, 3):
			var center = Vector3((bx + 0.5) * 48.0, 0, (bz + 0.5) * 48.0)
			_add_box("Sidewalk", Vector3(34, 0.16, 34), Vector3(center.x, 0.08, center.z), sidewalk_mat, false)
			for ox in [-9.0, 9.0]:
				for oz in [-9.0, 9.0]:
					var h = rng.randf_range(9.0, 34.0)
					var sx = rng.randf_range(12.0, 15.0)
					var sz = rng.randf_range(12.0, 15.0)
					var pos = Vector3(center.x + ox, h * 0.5 + 0.16, center.z + oz)
					var mat = building_mats[rng.randi_range(0, building_mats.size() - 1)]
					_add_box("Building", Vector3(sx, h, sz), pos, mat, true)

	for ix in range(-3, 4):
		for j in range(-6, 7):
			road_points.append(Vector3(ix * 48.0 + 3.1, 0.6, j * 24.0))
			road_points.append(Vector3(j * 24.0, 0.6, ix * 48.0 - 3.1))

	for z in range(-5, 6, 2):
		_add_tree(Vector3(-171, 0, z * 28.0))
		_add_tree(Vector3(171, 0, z * 28.0))
	for x in range(-5, 6, 2):
		_add_tree(Vector3(x * 28.0, 0, -171))
		_add_tree(Vector3(x * 28.0, 0, 171))

	_add_service_pad(garage_position, Color(0.12, 0.50, 0.95), "GARAGE")
	_add_service_pad(fuel_position, Color(0.10, 0.76, 0.36), "TANKSTELLE")

func _add_tree(pos):
	var trunk_mat = _material(Color(0.30, 0.19, 0.10), 1.0)
	var leaves_mat = _material(Color(0.08, 0.39, 0.14), 1.0)

	var trunk = MeshInstance3D.new()
	var trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 2.4
	trunk.mesh = trunk_mesh
	trunk.position = pos + Vector3(0, 1.2, 0)
	trunk.material_override = trunk_mat
	add_child(trunk)

	var crown = MeshInstance3D.new()
	var crown_mesh = SphereMesh.new()
	crown_mesh.radius = 1.25
	crown_mesh.height = 2.5
	crown.mesh = crown_mesh
	crown.position = pos + Vector3(0, 3.0, 0)
	crown.material_override = leaves_mat
	add_child(crown)

func _add_service_pad(pos, color, title):
	var mat = _material(color, 0.75)
	mat.emission_enabled = true
	mat.emission = color * 0.65
	mat.emission_energy_multiplier = 0.55
	_add_box(title, Vector3(10, 0.06, 10), pos + Vector3(0, 0.04, 0), mat, false)

	var label = Label3D.new()
	label.text = title
	label.font_size = 54
	label.outline_size = 10
	label.modulate = Color.WHITE
	label.position = pos + Vector3(0, 3.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _add_box(node_name, size, pos, material, with_collision):
	var root = StaticBody3D.new() if with_collision else Node3D.new()
	root.name = node_name
	root.position = pos
	add_child(root)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	root.add_child(mesh)

	if with_collision:
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		root.add_child(collision)
	return root

func _spawn_player():
	player = PlayerCarScript.new()
	player.name = "PlayerCar"
	player.global_position = Vector3(4, 0.8, 0)
	add_child(player)
	player.crashed.connect(_on_player_crashed)

func _spawn_traffic():
	var routes = [
		[Vector3(-96, 0.55, -3), Vector3(96, 0.55, -3), Vector3(96, 0.55, 48), Vector3(-96, 0.55, 48)],
		[Vector3(-48, 0.55, -96), Vector3(-48, 0.55, 96), Vector3(3, 0.55, 96), Vector3(3, 0.55, -96)],
		[Vector3(-144, 0.55, -51), Vector3(144, 0.55, -51), Vector3(144, 0.55, 3), Vector3(-144, 0.55, 3)]
	]
	var colors = [
		Color(0.72, 0.12, 0.10),
		Color(0.10, 0.55, 0.72),
		Color(0.82, 0.66, 0.12),
		Color(0.22, 0.24, 0.28),
		Color(0.74, 0.74, 0.76)
	]
	for i in range(9):
		var car = TrafficCarScript.new()
		add_child(car)
		var route = routes[i % routes.size()]
		car.setup(route, i % route.size(), colors[i % colors.size()], 7.0 + (i % 4) * 1.15)
		traffic.append(car)

func _build_marker():
	marker_root = Node3D.new()
	add_child(marker_root)

	var mesh = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 2.1
	cylinder.bottom_radius = 2.1
	cylinder.height = 0.18
	mesh.mesh = cylinder
	mesh.position.y = 0.12
	marker_root.add_child(mesh)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.70, 1.0, 0.58)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.45, 1.0)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.set_meta("marker_material", mat)

	var light = OmniLight3D.new()
	light.omni_range = 7.0
	light.light_energy = 1.6
	light.light_color = Color(0.10, 0.65, 1.0)
	light.position.y = 1.1
	marker_root.add_child(light)

	marker_label = Label3D.new()
	marker_label.text = "ABHOLUNG"
	marker_label.font_size = 42
	marker_label.outline_size = 9
	marker_label.position.y = 2.4
	marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker_root.add_child(marker_label)

func _build_ui():
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var root = Control.new()
	canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var top_panel = Panel.new()
	top_panel.position = Vector2(18, 18)
	top_panel.size = Vector2(430, 132)
	top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.05, 0.86), 18))
	root.add_child(top_panel)

	speed_label = Label.new()
	speed_label.position = Vector2(18, 12)
	speed_label.size = Vector2(190, 52)
	speed_label.text = "0 km/h"
	speed_label.add_theme_font_size_override("font_size", 34)
	top_panel.add_child(speed_label)

	stats_label = Label.new()
	stats_label.position = Vector2(210, 14)
	stats_label.size = Vector2(205, 50)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_label.add_theme_font_size_override("font_size", 20)
	top_panel.add_child(stats_label)

	mission_label = Label.new()
	mission_label.position = Vector2(18, 68)
	mission_label.size = Vector2(395, 52)
	mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_label.add_theme_font_size_override("font_size", 17)
	top_panel.add_child(mission_label)

	notify_label = Label.new()
	notify_label.position = Vector2(350, 168)
	notify_label.size = Vector2(580, 58)
	notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notify_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notify_label.add_theme_font_size_override("font_size", 20)
	notify_label.add_theme_stylebox_override("normal", _panel_style(Color(0.02, 0.03, 0.045, 0.88), 16))
	notify_label.visible = false
	root.add_child(notify_label)

	_add_touch_control(canvas, root, "◀", Vector2(102, 610), 116, "steer_left", Color(0.13, 0.28, 0.48, 0.58))
	_add_touch_control(canvas, root, "▶", Vector2(235, 610), 116, "steer_right", Color(0.13, 0.28, 0.48, 0.58))
	_add_touch_control(canvas, root, "GAS", Vector2(1172, 600), 128, "move_forward", Color(0.08, 0.54, 0.28, 0.62))
	_add_touch_control(canvas, root, "BREMSE", Vector2(1025, 612), 112, "move_back", Color(0.69, 0.13, 0.13, 0.62))
	_add_touch_control(canvas, root, "DRIFT", Vector2(1102, 470), 86, "handbrake", Color(0.82, 0.48, 0.08, 0.62))
	_add_touch_control(canvas, root, "AKTION", Vector2(1190, 395), 78, "interact", Color(0.40, 0.20, 0.66, 0.62))

	garage_panel = Panel.new()
	garage_panel.position = Vector2(392, 126)
	garage_panel.size = Vector2(496, 468)
	garage_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.05, 0.96), 22))
	garage_panel.visible = false
	root.add_child(garage_panel)

	var garage_title = Label.new()
	garage_title.position = Vector2(24, 18)
	garage_title.size = Vector2(448, 50)
	garage_title.text = "GARAGE"
	garage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	garage_title.add_theme_font_size_override("font_size", 30)
	garage_panel.add_child(garage_title)

	var y = 86
	for kind in ["engine", "brakes", "tank", "armor"]:
		var b = Button.new()
		b.position = Vector2(54, y)
		b.size = Vector2(388, 56)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_buy_upgrade.bind(kind))
		garage_panel.add_child(b)
		garage_buttons[kind] = b
		y += 64

	var repair = Button.new()
	repair.position = Vector2(54, 342)
	repair.size = Vector2(188, 54)
	repair.text = "REPARIEREN"
	repair.add_theme_font_size_override("font_size", 17)
	repair.pressed.connect(_repair_car)
	garage_panel.add_child(repair)
	garage_buttons["repair"] = repair

	var close = Button.new()
	close.position = Vector2(254, 342)
	close.size = Vector2(188, 54)
	close.text = "SCHLIESSEN"
	close.add_theme_font_size_override("font_size", 17)
	close.pressed.connect(_toggle_garage)
	garage_panel.add_child(close)

	var hint = Label.new()
	hint.position = Vector2(42, 410)
	hint.size = Vector2(410, 42)
	hint.text = "Garage: Auf blauem Feld AKTION drücken"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.73, 0.78, 0.83)
	garage_panel.add_child(hint)

func _add_touch_control(canvas, root, label_text, center, diameter, action_name, color):
	var panel = Panel.new()
	panel.position = center - Vector2(diameter * 0.5, diameter * 0.5)
	panel.size = Vector2(diameter, diameter)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(color, int(diameter * 0.5)))
	root.add_child(panel)
	touch_visuals.append(panel)

	var label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22 if diameter < 100 else 26)
	panel.add_child(label)

	var touch = TouchScreenButton.new()
	var shape = CircleShape2D.new()
	shape.radius = diameter * 0.5
	touch.shape = shape
	touch.shape_centered = true
	touch.shape_visible = false
	touch.position = center
	touch.action = action_name
	touch.passby_press = true
	canvas.add_child(touch)
	touch_nodes.append(touch)

func _process(delta):
	if not player:
		return

	if Input.is_action_just_pressed("interact") and not garage_panel.visible:
		_handle_interact()

	_update_day_night(delta)
	_update_mission()
	_update_hud()

	if marker_root:
		marker_root.rotation.y += delta * 0.8
		marker_root.global_position = marker_base_position + Vector3(0, 0.22 + sin(Time.get_ticks_msec() * 0.003) * 0.14, 0)

	if notify_time > 0.0:
		notify_time -= delta
		if notify_time <= 0.0:
			notify_label.visible = false

func _update_day_night(delta):
	time_of_day = fmod(time_of_day + delta * 0.055, 24.0)
	var daylight = clamp(sin((time_of_day - 6.0) / 12.0 * PI), 0.0, 1.0)
	sun.rotation_degrees.x = time_of_day / 24.0 * 360.0 - 100.0
	sun.light_energy = 0.13 + daylight * 1.16

	var day_color = Color(0.40, 0.63, 0.79)
	var night_color = Color(0.035, 0.055, 0.10)
	world_environment.environment.background_color = night_color.lerp(day_color, daylight)
	world_environment.environment.ambient_light_energy = 0.20 + daylight * 0.48
	player.set_headlights(daylight < 0.24)

func _update_mission():
	var target = mission_pickup if mission_phase == 0 else mission_dropoff
	var distance = player.global_position.distance_to(target)
	if distance < 5.2 and abs(player.speed) < 3.0:
		if mission_phase == 0:
			mission_phase = 1
			_set_marker_target(mission_dropoff, false)
			_notify("Fracht geladen: %s. Jetzt zum Ziel." % cargo_name)
		else:
			var condition_bonus = max(0.0, 1.0 - player.damage / 140.0)
			var reward = mission_payout * condition_bonus
			cash += reward
			_notify("Auftrag erledigt! +€%d" % int(reward))
			_save_game()
			_new_mission()

func _new_mission():
	if road_points.size() < 2:
		return
	var cargo = ["Ersatzteile", "Elektronik", "Lebensmittel", "Werkzeug", "Medikamente", "Pakete"]
	cargo_name = cargo[rng.randi_range(0, cargo.size() - 1)]
	mission_pickup = road_points[rng.randi_range(0, road_points.size() - 1)]
	mission_dropoff = road_points[rng.randi_range(0, road_points.size() - 1)]
	var guard = 0
	while mission_pickup.distance_to(mission_dropoff) < 85.0 and guard < 30:
		mission_dropoff = road_points[rng.randi_range(0, road_points.size() - 1)]
		guard += 1
	mission_phase = 0
	mission_payout = 180.0 + mission_pickup.distance_to(mission_dropoff) * 2.35
	_set_marker_target(mission_pickup, true)

func _set_marker_target(pos, pickup):
	marker_base_position = Vector3(pos.x, 0.08, pos.z)
	marker_label.text = "ABHOLUNG" if pickup else "ZIEL"
	var mesh = marker_root.get_child(0)
	var mat = mesh.get_meta("marker_material")
	var color = Color(0.08, 0.68, 1.0) if pickup else Color(1.0, 0.52, 0.08)
	mat.albedo_color = Color(color.r, color.g, color.b, 0.58)
	mat.emission = color
	var light = marker_root.get_child(1)
	light.light_color = color

func _update_hud():
	var target = mission_pickup if mission_phase == 0 else mission_dropoff
	var distance = player.global_position.distance_to(target)
	speed_label.text = "%03d km/h" % int(player.get_speed_kmh())
	stats_label.text = "€%d\nSprit %.1f/%.0f L  |  Schaden %d%%" % [int(cash), player.fuel, player.fuel_capacity, int(player.damage)]
	var stage = "Abholen" if mission_phase == 0 else "Abliefern"
	mission_label.text = "%s: %s  •  %dm  •  Lohn ca. €%d" % [stage, cargo_name, int(distance), int(mission_payout)]

	if garage_panel.visible:
		_update_garage_buttons()

func _handle_interact():
	var d_garage = player.global_position.distance_to(garage_position)
	var d_fuel = player.global_position.distance_to(fuel_position)

	if d_garage < 8.0 and abs(player.speed) < 2.0:
		_toggle_garage()
	elif d_fuel < 8.0 and abs(player.speed) < 2.0:
		_refuel_car()
	else:
		_notify("Keine Aktion hier. Fahre zur Garage oder Tankstelle.")

func _toggle_garage():
	garage_panel.visible = not garage_panel.visible
	player.controls_locked = garage_panel.visible
	for n in touch_nodes:
		n.visible = not garage_panel.visible
	for n in touch_visuals:
		n.visible = not garage_panel.visible
	if garage_panel.visible:
		_update_garage_buttons()
	else:
		_save_game()

func _upgrade_cost(kind):
	match kind:
		"engine":
			return 1250 * (player.engine_level + 1)
		"brakes":
			return 950 * (player.brake_level + 1)
		"tank":
			return 850 * (player.tank_level + 1)
		"armor":
			return 1100 * (player.armor_level + 1)
	return 999999

func _upgrade_level(kind):
	match kind:
		"engine":
			return player.engine_level
		"brakes":
			return player.brake_level
		"tank":
			return player.tank_level
		"armor":
			return player.armor_level
	return 0

func _buy_upgrade(kind):
	var level = _upgrade_level(kind)
	if level >= 5:
		_notify("Dieses Upgrade ist bereits auf Maximum.")
		return
	var cost = _upgrade_cost(kind)
	if cash < cost:
		_notify("Dafür fehlen dir €%d." % int(cost - cash))
		return
	cash -= cost
	player.apply_upgrade(kind)
	_notify("Upgrade gekauft.")
	_update_garage_buttons()
	_save_game()

func _repair_car():
	if player.damage < 0.5:
		_notify("Das Fahrzeug ist bereits in Ordnung.")
		return
	var cost = max(80.0, player.damage * 22.0)
	if cash < cost:
		_notify("Reparatur kostet €%d." % int(cost))
		return
	cash -= cost
	player.damage = 0.0
	_notify("Fahrzeug vollständig repariert.")
	_save_game()

func _refuel_car():
	var missing = max(0.0, player.fuel_capacity - player.fuel)
	if missing < 0.05:
		_notify("Tank ist bereits voll.")
		return
	var price_per_liter = 2.05
	var liters = min(missing, cash / price_per_liter)
	if liters <= 0.01:
		_notify("Nicht genug Geld zum Tanken.")
		return
	var cost = liters * price_per_liter
	cash -= cost
	player.fuel += liters
	_notify("%.1f L getankt – €%d" % [liters, int(cost)])
	_save_game()

func _update_garage_buttons():
	var names = {
		"engine": "Motor",
		"brakes": "Bremsen",
		"tank": "Tank",
		"armor": "Karosserie"
	}
	for kind in ["engine", "brakes", "tank", "armor"]:
		var level = _upgrade_level(kind)
		if level >= 5:
			garage_buttons[kind].text = "%s  Stufe %d/5  •  MAX" % [names[kind], level]
		else:
			garage_buttons[kind].text = "%s  Stufe %d/5  •  €%d" % [names[kind], level, _upgrade_cost(kind)]
	var repair_cost = max(80.0, player.damage * 22.0)
	garage_buttons["repair"].text = "REPARIEREN €%d" % int(repair_cost)

func _on_player_crashed(severity):
	_notify("Unfall! Fahrzeugschaden +%d%%" % int(severity))

func _notify(text):
	if not notify_label:
		return
	notify_label.text = text
	notify_label.visible = true
	notify_time = 3.0

func _save_game():
	if not player:
		return
	var data = {
		"cash": cash,
		"fuel": player.fuel,
		"damage": player.damage,
		"engine_level": player.engine_level,
		"brake_level": player.brake_level,
		"tank_level": player.tank_level,
		"armor_level": player.armor_level,
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"rotation_y": player.rotation.y,
		"time_of_day": time_of_day
	}
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func _load_game():
	if not FileAccess.file_exists(save_path):
		return
	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	cash = float(parsed.get("cash", cash))
	player.engine_level = int(parsed.get("engine_level", 0))
	player.brake_level = int(parsed.get("brake_level", 0))
	player.tank_level = int(parsed.get("tank_level", 0))
	player.armor_level = int(parsed.get("armor_level", 0))
	player.fuel_capacity = 45.0 + player.tank_level * 8.0
	player.fuel = clamp(float(parsed.get("fuel", player.fuel_capacity)), 0.0, player.fuel_capacity)
	player.damage = clamp(float(parsed.get("damage", 0.0)), 0.0, 100.0)
	time_of_day = float(parsed.get("time_of_day", 10.0))

	var p = parsed.get("position", [])
	if p is Array and p.size() == 3:
		player.global_position = Vector3(float(p[0]), max(0.7, float(p[1])), float(p[2]))
	player.rotation.y = float(parsed.get("rotation_y", 0.0))

func _notification(what):
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()

func _panel_style(color, radius):
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.10)
	return style

func _material(color, roughness):
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat
