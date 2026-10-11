extends Node3D
## Story-driven RPG layer: companion AI, quest stages, exploration and persistent progression.
## All geometry is original and generated at runtime.

const CAMP := Vector3(-18.0, 0.0, 6.0)
const BRIDGE := Vector3(-16.0, 0.0, -118.0)
const RUINS := Vector3(-66.0, 0.0, -218.0)
const RELIC := Vector3(-73.0, 0.0, -232.0)
const SAVE_PATH := "user://riverlands_rpg.json"

var game
var stage: int = 0
var level: int = 1
var experience: int = 0
var next_level_xp: int = 500
var combat_kills: int = 0
var map_visible: bool = false
var talking: String = ""
var talk_timer: float = 0.0
var auto_save_timer: float = 10.0
var restored: bool = false
var allies: Array[Dictionary] = []
var placemarkers: Array[Node3D] = []
var gate_crystal: Node3D
var relic_object: Node3D
var rng := RandomNumberGenerator.new()

func initialize(host: Node3D) -> void:
    game = host
    rng.seed = 31622
    _create_locations()
    _make_allies()

func start_adventure() -> void:
    stage = 0
    combat_kills = 0
    talking = ""
    talk_timer = 0.0
    map_visible = false
    if not restored:
        _load()
        restored = true
    for a in allies:
        a["health"] = 100.0
        a["shot_cd"] = float(a["id"]) * 0.31 + 0.5
        var body: CharacterBody3D = a["body"]
        body.global_position = game.player.global_position + Vector3(-2.0 - float(a["id"]) * 2.0, 0.0, 2.5)
    if stage == 0:
        _speak("MIRA", "Unser Dorf verliert das Licht. Wir muessen die alte Bruecke erreichen!", 6.5)
    elif stage == 1:
        _prepare_ambush()
    else:
        _speak("KAEL", "Wir setzen unsere Suche fort. Ich halte dir den Ruecken frei.", 5.0)
    _update_markers()

func quest_title() -> String:
    match stage:
        0: return "01  EIN NEUER HORIZONT"
        1: return "02  HINTERHALT AN DER BRUECKE"
        2: return "03  DER WEG ZUM ALTEN TURM"
        3: return "04  DAS VERLORENE LICHT"
        4: return "05  HEIMKEHR"
        _: return "GESCHICHTE ABGESCHLOSSEN"

func quest_description() -> String:
    match stage:
        0: return "Erreiche mit deinen Begleitern die alte Bruecke"
        1: return "Verteidige die Bruecke  %d / 6" % mini(combat_kills, 6)
        2: return "Erkunde die Ruinen im Nordtal"
        3: return "Sichere den Lichtkern am Turm"
        4: return "Bringe den Lichtkern zurueck ins Waldlager"
        _: return "Erkunde die Welt und beschuetze das Tal"

func objective() -> Vector3:
    match stage:
        0, 1: return BRIDGE
        2: return RUINS
        3: return RELIC
        4: return CAMP
        _: return CAMP

func objective_distance() -> int:
    if game == null or game.player == null:
        return 0
    var p: Vector3 = game.player.global_position
    var o := objective()
    return int(Vector2(p.x - o.x, p.z - o.z).length())

func companion_status() -> String:
    return "KAEL / WAEC HTER     MIRA / SANITAETERIN".replace("WAEC HTER", "WAECHTER")

func _speak(speaker: String, line: String, duration: float = 5.5) -> void:
    talking = speaker + ": " + line
    talk_timer = duration

func award_xp(amount: int) -> void:
    experience += amount
    while experience >= next_level_xp:
        experience -= next_level_xp
        level += 1
        next_level_xp = 500 + (level - 1) * 270
        game.max_health += 15.0
        game.health = game.max_health
        _speak("AUFSTIEG", "Stufe %d erreicht! Maximale Energie erhoeht." % level, 4.0)
    _save()

func on_enemy_defeated() -> void:
    award_xp(75)
    if stage == 1:
        combat_kills += 1
        if combat_kills >= 6 and game.remaining_spawns <= 0 and game.enemies.is_empty():
            _next_stage()

func _prepare_ambush() -> void:
    game.wave = 1
    game.remaining_spawns = maxi(0, 6 - combat_kills)
    game.spawn_timer = 0.6
    game.wave_wait = -1.0
    _speak("KAEL", "Hinterhalt! Bleib bei uns, wir schlagen sie zurueck!", 5.0)

