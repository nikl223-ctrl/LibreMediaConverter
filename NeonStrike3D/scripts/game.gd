extends Node3D
## NEON STRIKE 3D - no purchased assets; all level art is generated in code.
## Fast low-poly geometry and the Compatibility renderer target mid/high-end Android phones.

const HUD_SCRIPT = preload("res://scripts/hud.gd")
const ARENA_HALF: float = 43.0
const PLAYER_SPEED: float = 9.0
const SHOT_INTERVAL: float = 0.115

var state: String = "menu"
var wave: int = 0
var score: int = 0
var kills: int = 0
var health: float = 100.0
var max_health: float = 100.0
var ammo: int = 32
var reserve_ammo: int = 999
var magazine_size: int = 32
var reload_timer: float = 0.0
var shoot_timer: float = 0.0
var dash_cooldown: float = 0.0
var dash_time: float = 0.0
var elapsed: float = 0.0
var flash_time: float = 0.0
var wave_wait: float = -1.0
var remaining_spawns: int = 0
var spawn_timer: float = 0.0
var status_text: String = ""
var status_timer: float = 0.0
var kills_this_wave: int = 0

var move_axis: Vector2 = Vector2.ZERO
var trigger_down: bool = false
var enemies: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var materials: Dictionary = {}
var player: CharacterBody3D
var camera: Camera3D
var gun_holder: Node3D
var muzzle_light: OmniLight3D
var hud: Control
var sounds: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _ready() -> void:
    rng.randomize()
    _build_materials()
    _build_atmosphere()
    _build_arena()
    _build_player()
    _build_audio()
    var overlay := CanvasLayer.new()
    overlay.name = "Interface"
    add_child(overlay)
    hud = HUD_SCRIPT.new()
    hud.game = self
    overlay.add_child(hud)
    hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _build_materials() -> void:
    materials["floor"] = _mat(Color("#122234"), 0.34, 0.68)
    materials["tile"] = _mat(Color("#162e43"), 0.54, 0.48)
    materials["steel"] = _mat(Color("#223b52"), 0.67, 0.32)
    materials["dark"] = _mat(Color("#091522"), 0.45, 0.43)
    materials["cyan"] = _glow(Color("#37e7ff"), 2.4)
    materials["blue"] = _glow(Color("#446dff"), 2.0)
    materials["pink"] = _glow(Color("#ff3d92"), 2.6)
    materials["gold"] = _glow(Color("#ffcc62"), 2.5)
    materials["green"] = _glow(Color("#64ffa6"), 2.1)
    materials["white"] = _glow(Color("#ddfaff"), 1.7)
    materials["enemy"] = _mat(Color("#572640"), 0.4, 0.34)
    materials["brute"] = _mat(Color("#5b3f28"), 0.48, 0.36)

func _mat(tint: Color, metallic_value: float = 0.0, roughness_value: float = 0.6) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = tint
    m.metallic = metallic_value
    m.roughness = roughness_value
    return m

func _glow(tint: Color, intensity: float) -> StandardMaterial3D:
    var m := _mat(tint, 0.18, 0.28)
    m.emission_enabled = true
    m.emission = tint
    m.emission_energy_multiplier = intensity
    return m

