extends Control
## Adaptive Android multitouch dashboard for ambulance driving.
var game
var steer_touch: int = -1
var gas_touch: int = -1
var brake_touch: int = -1
var steer_origin: Vector2 = Vector2.ZERO
var steer_knob: Vector2 = Vector2.ZERO

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
    queue_redraw()

func _scale() -> float:
    return minf(size.x/1600.0,size.y/900.0)

func _print(value: String, at: Vector2, px: int, tint: Color=Color.WHITE) -> void:
    draw_string(ThemeDB.fallback_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1.0,px,tint)

func _center(value: String, x: float, y: float, px: int, tint: Color=Color.WHITE) -> void:
    var tw: float = ThemeDB.fallback_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1.0,px).x
    _print(value,Vector2(x-tw*0.5,y),px,tint)

func _panel(rect: Rect2, border: Color=Color("#659fbb")) -> void:
    draw_rect(rect,Color(0.020,0.060,0.083,0.81),true)
    draw_rect(rect,border,false,2.0*_scale())

func _button(center: Vector2, radius: float, label: String, tint: Color, active: bool = false) -> void:
    var bg: Color = tint.darkened(0.68)
    bg.a = 0.84 if active else 0.56
    draw_circle(center,radius,bg)
    draw_arc(center,radius,-PI,PI,62,tint,3.0*_scale(),true)
    _center(label,center.x,center.y+6.0*_scale(),int(18*_scale()),tint)

