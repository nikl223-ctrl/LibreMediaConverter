extends Node3D
## Rettungsdienst Simulator Android - standalone, independently implemented.
## This is NOT an EXE converter or a confirmed 1:1 port of the commercial title.
const CITY_SCRIPT = preload("res://scripts/city.gd")
const HUD_SCRIPT = preload("res://scripts/hud.gd")
const SAVE_PATH: String = "user://ambulance_progress.json"
const ORIGINAL_RTW_STEERING_DEGREES: float = 46.0
const MOBILE_WHEELBASE: float = 3.7

var state: String = "menu"
var city
var player: CharacterBody3D
var camera: Camera3D
var chase_camera: bool = true
var hud: Control
var vehicle_visual: Node3D
var marker: Node3D
var marker_light: OmniLight3D
var mission_number: int = 1
var mission_stage: int = 0  # 0 dispatched; 1 treat patient; 2 transport; 3 accomplished
var mission_timer: float = 0.0
var mission_minutes: float = 0.0
var mission_payout: int = 0
var career_rank: int = 1
var career_xp: int = 0
var credits: int = 0
var completed: int = 0
var vehicle_type: int = 0
var steer_axis: float = 0.0
var gas_input: float = 0.0
var brake_input: float = 0.0
var speed: float = 0.0  # signed meters/second
var reverse_gear: bool = false
var lights_on: bool = false
var siren_on: bool = false
var siren_player: AudioStreamPlayer
var engine_player: AudioStreamPlayer
var flash_clock: float = 0.0
var message: String = ""
var message_time: float = 0.0
var mission_positions: Array[Vector3] = [
    Vector3(80.0,0.0,-80.0),
    Vector3(-240.0,0.0,80.0),
    Vector3(160.0,0.0,-160.0),
    Vector3(-160.0,0.0,-240.0),
    Vector3(240.0,0.0,0.0),
    Vector3(-80.0,0.0,240.0),
    Vector3(80.0,0.0,160.0),
    Vector3(-160.0,0.0,0.0)
]
var hospital_position: Vector3 = Vector3(0.0,0.0,-160.0)
var incident_position: Vector3 = Vector3(80.0,0.0,-80.0)
var unit_labels: Array[String] = ["RTW / Rettungswagen","NEF / Notarztwagen","KTW / Krankentransport"]
var incident_labels: Array[String] = [
    "Verkehrsunfall / Person verletzt",
    "Atemnot / Rettung dringend",
    "Sturzverletzung / Sofortversorgung",
    "Bewusstlose Person / Notfall",
    "Medizinischer Notfall / Stadtmitte",
    "Unfall / Patient stabilisieren",
    "Kreislaufkollaps / Notruf 112",
    "Notfalleinsatz / Versorgung"
]
var lights: Array[OmniLight3D] = []
var light_meshes: Array[MeshInstance3D] = []

func _ready() -> void:
    var city_instance = CITY_SCRIPT.new()
    city_instance.name = "OpenCity"
    add_child(city_instance)
    city = city_instance
    city.initialize()
    _build_ambulance()
    _build_camera()
    _build_marker()
    _build_audio()
    _load_progress()
    var layer := CanvasLayer.new()
    layer.name = "MobileHUD"
    add_child(layer)
    var overlay = HUD_SCRIPT.new()
    overlay.game = self
    overlay.name = "MobileControls"
    layer.add_child(overlay)
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hud = overlay
    _position_vehicle()
    _choose_mission()
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _build_ambulance() -> void:
    player = CharacterBody3D.new()
    player.name = "Ambulance"
    player.collision_layer = 1
    player.collision_mask = 1
    player.floor_snap_length = 0.45
    add_child(player)
    var shape := CollisionShape3D.new()
    var body_box := BoxShape3D.new()
    body_box.size = Vector3(1.95,2.5,5.4)
    shape.shape = body_box
    shape.position = Vector3(0,1.35,0)
    player.add_child(shape)
    vehicle_visual = city.create_player_model(player,vehicle_type)
    _make_lights()