func _box(parent: Node3D, location: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
    var item := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    item.mesh = mesh
    item.material_override = material
    item.position = location
    parent.add_child(item)
    return item

func _sphere(parent: Node3D, location: Vector3, radius: float, material: Material) -> MeshInstance3D:
    var item := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 12
    mesh.rings = 6
    item.mesh = mesh
    item.material_override = material
    item.position = location
    parent.add_child(item)
    return item

func _cylinder(parent: Node3D, location: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
    var item := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 10
    item.mesh = mesh
    item.material_override = material
    item.position = location
    parent.add_child(item)
    return item

func _solid_box(location: Vector3, dimensions: Vector3, material: Material) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.position = location
    add_child(body)
    _box(body, Vector3.ZERO, dimensions, material)
    var shape := CollisionShape3D.new()
    var box_shape := BoxShape3D.new()
    box_shape.size = dimensions
    shape.shape = box_shape
    body.add_child(shape)
    return body

func _build_atmosphere() -> void:
    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var procedural := ProceduralSkyMaterial.new()
    procedural.sky_top_color = Color("#060d20")
    procedural.sky_horizon_color = Color("#233355")
    procedural.ground_bottom_color = Color("#091421")
    procedural.ground_horizon_color = Color("#203045")
    procedural.sun_angle_max = 8.0
    sky.sky_material = procedural
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.43
    env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color("#1a3053")
    env.fog_density = 0.008
    world.environment = env
    add_child(world)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-56.0, 28.0, 0.0)
    sun.light_color = Color("#8aafff")
    sun.light_energy = 0.9
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 90.0
    add_child(sun)

    for i in range(4):
        var lamp := OmniLight3D.new()
        lamp.position = Vector3((-30.0 if i % 2 == 0 else 30.0), 7.0, (-30.0 if i < 2 else 30.0))
        lamp.light_color = Color("#23ddff") if i % 2 == 0 else Color("#fa408d")
        lamp.light_energy = 2.1
        lamp.omni_range = 19.0
        lamp.shadow_enabled = false
        add_child(lamp)

func _build_arena() -> void:
    _solid_box(Vector3(0.0, -0.65, 0.0), Vector3(92.0, 1.3, 92.0), materials["floor"])
    # Tile highlights and an emissive floor grid.
    for x in range(-5, 6):
        for z in range(-5, 6):
            if (x + z) % 2 == 0:
                _box(self, Vector3(float(x) * 8.0, 0.017, float(z) * 8.0), Vector3(7.7, 0.025, 7.7), materials["tile"])
    for v in range(-5, 6):
        _box(self, Vector3(float(v) * 8.0, 0.045, 0.0), Vector3(0.07, 0.02, 88.0), materials["cyan"] if v % 2 == 0 else materials["blue"])
        _box(self, Vector3(0.0, 0.045, float(v) * 8.0), Vector3(88.0, 0.02, 0.07), materials["cyan"] if v % 2 == 0 else materials["blue"])

    _solid_box(Vector3(-46.0, 5.0, 0.0), Vector3(2.0, 10.0, 94.0), materials["dark"])
    _solid_box(Vector3(46.0, 5.0, 0.0), Vector3(2.0, 10.0, 94.0), materials["dark"])
    _solid_box(Vector3(0.0, 5.0, -46.0), Vector3(94.0, 10.0, 2.0), materials["dark"])
    _solid_box(Vector3(0.0, 5.0, 46.0), Vector3(94.0, 10.0, 2.0), materials["dark"])
    for edge in [-44.5, 44.5]:
        _box(self, Vector3(edge, 8.0, 0.0), Vector3(0.24, 0.25, 89.0), materials["pink"])
        _box(self, Vector3(0.0, 8.0, edge), Vector3(89.0, 0.25, 0.24), materials["cyan"])

    for a in range(12):
        var theta := TAU * float(a) / 12.0
        var px := cos(theta) * 36.0
        var pz := sin(theta) * 36.0
        var p_height := 6.0 + float(a % 3) * 3.0
        _box(self, Vector3(px, p_height * 0.5, pz), Vector3(3.0, p_height, 3.0), materials["steel"])
        _box(self, Vector3(px, p_height + 0.15, pz), Vector3(3.3, 0.25, 3.3), materials["cyan"] if a % 2 == 0 else materials["pink"])
        _box(self, Vector3(px, 2.0, pz), Vector3(3.1, 0.10, 3.1), materials["blue"])

    for i in range(14):
        var angle := TAU * float(i) / 14.0 + 0.17
        var radius := 19.0 + float(i % 3) * 3.0
        var px := cos(angle) * radius
        var pz := sin(angle) * radius
        var size := Vector3(3.0 + float(i % 2), 2.0 + float(i % 3), 2.5)
        _solid_box(Vector3(px, size.y * 0.5, pz), size, materials["steel"])
        _box(self, Vector3(px, size.y + 0.035, pz), Vector3(size.x + 0.16, 0.09, size.z + 0.16), materials["pink"] if i % 3 == 0 else materials["cyan"])

    _cylinder(self, Vector3(0.0, 0.08, 0.0), 5.7, 0.15, materials["dark"])
    var center_ring := MeshInstance3D.new()
    var ring_mesh := TorusMesh.new()
    ring_mesh.inner_radius = 4.7
    ring_mesh.outer_radius = 5.1
    center_ring.mesh = ring_mesh
    center_ring.material_override = materials["cyan"]
    center_ring.position = Vector3(0.0, 0.18, 0.0)
    add_child(center_ring)

func _build_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0.0, 1.1, 0.0)
    player.floor_snap_length = 0.28
    add_child(player)
    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.44
    capsule.height = 2.12
    collision.shape = capsule
    player.add_child(collision)

    camera = Camera3D.new()
    camera.name = "FirstPersonCamera"
    camera.position = Vector3(0.0, 0.58, 0.0)
    camera.fov = 77.0
    camera.near = 0.06
    camera.current = true
    player.add_child(camera)

    gun_holder = Node3D.new()
    gun_holder.position = Vector3(0.43, -0.39, -0.79)
    camera.add_child(gun_holder)
    _box(gun_holder, Vector3(0.0, -0.03, -0.18), Vector3(0.27, 0.23, 0.57), materials["dark"])
    _box(gun_holder, Vector3(0.0, 0.055, -0.18), Vector3(0.29, 0.09, 0.59), materials["steel"])
    _box(gun_holder, Vector3(0.0, 0.11, -0.20), Vector3(0.13, 0.025, 0.32), materials["cyan"])
    _box(gun_holder, Vector3(0.0, -0.24, 0.035), Vector3(0.15, 0.30, 0.18), materials["steel"])
    _box(gun_holder, Vector3(0.0, -0.19, -0.23), Vector3(0.16, 0.21, 0.21), materials["blue"])
    _cylinder(gun_holder, Vector3(0.0, 0.01, -0.52), 0.095, 0.40, materials["steel"]).rotation_degrees.x = 90.0
    _cylinder(gun_holder, Vector3(0.0, 0.01, -0.70), 0.07, 0.12, materials["cyan"]).rotation_degrees.x = 90.0
    _box(gun_holder, Vector3(-0.16, 0.01, -0.16), Vector3(0.05, 0.075, 0.35), materials["cyan"])
    _box(gun_holder, Vector3(0.16, 0.01, -0.16), Vector3(0.05, 0.075, 0.35), materials["pink"])

    muzzle_light = OmniLight3D.new()
    muzzle_light.light_color = Color("#5deaff")
    muzzle_light.light_energy = 3.8
    muzzle_light.omni_range = 5.0
    muzzle_light.position = Vector3(0.0, 0.02, -0.85)
    muzzle_light.visible = false
    gun_holder.add_child(muzzle_light)

