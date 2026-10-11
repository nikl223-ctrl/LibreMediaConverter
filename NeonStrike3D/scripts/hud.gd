extends Control
## Full-screen responsive HUD and multitouch controls. No external font needed.
var game
var move_touch: int = -1
var look_touch: int = -1
var fire_touch: int = -1
var move_origin: Vector2 = Vector2.ZERO
var move_knob: Vector2 = Vector2.ZERO
var mobile: bool = false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    mobile = OS.has_feature("mobile")
    set_process(true)

func _process(_delta: float) -> void:
    queue_redraw()

func _ui_scale() -> float:
    return minf(size.x / 1600.0, size.y / 900.0)

func _print(label: String, pos: Vector2, pt: int, tint: Color = Color.WHITE) -> void:
    draw_string(ThemeDB.fallback_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pt, tint)

func _outlined_rect(rect: Rect2, fill: Color, line: Color) -> void:
    draw_rect(rect, fill, true)
    draw_rect(rect, line, false, 2.0)

func _button(center: Vector2, radius: float, title: String, outline: Color, fill: Color, font_size: int) -> void:
    draw_circle(center, radius, fill)
    draw_arc(center, radius, -PI, PI, 68, outline, 3.0, true)
    var string_size := ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
    _print(title, center - Vector2(string_size.x * 0.5, -float(font_size) * 0.34), font_size, outline)