func _next_stage() -> void:
    stage += 1
    combat_kills = 0
    award_xp(160)
    game.remaining_spawns = 0
    if stage == 1:
        _prepare_ambush()
    elif stage == 2:
        _speak("MIRA", "Wir haben es geschafft! In den Ruinen liegt der Lichtkern.", 6.0)
    elif stage == 3:
        _speak("KAEL", "Der Turm ist hier. Suche den Lichtkern zwischen den Steinen.", 6.0)
    elif stage == 4:
        _speak("MIRA", "Der Lichtkern! Schnell zurueck zum Lager. Wir retten das Tal.", 6.0)
    else:
        _speak("MIRA", "Das Licht kehrt zurueck. Du bist jetzt der Hueter von Riverlands!", 9.0)
    _update_markers()
    _save()

func update_adventure(delta: float) -> void:
    if game.state != "playing":
        return
    talk_timer = maxf(0.0, talk_timer - delta)
    auto_save_timer -= delta
    if auto_save_timer <= 0.0:
        auto_save_timer = 30.0
        _save()
    _update_allies(delta)
    if stage == 0 and objective_distance() < 11:
        _next_stage()
    elif stage == 1:
        if combat_kills >= 6 and game.remaining_spawns <= 0 and game.enemies.is_empty():
            _next_stage()
    elif stage == 2 and objective_distance() < 13:
        _next_stage()
    elif stage == 3 and objective_distance() < 8:
        _next_stage()
    elif stage == 4 and objective_distance() < 12:
        _next_stage()
    if is_instance_valid(relic_object):
        relic_object.rotate_y(0.35 * delta)
        relic_object.position.y = 1.95 + sin(game.elapsed * 1.5) * 0.23
        relic_object.visible = stage == 3

func reset_progress() -> void:
    stage = 0
    level = 1
    experience = 0
    next_level_xp = 500
    restored = true
    if FileAccess.file_exists(SAVE_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
    _update_markers()

func _save() -> void:
    var content := {
        "version": 1, "stage": stage, "level": level,
        "xp": experience, "next_xp": next_level_xp
    }
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(content))

func _load() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if f == null:
        return
    var payload: Variant = JSON.parse_string(f.get_as_text())
    if typeof(payload) != TYPE_DICTIONARY:
        return
    stage = clampi(int(payload.get("stage", 0)), 0, 5)
    level = clampi(int(payload.get("level", 1)), 1, 99)
    experience = maxi(0, int(payload.get("xp", 0)))
    next_level_xp = maxi(500, int(payload.get("next_xp", 500)))
    game.max_health = 100.0 + 15.0 * float(level - 1)
    game.health = game.max_health

func _update_markers() -> void:
    if is_instance_valid(gate_crystal):
        gate_crystal.visible = stage == 0 or stage == 1
    if is_instance_valid(relic_object):
        relic_object.visible = stage == 3