func _make_lights() -> void:
    for old in lights:
        if is_instance_valid(old):
            old.queue_free()
    lights.clear()
    light_meshes.clear()
    for side in [-0.44,0.44]:
        var lamp := OmniLight3D.new()
        lamp.position = Vector3(side,3.08,-0.48)
        lamp.light_color = Color("#126bff")
        lamp.light_energy = 3.2
        lamp.omni_range = 13.0
        lamp.shadow_enabled = false
        lamp.visible = false
        vehicle_visual.add_child(lamp)
        lights.append(lamp)

func _build_camera() -> void:
    camera = Camera3D.new()
    camera.name = "ChaseAndCockpitCamera"
    camera.current = true
    camera.fov = 73.0
    camera.near = 0.085
    camera.far = 560.0
    add_child(camera)

func _build_marker() -> void:
    marker = Node3D.new()
    marker.name = "EmergencyGPSWaypoint"
    add_child(marker)
    var ring := MeshInstance3D.new()
    var mesh := TorusMesh.new()
    mesh.inner_radius = 4.5
    mesh.outer_radius = 5.0
    ring.mesh = mesh
    var emit := StandardMaterial3D.new()
    emit.albedo_color = Color("#ffbe37")
    emit.emission_enabled = true
    emit.emission = Color("#fcbe3d")
    emit.emission_energy_multiplier = 1.3
    ring.material_override = emit
    ring.rotation.x = PI / 2.0
    ring.position.y = 0.15
    marker.add_child(ring)
    var shaft := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.10
    cylinder.bottom_radius = 0.10
    cylinder.height = 7.0
    cylinder.radial_segments = 8
    shaft.mesh = cylinder
    shaft.material_override = emit
    shaft.position.y = 4.0
    marker.add_child(shaft)
    var diamond := MeshInstance3D.new()
    var diamond_mesh := SphereMesh.new()
    diamond_mesh.radius = 0.48
    diamond_mesh.height = 1.3
    diamond_mesh.radial_segments = 8
    diamond_mesh.rings = 4
    diamond.mesh = diamond_mesh
    diamond.material_override = emit
    diamond.position.y = 7.4
    marker.add_child(diamond)
    marker_light = OmniLight3D.new()
    marker_light.light_color = Color("#feb34a")
    marker_light.light_energy = 1.2
    marker_light.omni_range = 12.0
    marker_light.position = Vector3(0,3,0)
    marker_light.shadow_enabled = false
    marker.add_child(marker_light)

func _build_audio() -> void:
    siren_player = AudioStreamPlayer.new()
    siren_player.name = "SyntheticWarningSiren"
    siren_player.volume_db = -13
    siren_player.stream = _make_tone(true)
    add_child(siren_player)
    engine_player = AudioStreamPlayer.new()
    engine_player.name = "SyntheticDieselEngine"
    engine_player.volume_db = -24
    engine_player.stream = _make_tone(false)
    add_child(engine_player)

func _make_tone(emergency: bool) -> AudioStreamWAV:
    var rate: int = 22050
    var count: int = int(float(rate) * (4.0 if emergency else 2.0))
    var pcm := PackedByteArray()
    pcm.resize(count * 2)
    var phase: float = 0.0
    for i in range(count):
        var t: float = float(i) / float(rate)
        var frequency: float = 620.0 + 185.0 * sin(t * PI * 0.5) if emergency else (87.0 + 6.0 * sin(t * PI * 2.0))
        phase += TAU * frequency / float(rate)
        var tone: float = sin(phase) * 0.54 + sin(phase * 0.52) * 0.24
        if not emergency:
            tone += sin(phase * 2.8) * 0.14
        var value: int = int(clampf(tone * 17500.0,-31000,31000))
        if value < 0:
            value += 65536
        pcm[2*i] = value & 255
        pcm[2*i+1] = (value >> 8) & 255
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = rate
    stream.stereo = false
    stream.data = pcm
    stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin = 0
    stream.loop_end = count
    return stream

func _position_vehicle() -> void:
    player.global_position = Vector3(160.0,0.18,161.0)
    player.rotation = Vector3.ZERO
    player.velocity = Vector3.ZERO
    speed = 0.0
    steer_axis = 0.0
    gas_input = 0.0
    brake_input = 0.0