func _draw() -> void:
    if game == null or size.x < 1.0:
        return
    var s := _ui_scale()
    var w := size.x
    var h := size.y
    var cyan := Color("#54f1ff")
    var pink := Color("#ff549d")
    var white := Color("#eefaff")
    var muted := Color("#8aabc4")
    var dark := Color(0.035, 0.08, 0.14, 0.80)
    var view_center := Vector2(w * 0.5, h * 0.5)

    if game.state == "menu":
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.055, 0.81))
        for i in range(12):
            var y := (float(i) + 1.0) * h / 13.0
            draw_line(Vector2(0.0, y), Vector2(w, y), Color(0.12, 0.45, 0.65, 0.12), 1.0)
        draw_rect(Rect2(Vector2(w * 0.21, h * 0.19), Vector2(w * 0.58, h * 0.60)), Color(0.025, 0.065, 0.12, 0.88))
        draw_rect(Rect2(Vector2(w * 0.21, h * 0.19), Vector2(w * 0.58, h * 0.60)), cyan, false, 3.0 * s)
        _center("R I V E R L A N D S", h * 0.355, int(64.0 * s), cyan)
        _center("3D / OPEN-WORLD STORY RPG", h * 0.414, int(24.0 * s), pink)
        _center("ERKUNDE DAS TAL  /  ERLEBE EINE GESCHICHTE  /  VERBUENDETE", h * 0.51, int(20.0 * s), muted)
        _center("TIPPEN ZUM STARTEN", h * 0.651, int(31.0 * s), white)
        _center("LINKS: BEWEGEN     RECHTS: ZIELEN / FEUERN", h * 0.72, int(17.0 * s), muted)
        return

    # Peripheral, unobtrusive corner HUD.
    _outlined_rect(Rect2(Vector2(26.0 * s, 22.0 * s), Vector2(347.0 * s, 91.0 * s)), dark, Color(0.23, 0.67, 0.80, 0.55))
    _print("RIVERLANDS / STRIKE", Vector2(43.0 * s, 54.0 * s), int(24.0 * s), cyan)
    _print("LVL %02d  |  XP %d/%d  |  SCORE %06d" % [game.rpg.level, game.rpg.experience, game.rpg.next_level_xp, game.score], Vector2(43.0 * s, 89.0 * s), int(18.0 * s), white)

    var hp_rect := Rect2(Vector2(32.0 * s, 130.0 * s), Vector2(332.0 * s, 20.0 * s))
    draw_rect(hp_rect, Color(0.08, 0.10, 0.16, 0.80))
    var hp_pct: float = clampf(game.health / game.max_health, 0.0, 1.0)
    draw_rect(Rect2(hp_rect.position, Vector2(hp_rect.size.x * hp_pct, hp_rect.size.y)), Color("#52f0b3") if hp_pct > 0.31 else pink)
    draw_rect(hp_rect, white, false, 1.4 * s)
    _print("ENERGIE   %d / 100" % int(game.health), Vector2(37.0 * s, 180.0 * s), int(17.0 * s), white)

    _outlined_rect(Rect2(Vector2(w - 344.0 * s, 24.0 * s), Vector2(312.0 * s, 83.0 * s)), dark, Color(0.23, 0.67, 0.80, 0.55))
    _print("VX-9 PLASMA RIFLE", Vector2(w - 327.0 * s, 52.0 * s), int(16.0 * s), muted)
    var rounds := "--" if game.reload_timer > 0.0 else str(game.ammo)
    _print(rounds + " / %02d" % game.magazine_size, Vector2(w - 327.0 * s, 90.0 * s), int(30.0 * s), cyan)
    _print("KILLS %02d" % game.kills, Vector2(w - 175.0 * s, 90.0 * s), int(17.0 * s), white)

    var reload_rect := Rect2(Vector2(w - 344.0 * s, 123.0 * s), Vector2(312.0 * s, 8.0 * s))
    draw_rect(reload_rect, Color(0.06, 0.14, 0.24, 0.85))
    if game.reload_timer > 0.0:
        draw_rect(Rect2(reload_rect.position, Vector2(reload_rect.size.x * (1.0 - game.reload_timer / 1.35), reload_rect.size.y)), pink)
    else:
        draw_rect(Rect2(reload_rect.position, Vector2(reload_rect.size.x * float(game.ammo) / float(game.magazine_size), reload_rect.size.y)), cyan)

    # Tactical reticle with reactive dispersion.
    var cross := 10.0 * s
    var gap := (8.0 + (4.0 if game.shoot_timer > 0.0 else 0.0)) * s
    draw_arc(view_center, 23.0 * s, 0.0, TAU, 60, Color(0.65, 0.96, 1.0, 0.25), 1.0 * s, true)
    draw_line(view_center - Vector2(gap + cross, 0.0), view_center - Vector2(gap, 0.0), cyan, 2.0 * s)
    draw_line(view_center + Vector2(gap, 0.0), view_center + Vector2(gap + cross, 0.0), cyan, 2.0 * s)
    draw_line(view_center - Vector2(0.0, gap + cross), view_center - Vector2(0.0, gap), cyan, 2.0 * s)
    draw_line(view_center + Vector2(0.0, gap), view_center + Vector2(0.0, gap + cross), cyan, 2.0 * s)
    draw_circle(view_center, 2.0 * s, white)

    if game.status_timer > 0.0 and game.state == "playing":
        _center(game.status_text, h * 0.17, int(26.0 * s), pink if game.reload_timer > 0.0 else cyan)

    if game.flash_time > 0.0:
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.84, 0.02, 0.22, 0.20 * game.flash_time / 0.26))

    if game.state == "playing":
        _draw_rpg()

    if mobile:
        var stick_center := Vector2(188.0 * s, h - 180.0 * s)
        var current_center := move_origin if move_touch >= 0 else stick_center
        draw_circle(current_center, 102.0 * s, Color(0.12, 0.26, 0.37, 0.24))
        draw_arc(current_center, 102.0 * s, -PI, PI, 70, Color(0.35, 0.85, 1.0, 0.60), 3.0 * s, true)
        draw_circle(current_center + move_knob, 46.0 * s, Color(0.20, 0.73, 0.89, 0.40))
        draw_arc(current_center + move_knob, 46.0 * s, -PI, PI, 50, cyan, 2.0 * s, true)
        _button(Vector2(w - 172.0 * s, h - 187.0 * s), 91.0 * s, "FEUER", pink, Color(0.48, 0.06, 0.24, 0.33), int(24.0 * s))
        _button(Vector2(w - 365.0 * s, h - 132.0 * s), 51.0 * s, "DASH", cyan, Color(0.04, 0.22, 0.30, 0.38), int(17.0 * s))
        _button(Vector2(w - 315.0 * s, h - 268.0 * s), 40.0 * s, "R", white, Color(0.18, 0.20, 0.27, 0.5), int(22.0 * s))
        _button(Vector2(w - 44.0 * s, 415.0 * s), 27.0 * s, "II", muted, Color(0.10, 0.17, 0.28, 0.65), int(13.0 * s))
        _button(Vector2(72.0 * s, h - 358.0 * s), 34.0 * s, "MAP", cyan, Color(0.10, 0.17, 0.28, 0.70), int(14.0 * s))
        var dash_fraction: float = 1.0 - clampf(game.dash_cooldown / 5.0, 0.0, 1.0)
        draw_arc(Vector2(w - 365.0 * s, h - 132.0 * s), 57.0 * s, -PI * 0.5, -PI * 0.5 + TAU * dash_fraction, 36, cyan, 3.0 * s, true)

    if game.state == "playing" and game.rpg.map_visible:
        _draw_big_map()

    if game.state == "dead" or game.state == "paused":
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.017, 0.039, 0.84))
        if game.state == "dead":
            _center("MISSION GESCHEITERT", h * 0.38, int(55.0 * s), pink)
            _center("SCORE %06d   |   WELLE %02d   |   KILLS %02d" % [game.score, game.wave, game.kills], h * 0.50, int(27.0 * s), white)
            _center("TIPPEN ZUM NEUSTART", h * 0.66, int(30.0 * s), cyan)
        else:
            _center("PAUSE", h * 0.40, int(66.0 * s), cyan)
            _center("TIPPEN ZUM FORTSETZEN", h * 0.63, int(29.0 * s), white)

    if h > w:
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.7))
        _center("BITTE QUERFORMAT VERWENDEN", h * 0.5, int(22.0 * s), white)