func _build_audio() -> void:
    _make_sound("shot", 0.10, 170.0, -13.0)
    _make_sound("hit", 0.13, 94.0, -16.0)
    _make_sound("blast", 0.36, 69.0, -10.0)
    _make_sound("pickup", 0.19, 580.0, -11.0)

func _make_sound(key: String, duration: float, hz: float, volume: float) -> void:
    var rate := 22050
    var count := int(duration * float(rate))
    var bytes := PackedByteArray()
    bytes.resize(count * 2)
    for i in range(count):
        var t := float(i) / float(rate)
        var falloff := pow(maxf(0.0, 1.0 - t / duration), 2.0)
        var frequency := hz * (1.0 + 2.5 * t / duration)
        var wave_value := sin(TAU * frequency * t) * 0.5 + rng.randf_range(-0.4, 0.4)
        if key == "pickup":
            wave_value = sin(TAU * (hz + 550.0 * t / duration) * t) * 0.62
        var value := int(clampf(wave_value * falloff * 25000.0, -32767.0, 32767.0))
        if value < 0:
            value += 65536
        bytes[i * 2] = value & 255
        bytes[i * 2 + 1] = (value >> 8) & 255
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = rate
    stream.stereo = false
    stream.data = bytes
    var sound := AudioStreamPlayer.new()
    sound.stream = stream
    sound.volume_db = volume
    add_child(sound)
    sounds[key] = sound