func _choose_mission() -> void:
    var idx: int = (mission_number-1) % mission_positions.size()
    incident_position = mission_positions[idx]
    mission_stage = 0
    mission_minutes = 0.0
    mission_payout = 0
    message = "LEITSTELLE: " + incident_labels[idx]
    message_time = 7.5
    _update_target()

func _update_target() -> void:
    if marker == null:
        return
    var goal: Vector3 = hospital_position if mission_stage >= 2 else incident_position
    marker.position = goal + Vector3(0.0,0.07,0.0)
    marker.visible = mission_stage != 3

func start_simulation(unit: int = 0) -> void:
    if state == "playing":
        return
    vehicle_type = clampi(unit,0,2)
    state = "playing"
    if is_instance_valid(vehicle_visual):
        vehicle_visual.queue_free()
    vehicle_visual = city.create_player_model(player,vehicle_type)
    _make_lights()
    _position_vehicle()
    mission_stage = 0
    _choose_mission()
    engine_player.play()

func _load_progress() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var f := FileAccess.open(SAVE_PATH,FileAccess.READ)
    if f == null:
        return
    var v: Variant = JSON.parse_string(f.get_as_text())
    if typeof(v) != TYPE_DICTIONARY:
        return
    credits = maxi(0,int(v.get("credits",0)))
    completed = maxi(0,int(v.get("completed",0)))
    career_xp = maxi(0,int(v.get("xp",0)))
    career_rank = clampi(int(v.get("rank",1)),1,99)
    mission_number = maxi(1,int(v.get("mission_number",1)))

func _save_progress() -> void:
    var f := FileAccess.open(SAVE_PATH,FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify({
            "mission_number":mission_number,
            "credits":credits,
            "completed":completed,
            "rank":career_rank,
            "xp":career_xp
        }))

func active_target() -> Vector3:
    return hospital_position if mission_stage >= 2 else incident_position

func objective_distance() -> int:
    var goal: Vector3 = active_target()
    var delta: Vector3 = goal - player.global_position
    delta.y = 0
    return int(delta.length())

func mission_title() -> String:
    var idx: int = (mission_number-1) % incident_labels.size()
    if mission_stage == 0:
        return "EINSATZ %02d  //  %s" % [mission_number,incident_labels[idx]]
    if mission_stage == 1:
        return "PATIENT VERSORGEN  //  SICHERE DEN EINSATZORT"
    if mission_stage == 2:
        return "PATIENT AN BORD  //  ZUR KLINIK FAHREN"
    return "EINSATZ ERFOLGREICH  //  +%d EUR" % mission_payout

func trigger_treatment() -> void:
    if state != "playing" or mission_stage != 1:
        return
    if absf(speed) > 2.4:
        message = "Fahrzeug erst anhalten!"
        message_time = 2.1
        return
    mission_stage = 4
    mission_timer = 3.6
    message = "Team versorgt den Patienten ... "
    message_time = 3.6

func toggle_siren() -> void:
    siren_on = not siren_on
    if siren_on:
        siren_player.play()
    else:
        siren_player.stop()

func toggle_lights() -> void:
    lights_on = not lights_on
    flash_clock = 0.0
    if not lights_on:
        for light in lights:
            light.visible = false

func toggle_camera() -> void:
    chase_camera = not chase_camera

func toggle_reverse() -> void:
    reverse_gear = not reverse_gear
    message = "RUECKWAERTSGANG" if reverse_gear else "VORWAERTSGANG"
    message_time = 1.4