func _mat(tint: Color, roughness: float = 0.79, metal: float = 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = tint
    m.roughness = roughness
    m.metallic = metal
    return m

func _mesh_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
    var m := MeshInstance3D.new()
    var b := BoxMesh.new()
    b.size = size
    m.mesh = b
    m.material_override = mat
    m.position = pos
    parent.add_child(m)
    return m

func _mesh_ball(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
    var m := MeshInstance3D.new()
    var b := SphereMesh.new()
    b.radius = 0.5
    b.height = 1.0
    b.radial_segments = 12
    b.rings = 8
    m.mesh = b
    m.scale = size
    m.material_override = mat
    m.position = pos
    parent.add_child(m)
    return m

func _mesh_cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
    var m := MeshInstance3D.new()
    var c := CylinderMesh.new()
    c.top_radius = radius * 0.88
    c.bottom_radius = radius
    c.height = height
    c.radial_segments = 10
    m.mesh = c
    m.material_override = mat
    m.position = pos
    parent.add_child(m)
    return m

func _create_locations() -> void:
    var wood := _mat(Color("#554334"))
    var light_wood := _mat(Color("#a27a49"))
    var stone := _mat(Color("#777e76"))
    var stone_moss := _mat(Color("#555f4c"))
    var tent := _mat(Color("#a69b7d"))
    var fabric := _mat(Color("#494f48"))
    var gold := _mat(Color("#d5bc68"), 0.32, 0.45)
    var teal := _mat(Color("#56d3ce"), 0.19, 0.32)
    teal.emission_enabled = true
    teal.emission = Color("#32d9c9")
    teal.emission_energy_multiplier = 1.0
    var dark := _mat(Color("#322c28"))
    var camp := Node3D.new()
    camp.name = "WhisperingForestCamp"
    camp.position = CAMP
    add_child(camp)
    _mesh_cylinder(camp, Vector3(0.0, 0.03, 0.0), 6.6, 0.12, wood)
    for i in range(6):
        var a := TAU * float(i) / 6.0
        var pos := Vector3(cos(a) * 6.1, 1.1, sin(a) * 6.1)
        _mesh_cylinder(camp, pos, 0.12, 2.2, wood)
    for j in range(2):
        var t := Node3D.new()
        t.position = Vector3(-4.0 + j * 7.7, 0.0, -3.7)
        camp.add_child(t)
        _mesh_box(t, Vector3(0.0, 0.65, 0.0), Vector3(3.8, 1.3, 3.5), tent)
        _mesh_ball(t, Vector3(0.0, 1.46, 0.0), Vector3(4.0, 1.5, 3.7), fabric)
    _mesh_cylinder(camp, Vector3(0, 0.35, 2.2), 0.9, 0.7, stone)
    _mesh_ball(camp, Vector3(0, 0.9, 2.2), Vector3(0.7, 1.2, 0.7), teal)

    var bridge := Node3D.new()
    bridge.position = Vector3(4.5, 0.0, BRIDGE.z)
    bridge.name = "AncientBridge"
    add_child(bridge)
    for i in range(24):
        var x := -15.0 + float(i) * 1.7
        _mesh_box(bridge, Vector3(x, 0.65, 0.0), Vector3(1.48, 0.28, 5.4), light_wood)
        if i % 3 == 0:
            for side in [-2.5, 2.5]:
                _mesh_cylinder(bridge, Vector3(x, 1.6, side), 0.14, 2.1, wood)
                _mesh_box(bridge, Vector3(x, 2.47, side), Vector3(1.9, 0.12, 0.14), wood)
    for side in [-2.6, 2.6]:
        _mesh_box(bridge, Vector3(4.0, 1.7, side), Vector3(38.0, 0.15, 0.16), wood)
    gate_crystal = Node3D.new()
    gate_crystal.name = "BridgeQuestMarker"
    gate_crystal.position = BRIDGE + Vector3(0, 4.0, 0)
    add_child(gate_crystal)
    _mesh_ball(gate_crystal, Vector3.ZERO, Vector3(0.7, 1.4, 0.7), gold)

    var ruins := Node3D.new()
    ruins.name = "RuinsOfTheFirstLight"
    ruins.position = RUINS
    add_child(ruins)
    _mesh_cylinder(ruins, Vector3(0, 0.4, 0), 6.0, 0.8, stone)
    for i in range(12):
        var theta := TAU * float(i) / 12.0
        var px := cos(theta) * 6.0
        var pz := sin(theta) * 6.0
        var height := 5.0 + float(i % 4) * 2.0
        _mesh_box(ruins, Vector3(px, height * 0.5, pz), Vector3(1.6, height, 1.7), stone if i % 3 == 0 else stone_moss)
    for i in range(4):
        _mesh_box(ruins, Vector3(0, 3.3 + float(i) * 0.62, -7.4), Vector3(7.0 - float(i) * 0.9, 0.6, 1.5), stone)
    relic_object = Node3D.new()
    relic_object.name = "HeartOfTheValley"
    relic_object.position = RELIC + Vector3(0, 2.0, 0)
    add_child(relic_object)
    _mesh_ball(relic_object, Vector3.ZERO, Vector3(1.0, 1.5, 1.0), teal)
    _mesh_ball(relic_object, Vector3.ZERO, Vector3(0.5, 0.8, 0.5), gold)

    for i in range(22):
        var p := Vector3(rng.randf_range(-275.0, -110.0), 0.35, rng.randf_range(-300.0, 240.0))
        var height := rng.randf_range(2.5, 7.5)
        _mesh_box(self, p + Vector3(0, height * 0.5, 0), Vector3(rng.randf_range(1.1, 2.2), height, rng.randf_range(1.0, 2.2)), stone_moss)

func _make_allies() -> void:
    for id in range(2):
        var unit := CharacterBody3D.new()
        unit.name = "KaelGuardian" if id == 0 else "MiraHealer"
        unit.collision_layer = 0
        unit.collision_mask = 1
        unit.floor_snap_length = 0.3
        unit.position = CAMP + Vector3(-2.0 - 2.0 * float(id), 1.15, 1.8)
        add_child(unit)
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.36
        capsule.height = 1.86
        var shape := CollisionShape3D.new()
        shape.shape = capsule
        unit.add_child(shape)
        var visuals := Node3D.new()
        unit.add_child(visuals)
        var suit := _mat(Color("#393e44") if id == 0 else Color("#9c937b"))
        var armor := _mat(Color("#645846") if id == 0 else Color("#b8aa8a"), 0.42, 0.25)
        var skin := _mat(Color("#bd947e") if id == 0 else Color("#e0baa1"))
        var hair := _mat(Color("#322b28") if id == 0 else Color("#bf9a60"))
        var blue := _mat(Color("#4bb8cc"), 0.3, 0.36)
        blue.emission_enabled = true
        blue.emission = Color("#52bbdd")
        blue.emission_energy_multiplier = 0.8
        _mesh_cylinder(visuals, Vector3(0, 0.0, 0), 0.38, 0.93, suit)
        _mesh_box(visuals, Vector3(0, 0.26, -0.23), Vector3(0.65, 0.53, 0.20), armor)
        _mesh_ball(visuals, Vector3(0, 0.73, 0), Vector3(0.56, 0.62, 0.50), skin)
        _mesh_ball(visuals, Vector3(0, 0.97, 0.04), Vector3(0.56, 0.31, 0.53), hair)
        for side in [-1.0, 1.0]:
            _mesh_cylinder(visuals, Vector3(side * 0.51, 0.04, 0.01), 0.12, 0.72, suit)
            _mesh_cylinder(visuals, Vector3(side * 0.19, -0.71, 0.0), 0.14, 0.76, armor)
            _mesh_box(visuals, Vector3(side * 0.2, -1.05, -0.10), Vector3(0.27, 0.21, 0.43), suit)
        _mesh_box(visuals, Vector3(0, 0.22, 0.39), Vector3(0.53, 0.73, 0.19), armor)
        if id == 0:
            var sword := _mesh_box(visuals, Vector3(0.24, 0.44, 0.49), Vector3(0.11, 1.83, 0.14), blue)
            sword.rotate_z(0.32)
        else:
            _mesh_cylinder(visuals, Vector3(-0.52, 0.0, 0.45), 0.073, 1.9, armor)
            _mesh_ball(visuals, Vector3(-0.52, 1.0, 0.45), Vector3(0.37, 0.48, 0.37), blue)
        allies.append({"id": id, "body": unit, "visual": visuals, "health": 100.0, "shot_cd": 0.5, "heal_cd": 14.0, "name": "Kael" if id == 0 else "Mira"})

func _update_allies(delta: float) -> void:
    for a in allies:
        var body: CharacterBody3D = a["body"]
        var id: int = a["id"]
        var side := -1.0 if id == 0 else 1.0
        var wanted := game.player.global_position - game.player.global_transform.basis.z * -1.5 + game.player.global_transform.basis.x * (side * 2.8)
        var dist := Vector2(body.global_position.x - wanted.x, body.global_position.z - wanted.z).length()
        if dist > 36.0:
            body.global_position = wanted
            body.velocity = Vector3.ZERO
        var heading := wanted - body.global_position
        heading.y = 0.0
        if heading.length() > 1.8:
            var direction := heading.normalized()
            var speed := 8.7 if id == 0 else 8.1
            body.velocity.x = direction.x * speed
            body.velocity.z = direction.z * speed
        else:
            body.velocity.x = move_toward(body.velocity.x, 0.0, delta * 12.0)
            body.velocity.z = move_toward(body.velocity.z, 0.0, delta * 12.0)
        if not body.is_on_floor():
            body.velocity.y -= 26.0 * delta
        else:
            body.velocity.y = -0.5
        body.move_and_slide()
        var nearest: Dictionary = {}
        var nearest_distance := 36.0 if id == 0 else 22.0
        for enemy in game.enemies:
            var target: CharacterBody3D = enemy["body"]
            if not is_instance_valid(target):
                continue
            var d := body.global_position.distance_to(target.global_position)
            if d < nearest_distance:
                nearest = enemy
                nearest_distance = d
        a["shot_cd"] = float(a["shot_cd"]) - delta
        var aim: Vector3 = game.player.global_position
        if not nearest.is_empty():
            var enemy_body: CharacterBody3D = nearest["body"]
            aim = enemy_body.global_position
            if float(a["shot_cd"]) <= 0.0 and game.state == "playing":
                a["shot_cd"] = 1.1 if id == 0 else 1.8
                game._laser(body.global_position + Vector3(0.0, 0.30, 0.0), aim + Vector3.UP * 0.25)
                game._damage_enemy(nearest, 21.0 if id == 0 else 15.0, aim + Vector3.UP * 0.4)
        elif float(a["shot_cd"]) < 0.0:
            a["shot_cd"] = 0.3
        var to_aim := aim - body.global_position
        to_aim.y = 0.0
        if to_aim.length() > 0.4:
            body.look_at(Vector3(aim.x, body.global_position.y, aim.z), Vector3.UP)
        if id == 1:
            a["heal_cd"] = float(a["heal_cd"]) - delta
            if float(a["heal_cd"]) <= 0.0 and game.health < game.max_health * 0.72 and body.global_position.distance_to(game.player.global_position) < 14.0:
                a["heal_cd"] = 18.0
                game.health = minf(game.max_health, game.health + 23.0)
                _speak("MIRA", "Ich habe deine Wunden versorgt. Weiter geht's!", 3.5)