func _sound(key: String) -> void:
    if sounds.has(key):
        var sound: AudioStreamPlayer = sounds[key]
        sound.play()

func begin_game() -> void:
    if state == "playing":
        return
    _reset_game()
    state = "playing"
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if not OS.has_feature("mobile") else Input.MOUSE_MODE_VISIBLE)
    _start_wave()

func _reset_game() -> void:
    for e in enemies:
        if is_instance_valid(e["body"]):
            e["body"].queue_free()
    enemies.clear()
    for e in effects:
        if is_instance_valid(e["node"]):
            e["node"].queue_free()
    effects.clear()
    for p in pickups:
        if is_instance_valid(p["node"]):
            p["node"].queue_free()
    pickups.clear()
    wave = 0
    score = 0
    kills = 0
    health = 100.0
    ammo = magazine_size
    reload_timer = 0.0
    shoot_timer = 0.0
    dash_cooldown = 0.0
    remaining_spawns = 0
    spawn_timer = 0.0
    wave_wait = -1.0
    move_axis = Vector2.ZERO
    trigger_down = false
    player.position = Vector3(0.0, 1.1, 0.0)
    player.rotation = Vector3.ZERO
    camera.rotation = Vector3.ZERO
    player.velocity = Vector3.ZERO

func _start_wave() -> void:
    wave += 1
    kills_this_wave = 0
    remaining_spawns = mini(22, 4 + wave * 2)
    spawn_timer = 0.8
    wave_wait = -1.0
    status_text = "WELLE %02d   //   ZIELE ELIMINIEREN" % wave
    status_timer = 2.8

func _physics_process(delta: float) -> void:
    if state != "playing":
        return
    elapsed += delta
    shoot_timer = maxf(0.0, shoot_timer - delta)
    dash_cooldown = maxf(0.0, dash_cooldown - delta)
    flash_time = maxf(0.0, flash_time - delta)
    status_timer = maxf(0.0, status_timer - delta)

    if reload_timer > 0.0:
        reload_timer -= delta
        if reload_timer <= 0.0:
            ammo = magazine_size
            status_text = "NACHGELADEN"
            status_timer = 0.7

    _move_player(delta)
    _tick_enemies(delta)
    _tick_pickups(delta)

    if remaining_spawns > 0:
        spawn_timer -= delta
        if spawn_timer <= 0.0 and enemies.size() < 17:
            _spawn_enemy()
            remaining_spawns -= 1
            spawn_timer = maxf(0.26, 0.88 - float(wave) * 0.045)

    if remaining_spawns == 0 and enemies.is_empty() and wave_wait < 0.0:
        wave_wait = 3.4
        score += 150 * wave
        health = minf(max_health, health + 14.0)
        status_text = "ARENA GESICHERT   +%d" % (150 * wave)
        status_timer = 3.0

    if wave_wait > 0.0:
        wave_wait -= delta
        if wave_wait <= 0.0:
            _start_wave()

    if (trigger_down or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) and shoot_timer <= 0.0:
        fire()