func _draw_rpg() -> void:
    var s := _ui_scale()
    var w := size.x
    var h := size.y
    var quest = game.rpg
    var gold := Color("#edc66e")
    var cyan := Color("#63dddc")
    var white := Color("#eff0e6")
    var dark := Color(0.025, 0.06, 0.065, 0.78)
    var card := Rect2(Vector2(25.0 * s, 214.0 * s), Vector2(485.0 * s, 98.0 * s))
    _outlined_rect(card, dark, Color(0.63, 0.68, 0.59, 0.50))
    _print(quest.quest_title(), Vector2(41.0 * s, 245.0 * s), int(21.0 * s), gold)
    _print(quest.quest_description(), Vector2(42.0 * s, 275.0 * s), int(16.0 * s), white)
    _print("%d m  /  ZIEL" % quest.objective_distance(), Vector2(43.0 * s, 301.0 * s), int(16.0 * s), cyan)
    _outlined_rect(Rect2(Vector2(25.0 * s, 325.0 * s), Vector2(405.0 * s, 37.0 * s)), dark, Color(0.24, 0.52, 0.42, 0.55))
    _print("KAEL  /  KAMPF    +    MIRA  /  HEILUNG", Vector2(40.0 * s, 350.0 * s), int(17.0 * s), white)
    var map_center := Vector2(w - 143.0 * s, 263.0 * s)
    var map_radius := 104.0 * s
    draw_circle(map_center, map_radius + 5.0 * s, Color(0.1, 0.17, 0.17, 0.92))
    draw_circle(map_center, map_radius, Color(0.17, 0.30, 0.24, 0.92))
    draw_arc(map_center, map_radius, 0.0, TAU, 72, Color("#a2c8ac"), 2.2 * s, true)
    # Local 150m radar, looking north. Curving cyan river and destination marker.
    for i in range(33):
        var z: float = -75.0 + float(i) * 4.8 + game.player.global_position.z
        var z_radar: float = (z - game.player.global_position.z) * 0.85 * s
        var shore: float = (5.0 + sin(z * 0.058) * 3.5) - game.player.global_position.x
        var x_radar: float = shore * 0.85 * s
        var p := map_center + Vector2(x_radar, z_radar)
        if p.distance_to(map_center) < map_radius - 5.0 * s:
            draw_circle(p, 4.4 * s, Color("#6fbdcd"))
    for a in game.rpg.allies:
        var ally: CharacterBody3D = a["body"]
        var local := Vector2(ally.global_position.x - game.player.global_position.x, ally.global_position.z - game.player.global_position.z) * 0.85 * s
        if local.length() < map_radius - 7.0 * s:
            draw_circle(map_center + local, 5.0 * s, Color("#a8e6a1"))
    var goal: Vector3 = quest.objective()
    var offset := Vector2(goal.x - game.player.global_position.x, goal.z - game.player.global_position.z) * 0.85 * s
    if offset.length() > map_radius - 13.0 * s:
        offset = offset.normalized() * (map_radius - 13.0 * s)
    draw_circle(map_center + offset, 9.0 * s, gold)
    draw_circle(map_center, 6.0 * s, cyan)
    var angle: float = game.player.rotation.y
    var pointing := Vector2(-sin(angle), -cos(angle))
    draw_line(map_center, map_center + pointing * 19.0 * s, Color.WHITE, 2.4 * s)
    draw_arc(map_center, 21.0 * s, 0, TAU, 28, Color(0.7, 1.0, 0.93, 0.35), 1.0 * s, true)
    if quest.talk_timer > 0:
        var bubble := Rect2(Vector2(w * 0.24, h - 107.0 * s), Vector2(w * 0.54, 65.0 * s))
        _outlined_rect(bubble, dark, Color(0.41, 0.75, 0.67, 0.53))
        var line: String = quest.talking
        if line.length() > 72:
            var split := line.rfind(" ", 70)
            if split < 20:
                split = 69
            _print(line.substr(0, split), Vector2(bubble.position.x + 16.0 * s, bubble.position.y + 26.0 * s), int(17.0 * s), white)
            _print(line.substr(split + 1), Vector2(bubble.position.x + 16.0 * s, bubble.position.y + 49.0 * s), int(17.0 * s), white)
        else:
            _print(line, Vector2(bubble.position.x + 16.0 * s, bubble.position.y + 38.0 * s), int(17.0 * s), white)

