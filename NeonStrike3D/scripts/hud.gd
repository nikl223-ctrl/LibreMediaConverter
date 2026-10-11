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
        _center("N E O N  S T R I K E", h * 0.355, int(64.0 * s), cyan)
        _center("3 D  //  SURVIVAL ARENA", h * 0.414, int(24.0 * s), pink)
        _center("WELLEN UEBERLEBEN  •  ZIELE AUSSCHALTEN  •  BOOSTEN", h * 0.51, int(20.0 * s), muted)
        _center("TIPPEN ZUM STARTEN", h * 0.651, int(31.0 * s), white)
        _center("LINKS: BEWEGEN     RECHTS: ZIELEN / FEUERN", h * 0.72, int(17.0 * s), muted)
        return

    # Peripheral, unobtrusive corner HUD.
    _outlined_rect(Rect2(Vector2(26.0 * s, 22.0 * s), Vector2(347.0 * s, 91.0 * s)), dark, Color(0.23, 0.67, 0.80, 0.55))
    _print("NEON / STRIKE 3D", Vector2(43.0 * s, 54.0 * s), int(24.0 * s), cyan)
    _print("WELLE %02d  |  SCORE %06d" % [game.wave, game.score], Vector2(43.0 * s, 89.0 * s), int(18.0 * s), white)

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
        _button(Vector2(w - 45.0 * s, 179.0 * s), 25.0 * s, "II", muted, Color(0.10, 0.17, 0.28, 0.5), int(13.0 * s))
        var dash_fraction: float = 1.0 - clampf(game.dash_cooldown / 5.0, 0.0, 1.0)
        draw_arc(Vector2(w - 365.0 * s, h - 132.0 * s), 57.0 * s, -PI * 0.5, -PI * 0.5 + TAU * dash_fraction, 36, cyan, 3.0 * s, true)

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
        if location.distance_to(Vector2(w - 45.0 * s, 179.0 * s)) < 48.0 * s:
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