func _move_player(delta: float) -> void:
    var key_input := Vector2.ZERO
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        key_input.x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        key_input.x += 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        key_input.y -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        key_input.y += 1.0
    var stick := (move_axis + key_input).limit_length(1.0)
    var desired := (player.global_transform.basis.x * stick.x + player.global_transform.basis.z * stick.y) * PLAYER_SPEED
    if dash_time > 0.0:
        dash_time -= delta
        desired = -player.global_transform.basis.z * 24.0
    player.velocity.x = move_toward(player.velocity.x, desired.x, delta * 68.0)
    player.velocity.z = move_toward(player.velocity.z, desired.z, delta * 68.0)
    if not player.is_on_floor():
        player.velocity.y -= 26.0 * delta
    else:
        player.velocity.y = -0.4
    player.move_and_slide()
    var sway := sin(elapsed * 12.0) * 0.015 * minf(1.0, stick.length())
    var desired_y := -0.39 + sway - (0.09 if shoot_timer > SHOT_INTERVAL * 0.55 else 0.0)
    gun_holder.position.y = lerpf(gun_holder.position.y, desired_y, delta * 17.0)
    muzzle_light.visible = shoot_timer > SHOT_INTERVAL * 0.72

func rotate_view(movement: Vector2) -> void:
    if state != "playing":
        return
    player.rotation.y -= movement.x * 0.0034
    camera.rotation.x = clampf(camera.rotation.x - movement.y * 0.0034, -1.20, 1.17)

func request_dash() -> void:
    if state == "playing" and dash_cooldown <= 0.0:
        dash_cooldown = 5.0
        dash_time = 0.24
        status_text = "BOOST AKTIV"
        status_timer = 0.8

func start_reload() -> void:
    if state == "playing" and reload_timer <= 0.0 and ammo < magazine_size:
        reload_timer = 1.35
        status_text = "NACHLADEN ..."
        status_timer = 1.2