func _draw_big_map() -> void:
    var s := _ui_scale()
    var w := size.x
    var h := size.y
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.038, 0.045, 0.96))
    _center("RIVERLANDS  /  WELTKARTE", h * 0.13, int(38.0 * s), Color("#e3d6af"))
    _center("720 x 720 METER ERKUNDUNGSREGION", h * 0.19, int(17.0 * s), Color("#8fbab3"))
    var dimension := minf(w * 0.63, h * 0.66)
    var origin := Vector2((w - dimension) * 0.5, h * 0.235)
    var rect := Rect2(origin, Vector2(dimension, dimension))
    draw_rect(rect, Color("#344d39"))
    for i in range(55):
        var t := float(i) / 54.0
        var z := -360.0 + t * 720.0
        var rcenter := 5.0 + sin(z * 0.058) * 3.5 + cos(z * 0.19)
        var px := origin.x + (rcenter + 360.0) / 720.0 * dimension
        var py := origin.y + t * dimension
        draw_circle(Vector2(px,py), maxf(1.8, 6.0 * s), Color("#67bdc7"))
    for i in range(130):
        var x := sin(float(i) * 8.11) * 305.0
        var z := cos(float(i) * 12.87) * 304.0
        draw_circle(_to_map(Vector3(x,0,z),origin,dimension), 3.2 * s, Color("#709257"))
    for landmark in [
        {"pos":Vector3(-18,0,6),"label":"CAMP"},
        {"pos":Vector3(-16,0,-118),"label":"BRUECKE"},
        {"pos":Vector3(-66,0,-218),"label":"RUINEN"}
    ]:
        var mp := _to_map(landmark["pos"],origin,dimension)
        draw_circle(mp, 6.0 * s, Color("#edd07d"))
        _print(landmark["label"], mp + Vector2(10.0 * s, -8.0 * s), int(16.0 * s), Color.WHITE)
    var goalp := _to_map(game.rpg.objective(), origin, dimension)
    draw_arc(goalp, 12.0 * s, 0, TAU, 28, Color("#ffeea3"), 3.0 * s)
    var you := _to_map(game.player.global_position,origin,dimension)
    draw_circle(you, 8.0 * s, Color("#56e8ed"))
    _print("DU", you + Vector2(11.0 * s, -9.0 * s), int(16.0 * s), Color.WHITE)
    draw_rect(rect, Color("#adc2a7"), false, 3.0 * s)
    _center("TIPPE, UM ZURUECKZUKEHREN  |  PC: M", h * 0.98, int(18.0 * s), Color.WHITE)