func _draw() -> void:
    if game==null or size.x<1.0:
        return
    var s: float = _scale()
    var w: float = size.x
    var h: float = size.y
    var cyan := Color("#65d7ef")
    var gold := Color("#f2d38b")
    var white := Color("#ecf5f8")
    var green := Color("#71edb9")
    var pale := Color("#9fb3bc")
    if game.state=="menu":
        draw_rect(Rect2(Vector2.ZERO,size),Color(0.016,0.040,0.065,0.84),true)
        _panel(Rect2(Vector2(w*0.13,h*0.15),Vector2(w*0.74,h*0.68)),cyan)
        _center("R E T T U N G S D I E N S T",w*0.5,h*0.31,int(51.0*s),white)
        _center("S I M U L A T O R   /   A N D R O I D",w*0.5,h*0.373,int(28.0*s),cyan)
        _center("FAHR DIE RETTUNGSEINSAETZE IN EINER FREI BEFAHRBAREN STADT",w*0.5,h*0.46,int(19.0*s),pale)
        _center("FAHRZEUG WAEHLEN  -  TIPPEN ZUM STARTEN",w*0.5,h*0.56,int(25.0*s),gold)
        for i in range(3):
            var box := Rect2(Vector2(w*(0.19+float(i)*0.212),h*0.60),Vector2(w*0.19,h*0.115))
            _panel(box,cyan if i==0 else pale)
            _center(["RTW","NEF","KTW"][i],box.get_center().x,box.position.y+38.0*s,int(30.0*s),white)
            _center(["RETTUNG","NOTARZT","TRANSPORT"][i],box.get_center().x,box.position.y+74.0*s,int(16.0*s),gold)
        _center("ANDROID-NEUENTWICKLUNG  /  ALLE SOUNDS UND MODELLE NEU ERSTELLT",w*0.5,h*0.78,int(15*s),pale)
        return

    _panel(Rect2(Vector2(23*s,21*s),Vector2(513*s,112*s)),cyan)
    _print("RETTUNGSDIENST / LEITSTELLE 112",Vector2(40*s,56*s),int(21*s),cyan)
    _print("KARRIERE STUFE %d  |  %d EUR  |  %d EINSATZE" % [game.career_rank,game.credits,game.completed],Vector2(40*s,87*s),int(18*s),white)
    _print(game.unit_labels[game.vehicle_type],Vector2(40*s,115*s),int(17*s),pale)

    _panel(Rect2(Vector2(23*s,149*s),Vector2(630*s,99*s)),gold)
    _print(game.mission_title(),Vector2(39*s,184*s),int(19*s),gold)
    _print("GPS-ZIEL  %d M    |    EINSATZDAUER %.1f MIN" % [game.objective_distance(),game.mission_minutes],Vector2(39*s,216*s),int(19*s),white)

    _panel(Rect2(Vector2(w-365*s,18*s),Vector2(341*s,111*s)),cyan)
    _print("GESCHWINDIGKEIT",Vector2(w-346*s,52*s),int(16*s),pale)
    _print("%03d KM/H" % int(absf(game.speed)*3.6),Vector2(w-346*s,93*s),int(37*s),white)
    _print("R" if game.reverse_gear else "D",Vector2(w-95*s,94*s),int(25*s),gold)
    var fps: int = Engine.get_frames_per_second()
    var performance_color: Color = green if fps>=45 else (gold if fps>=30 else Color("#ff8f7e"))
    _print("%d FPS" % fps,Vector2(w-180*s,119*s),int(14*s),performance_color)

    # Emergency priority and current mission state.
    _panel(Rect2(Vector2(w-364*s,147*s),Vector2(340*s,57*s)),cyan if game.lights_on else pale)
    _print("BLAULICHT %s   /   MARTINSHORN %s" %
        ["AN" if game.lights_on else "AUS","AN" if game.siren_on else "AUS"],Vector2(w-345*s,181*s),int(17*s),white)

    if game.message_time > 0.0:
        var rect := Rect2(Vector2(w*0.28,h*0.20),Vector2(w*0.44,58*s))
        _panel(rect,gold)
        _center(game.message,rect.get_center().x,rect.position.y+36*s,int(18*s),white)

    # Compact GPS minimap and bearing arrow.
    var center := Vector2(w-147*s,310*s)
    var radius: float = 91*s
    draw_circle(center,radius+5*s,Color(0.04,0.13,0.17,0.89))
    draw_circle(center,radius,Color("#344f51"))
    for n in range(-4,5):
        var coord := float(n)*80.0
        var local_x: float = (coord-game.player.global_position.x)*0.50*s
        var local_z: float = (coord-game.player.global_position.z)*0.50*s
        if absf(local_x)<radius:
            var width: float = sqrt(radius*radius-local_x*local_x)
            draw_line(center+Vector2(local_x,-width),center+Vector2(local_x,width),Color("#9ea6a3"),3.0*s)
        if absf(local_z)<radius:
            var width: float = sqrt(radius*radius-local_z*local_z)
            draw_line(center+Vector2(-width,local_z),center+Vector2(width,local_z),Color("#9ea6a3"),3.0*s)
    var goal: Vector3 = game.active_target()
    var relative := Vector2(goal.x-game.player.global_position.x,goal.z-game.player.global_position.z)*0.50*s
    if relative.length()>radius-10*s:
        relative=relative.normalized()*(radius-10*s)
    draw_circle(center+relative,9*s,gold)
    draw_circle(center,5*s,cyan)
    var direction := Vector2(-sin(game.player.rotation.y),-cos(game.player.rotation.y))
    draw_line(center,center+direction*22*s,white,2.4*s)
    draw_arc(center,radius,0,TAU,60,cyan,2*s,true)

    var stick_origin := steer_origin if steer_touch>=0 else Vector2(190*s,h-166*s)
    draw_circle(stick_origin,105*s,Color(0.16,0.31,0.40,0.39))
    draw_arc(stick_origin,105*s,0,TAU,64,cyan,3*s,true)
    draw_circle(stick_origin+steer_knob,47*s,Color(0.23,0.65,0.73,0.49))
    draw_arc(stick_origin+steer_knob,47*s,0,TAU,48,cyan,3*s,true)
    _center("LENKEN",stick_origin.x,stick_origin.y-114*s,int(18*s),white)

    var throttle_center := Vector2(w-137*s,h-155*s)
    var brake_center := Vector2(w-326*s,h-155*s)
    _button(throttle_center,100*s,"GAS",green,game.gas_input>0)
    _button(brake_center,80*s,"BREMSE",Color("#ff8f7e"),game.brake_input>0)
    _button(Vector2(w-128*s,h-331*s),58*s,"SIRENE",gold,game.siren_on)
    _button(Vector2(w-272*s,h-331*s),58*s,"BLAU",cyan,game.lights_on)
    _button(Vector2(w-417*s,h-331*s),55*s,"KAMERA",white,not game.chase_camera)
    _button(Vector2(w-563*s,h-331*s),53*s,"R / D",pale,game.reverse_gear)

    if game.mission_stage == 1:
        var care := Rect2(Vector2(w*0.40,h-174*s),Vector2(w*0.19,95*s))
        _panel(care,green)
        _center("PATIENT",care.get_center().x,care.position.y+34*s,int(23*s),white)
        _center("VERSORGEN",care.get_center().x,care.position.y+68*s,int(22*s),green)
    elif game.mission_stage == 4:
        _panel(Rect2(Vector2(w*0.36,h-144*s),Vector2(w*0.30,65*s)),green)
        _center("PATIENTENVERSORGUNG  %.1f" % game.mission_timer,w*0.51,h-103*s,int(20*s),white)

    # Hint for first play session.
    if game.completed==0 and game.mission_stage==0:
        _print("LENKEN LINKS   |   GAS / BREMSE RECHTS",Vector2(w*0.31,h-26*s),int(16*s),Color(0.9,0.97,1,0.72))

    if h>w:
        draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,0.72),true)
        _center("BITTE HANDY INS QUERFORMAT DREHEN",w*0.5,h*0.5,int(24*s),white)