func fire() -> void:
    if state != "playing" or reload_timer > 0.0 or shoot_timer > 0.0:
        return
    if ammo <= 0:
        start_reload()
        return
    shoot_timer = SHOT_INTERVAL
    ammo -= 1
    _sound("shot")
    camera.rotation.z = rng.randf_range(-0.005, 0.005)
    var from := camera.global_position
    var toward := -camera.global_transform.basis.z
    var end := from + toward * 110.0
    var query := PhysicsRayQueryParameters3D.create(from, end)
    query.exclude = [player.get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    var impact := end
    if not hit.is_empty():
        impact = hit["position"]
        var collider: Object = hit["collider"]
        for e in enemies:
            if e["body"] == collider:
                _damage_enemy(e, 36.0, impact)
                break
    _laser(from + camera.global_transform.basis.x * 0.24 - camera.global_transform.basis.y * 0.22, impact)
    if not hit.is_empty():
        _impact(impact, materials["cyan"])
    if ammo == 0:
        start_reload()

func _laser(origin: Vector3, target: Vector3) -> void:
    var diff := target - origin
    if diff.length() < 0.05:
        return
    var laser := _cylinder(self, (origin + target) * 0.5, 0.036, diff.length(), materials["cyan"])
    laser.quaternion = Quaternion(Vector3.UP, diff.normalized())
    effects.append({"node": laser, "life": 0.10, "max_life": 0.10, "kind": "beam"})

func _impact(location: Vector3, material: Material) -> void:
    var hit := _sphere(self, location, 0.20, material)
    effects.append({"node": hit, "life": 0.18, "max_life": 0.18, "kind": "pulse"})

func _blast(location: Vector3, is_brute: bool) -> void:
    for i in range(7):
        var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
        var fragment := _box(self, location, Vector3(0.17, 0.17, 0.17), materials["gold"] if is_brute else materials["pink"])
        effects.append({"node": fragment, "life": 0.55, "max_life": 0.55, "kind": "fragment", "velocity": direction * rng.randf_range(4.0, 12.0)})
    _sound("blast")

func _spawn_enemy() -> void:
    var angle := rng.randf_range(0.0, TAU)
    var radius := rng.randf_range(21.0, 37.0)
    var is_brute := wave >= 3 and rng.randf() < minf(0.36, float(wave) * 0.045)
    var unit := CharacterBody3D.new()
    unit.name = "Brute" if is_brute else "Sentinel"
    unit.collision_layer = 2
    unit.collision_mask = 1
    unit.floor_snap_length = 0.35
    unit.position = Vector3(cos(angle) * radius, 1.24 if is_brute else 1.08, sin(angle) * radius)
    add_child(unit)
    var hitbox := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.height = 2.35 if is_brute else 1.85
    capsule.radius = 0.75 if is_brute else 0.51
    hitbox.shape = capsule
    unit.add_child(hitbox)

    var visual := Node3D.new()
    visual.name = "Visual"
    unit.add_child(visual)
    var armor: Material = materials["brute"] if is_brute else materials["enemy"]
    var glow: Material = materials["gold"] if is_brute else materials["pink"]
    var scale_factor := 1.35 if is_brute else 1.0
    _cylinder(visual, Vector3(0.0, 0.0, 0.0), 0.52 * scale_factor, 0.88 * scale_factor, armor)
    _sphere(visual, Vector3(0.0, 0.54 * scale_factor, 0.0), 0.40 * scale_factor, materials["dark"])
    _box(visual, Vector3(0.0, 0.55 * scale_factor, -0.32 * scale_factor), Vector3(0.51 * scale_factor, 0.15, 0.10), glow)
    _box(visual, Vector3(-0.55 * scale_factor, 0.05, 0.0), Vector3(0.27, 0.57 * scale_factor, 0.40), armor)
    _box(visual, Vector3(0.55 * scale_factor, 0.05, 0.0), Vector3(0.27, 0.57 * scale_factor, 0.40), armor)
    _cylinder(visual, Vector3(0.0, -0.48 * scale_factor, 0.0), 0.37 * scale_factor, 0.09, glow)
    _sphere(visual, Vector3(0.0, 0.0, -0.52 * scale_factor), 0.20, glow)
    enemies.append({
        "body": unit,
        "visual": visual,
        "health": 165.0 + float(wave) * 9.0 if is_brute else 78.0 + float(wave) * 4.0,
        "speed": 3.2 + float(wave) * 0.15 if is_brute else 4.3 + float(wave) * 0.19,
        "attack": 0.9,
        "damage": 22.0 if is_brute else 10.0,
        "phase": rng.randf_range(0.0, TAU),
        "brute": is_brute
    })

func _tick_enemies(delta: float) -> void:
    for e in enemies:
        var unit: CharacterBody3D = e["body"]
        if not is_instance_valid(unit):
            continue
        var to_player := player.global_position - unit.global_position
        to_player.y = 0.0
        var distance := to_player.length()
        if distance > 0.001:
            unit.look_at(Vector3(player.global_position.x, unit.global_position.y, player.global_position.z), Vector3.UP)
        if distance > 1.65:
            var velocity := to_player.normalized() * float(e["speed"])
            unit.velocity.x = velocity.x
            unit.velocity.z = velocity.z
        else:
            unit.velocity.x = move_toward(unit.velocity.x, 0.0, delta * 20.0)
            unit.velocity.z = move_toward(unit.velocity.z, 0.0, delta * 20.0)
        if not unit.is_on_floor():
            unit.velocity.y -= 26.0 * delta
        else:
            unit.velocity.y = -0.4
        unit.move_and_slide()
        var visual: Node3D = e["visual"]
        visual.position.y = sin(elapsed * 5.2 + float(e["phase"])) * 0.07
        e["attack"] = float(e["attack"]) - delta
        if distance < 2.0 and float(e["attack"]) <= 0.0:
            e["attack"] = 1.1 if bool(e["brute"]) else 0.85
            _hurt_player(float(e["damage"]))

func _hurt_player(damage: float) -> void:
    if state != "playing":
        return
    health = maxf(0.0, health - damage)
    flash_time = 0.26
    _sound("hit")
    if health <= 0.0:
        state = "dead"
        trigger_down = false
        move_axis = Vector2.ZERO
        status_text = "MISSION GESCHEITERT"
        status_timer = 15.0
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _damage_enemy(e: Dictionary, damage: float, impact: Vector3) -> void:
    e["health"] = float(e["health"]) - damage
    _impact(impact, materials["gold"])
    if float(e["health"]) > 0.0:
        return
    var unit: CharacterBody3D = e["body"]
    var location := unit.global_position
    var is_brute: bool = e["brute"]
    _blast(location, is_brute)
    unit.queue_free()
    enemies.erase(e)
    kills += 1
    kills_this_wave += 1
    score += 220 if is_brute else 100
    if kills % 6 == 0:
        _spawn_pickup(location)

func _spawn_pickup(location: Vector3) -> void:
    var root := Node3D.new()
    root.position = Vector3(location.x, 1.15, location.z)
    add_child(root)
    _cylinder(root, Vector3.ZERO, 0.46, 0.17, materials["dark"])
    _sphere(root, Vector3(0.0, 0.16, 0.0), 0.31, materials["green"])
    _box(root, Vector3(0.0, 0.17, -0.32), Vector3(0.11, 0.44, 0.06), materials["white"])
    _box(root, Vector3(0.0, 0.17, -0.32), Vector3(0.44, 0.11, 0.06), materials["white"])
    pickups.append({"node": root, "phase": rng.randf_range(0.0, TAU)})

func _tick_pickups(_delta: float) -> void:
    for i in range(pickups.size() - 1, -1, -1):
        var pickup: Dictionary = pickups[i]
        var root: Node3D = pickup["node"]
        root.rotation.y += 0.025
        root.position.y = 1.15 + sin(elapsed * 3.0 + float(pickup["phase"])) * 0.2
        if root.global_position.distance_to(player.global_position) < 1.8:
            health = minf(max_health, health + 30.0)
            status_text = "+30 ENERGIE"
            status_timer = 1.5
            _sound("pickup")
            root.queue_free()
            pickups.remove_at(i)

func _process(delta: float) -> void:
    camera.rotation.z = lerpf(camera.rotation.z, 0.0, delta * 9.0)
    for i in range(effects.size() - 1, -1, -1):
        var effect: Dictionary = effects[i]
        var node: MeshInstance3D = effect["node"]
        if not is_instance_valid(node):
            effects.remove_at(i)
            continue
        effect["life"] = float(effect["life"]) - delta
        if float(effect["life"]) <= 0.0:
            node.queue_free()
            effects.remove_at(i)
            continue
        var ratio := float(effect["life"]) / float(effect["max_life"])
        if effect["kind"] == "pulse":
            node.scale = Vector3.ONE * (1.0 + 2.6 * (1.0 - ratio))
        elif effect["kind"] == "beam":
            node.scale.x = ratio
            node.scale.z = ratio
        elif effect["kind"] == "fragment":
            node.position += effect["velocity"] * delta
            node.rotate_x(delta * 9.0)
            node.rotate_y(delta * 8.0)
            node.scale = Vector3.ONE * ratio
            effect["velocity"] = effect["velocity"] * (1.0 - delta * 2.8)

func toggle_pause() -> void:
    if state == "playing":
        state = "paused"
        trigger_down = false
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    elif state == "paused":
        state = "playing"
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if not OS.has_feature("mobile") else Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and state == "playing" and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        rotate_view(event.relative)
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            toggle_pause()
        elif event.keycode == KEY_R:
            if state == "playing":
                start_reload()
            elif state == "dead" or state == "menu":
                begin_game()
        elif event.keycode == KEY_SPACE:
            request_dash()
    elif event is InputEventMouseButton and event.pressed:
        if state == "menu" or state == "dead":
            begin_game()
        elif state == "paused":
            toggle_pause()