func _to_map(world: Vector3, origin: Vector2, dimension: float) -> Vector2:
    return origin + Vector2((world.x + 360.0) / 720.0, (world.z + 360.0) / 720.0) * dimension

func _center(label: String, y: float, font_size: int, tint: Color) -> void:
    var text_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
    _print(label, Vector2((size.x - text_size.x) * 0.5, y), font_size, tint)

func _input(event: InputEvent) -> void:
    if game == null:
        return
    if event is InputEventScreenTouch:
        _touch(event.index, event.position, event.pressed)
    elif event is InputEventScreenDrag:
        if game.state == "playing":
            if event.index == move_touch:
                move_knob = (event.position - move_origin).limit_length(91.0 * _ui_scale())
                game.move_axis = move_knob / (91.0 * _ui_scale())
            elif event.index == look_touch or event.index == fire_touch:
                game.rotate_view(event.relative * (0.80 if event.index == fire_touch else 1.0))

func _touch(index: int, location: Vector2, pressed: bool) -> void:
    if game.state == "menu" or game.state == "dead":
        if pressed:
            game.begin_game()
        return
    if game.state == "paused":
        if pressed:
            game.toggle_pause()
        return
    var s := _ui_scale()
    var w := size.x
    var h := size.y
    if pressed:
        if game.rpg.map_visible:
            game.rpg.map_visible = false
        elif location.distance_to(Vector2(72.0 * s, h - 358.0 * s)) < 64.0 * s:
            game.rpg.map_visible = true
        elif location.distance_to(Vector2(w - 44.0 * s, 415.0 * s)) < 48.0 * s:
            game.toggle_pause()
        elif location.distance_to(Vector2(w - 365.0 * s, h - 132.0 * s)) < 72.0 * s:
            game.request_dash()
        elif location.distance_to(Vector2(w - 315.0 * s, h - 268.0 * s)) < 65.0 * s:
            game.start_reload()
        elif location.distance_to(Vector2(w - 172.0 * s, h - 187.0 * s)) < 130.0 * s:
            fire_touch = index
            game.trigger_down = true
        elif location.x < w * 0.46 and move_touch < 0:
            move_touch = index
            move_origin = location
            move_knob = Vector2.ZERO
        elif look_touch < 0:
            look_touch = index
    else:
        if index == move_touch:
            move_touch = -1
            move_knob = Vector2.ZERO
            game.move_axis = Vector2.ZERO
        if index == look_touch:
            look_touch = -1
        if index == fire_touch:
            fire_touch = -1
            game.trigger_down = false