func _input(event: InputEvent) -> void:
    if game == null:
        return
    if event is InputEventScreenTouch:
        _on_touch(event.index,event.position,event.pressed)
    elif event is InputEventScreenDrag and game.state=="playing":
        if event.index==steer_touch:
            var magnitude: float = 105.0*_scale()
            steer_knob=Vector2(clampf(event.position.x-steer_origin.x,-magnitude,magnitude),0.0)
            game.steer_axis=clampf(steer_knob.x/magnitude,-1.0,1.0)
    elif event is InputEventMouseButton and event.pressed:
        # Debug on Windows desktop: mouse-click supports menu and buttons as well.
        _on_touch(900,event.position,true)
    elif event is InputEventMouseButton and not event.pressed:
        _on_touch(900,event.position,false)

func _on_touch(index: int, pos: Vector2, pressed: bool) -> void:
    var s: float = _scale()
    var w: float = size.x
    var h: float = size.y
    if game.state=="menu":
        if pressed:
            var unit: int = clampi(int((pos.x/w-0.19)/0.212),0,2)
            if pos.y>h*0.59 and pos.y<h*0.75:
                game.start_simulation(unit)
            else:
                game.start_simulation(0)
        return
    if pressed:
        if game.mission_stage==1 and pos.x>w*0.40 and pos.x<w*0.59 and pos.y>h-182*s:
            game.trigger_treatment()
        elif pos.distance_to(Vector2(w-128*s,h-331*s))<75*s:
            game.toggle_siren()
        elif pos.distance_to(Vector2(w-272*s,h-331*s))<75*s:
            game.toggle_lights()
        elif pos.distance_to(Vector2(w-417*s,h-331*s))<72*s:
            game.toggle_camera()
        elif pos.distance_to(Vector2(w-563*s,h-331*s))<70*s:
            game.toggle_reverse()
        elif pos.distance_to(Vector2(w-137*s,h-155*s))<124*s:
            gas_touch=index
            game.gas_input=1.0
        elif pos.distance_to(Vector2(w-326*s,h-155*s))<103*s:
            brake_touch=index
            game.brake_input=1.0
        elif pos.x<w*0.42 and pos.y>h*0.49 and steer_touch<0:
            steer_touch=index
            steer_origin=pos
            steer_knob=Vector2.ZERO
    else:
        if index==gas_touch:
            gas_touch=-1
            game.gas_input=0.0
        if index==brake_touch:
            brake_touch=-1
            game.brake_input=0.0
        if index==steer_touch:
            steer_touch=-1
            steer_knob=Vector2.ZERO
            game.steer_axis=0.0