func _physics_process(delta: float) -> void:
    if state != "playing":
        return
    var acceleration: float = 9.3
    var max_speed: float = 29.0 if vehicle_type == 1 else (25.0 if vehicle_type == 0 else 22.0)
    var kb_gas: float = 1.0 if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) else 0.0
    var kb_brake: float = 1.0 if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) else 0.0
    var kb_steer: float = (1.0 if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) else 0.0)
    var throttle: float = maxf(kb_gas,gas_input)
    var brake: float = maxf(kb_brake,brake_input)
    var desired_direction: float = -1.0 if reverse_gear else 1.0
    if throttle > 0.0:
        speed = move_toward(speed,max_speed*desired_direction,acceleration*throttle*delta)
    elif absf(speed) > 0.0:
        speed = move_toward(speed,0.0,3.2*delta)
    if brake > 0.0:
        speed = move_toward(speed,0.0,23.0*brake*delta)
    var steering: float = clampf(steer_axis+kb_steer,-1.0,1.0)
    if absf(speed)>0.12:
        # Bicycle steering: initial 46-degree limit comes from the original
        # user-provided vehicles/rtw.xvd; platform units are reinterpreted.
        var max_angle: float = deg_to_rad(ORIGINAL_RTW_STEERING_DEGREES)
        var steer_fade: float = 1.0 + absf(speed)*0.105
        var wheel_angle: float = steering*max_angle/steer_fade
        var yaw_rate: float = speed*tan(wheel_angle)/MOBILE_WHEELBASE
        player.rotation.y -= yaw_rate*delta
    var front: Vector3 = -player.global_transform.basis.z
    player.velocity = front*speed
    player.velocity.y = -0.7 if player.is_on_floor() else player.velocity.y - 15.0*delta
    player.move_and_slide()
    if player.get_slide_collision_count()>0:
        speed *= 0.86
    city.advance_traffic(delta,player)
    _tick_mission(delta)

func _process(delta: float) -> void:
    if state != "playing":
        return
    flash_clock += delta
    message_time = maxf(0.0,message_time-delta)
    if siren_on and not siren_player.playing:
        siren_player.play()
    engine_player.pitch_scale = clampf(0.77+absf(speed)*0.018,0.72,1.55)
    _tick_lightbar()
    _position_camera(delta)
    if marker.visible:
        marker.rotate_y(delta*0.73)

func _tick_lightbar() -> void:
    if not lights_on:
        return
    for i in range(lights.size()):
        lights[i].visible = (int(flash_clock*7.0) % 2)==i
    for i in range(light_meshes.size()):
        light_meshes[i].visible = (int(flash_clock*7.0) % 2)==i

func _position_camera(delta: float) -> void:
    if chase_camera:
        var offset: Vector3 = player.global_transform.basis.z*11.4+Vector3.UP*6.4
        var desired: Vector3 = player.global_position+offset
        camera.global_position = camera.global_position.lerp(desired,clampf(delta*6.4,0,1))
        camera.look_at(player.global_position+Vector3.UP*1.7)
        camera.fov = 74
    else:
        var seat: Vector3 = player.global_position+player.global_transform.basis*Vector3(-0.43,2.28,-0.9)
        camera.global_position = camera.global_position.lerp(seat,clampf(delta*12.0,0,1))
        camera.global_basis = camera.global_basis.slerp(player.global_transform.basis,clampf(delta*9.0,0,1))
        camera.fov = 76

func _tick_mission(delta: float) -> void:
    mission_minutes += delta/60.0
    if mission_stage == 0:
        if objective_distance()<13 and absf(speed)<2.8:
            mission_stage = 1
            message = "Ankunft am Einsatzort! Tippe VERSORGEN."
            message_time = 5.0
    elif mission_stage == 4:
        mission_timer -= delta
        if mission_timer<=0.0:
            mission_stage = 2
            message = "Patient transportfaehig. Fahrt zur Klinik."
            message_time = 5.0
            _update_target()
    elif mission_stage == 2:
        if objective_distance()<16 and absf(speed)<3.0:
            mission_stage = 3
            mission_payout = maxi(160,1200-int(mission_minutes*55.0))
            credits += mission_payout
            career_xp += 200
            completed += 1
            if career_xp >= career_rank*500:
                career_xp = 0
                career_rank += 1
            _save_progress()
            mission_timer = 4.4
            message = "PATIENT GERETTET! +%d EUR" % mission_payout
            message_time = 4.4
            _update_target()
    elif mission_stage == 3:
        mission_timer -= delta
        if mission_timer<=0.0:
            mission_number += 1
            _choose_mission()
            _save_progress()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_B: toggle_lights()
            KEY_H: toggle_siren()
            KEY_C: toggle_camera()
            KEY_R: toggle_reverse()
            KEY_T: trigger_treatment()
            KEY_ENTER:
                if state == "menu":
                    start_simulation(0)
