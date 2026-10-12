extends SceneTree
## Real startup regression test, run by GitHub before uploading an Android APK.
func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var pack: PackedScene = load("res://main.tscn")
    if pack == null:
        push_error("Unable to load rescue simulator main scene")
        quit(1)
        return
    var game = pack.instantiate()
    root.add_child(game)
    await process_frame
    if game.player == null or game.city == null or game.hud == null:
        push_error("Missing city, player, or Android controls")
        quit(1)
        return
    if game.city.traffic.size() < 10:
        push_error("City should contain moving traffic")
        quit(1)
        return
    game.start_simulation(0)
    await process_frame
    if game.state != "playing" or game.mission_stage != 0:
        push_error("Cannot start RTW dispatch")
        quit(1)
        return
    # Verify that floor contacts do NOT count as crashes anymore. This was
    # the cause of the previous version's severe speed limitation.
    game.gas_input = 1.0
    for frame in range(150):
        await physics_frame
    game.gas_input = 0.0
    if game.speed < 18.0:
        push_error("Drive physics regression: full-throttle ambulance could not accelerate above 65 km/h")
        quit(1)
        return
    print("DRIVING_SPEED_TEST_PASS actual_kmh=", game.speed*3.6)
    game.toggle_lights()
    game.toggle_siren()
    if not game.lights_on or not game.siren_on:
        push_error("Emergency light/siren controls not working")
        quit(1)
        return
    game.toggle_siren()
    game.player.global_position = game.incident_position
    game.speed = 0.0
    game._tick_mission(0.016)
    if game.mission_stage != 1:
        push_error("Arrival at emergency incident did not unlock treatment")
        quit(1)
        return
    game.trigger_treatment()
    if game.mission_stage != 4:
        push_error("Treatment action did not begin")
        quit(1)
        return
    game._tick_mission(4.1)
    if game.mission_stage != 2:
        push_error("Patient pickup did not transition to hospital trip")
        quit(1)
        return
    game.player.global_position = game.hospital_position
    game._tick_mission(0.1)
    if game.mission_stage != 3 or game.completed < 1:
        push_error("Patient hospital delivery failed")
        quit(1)
        return
    print("AMBULANCE_SMOKE_PASS city traffic=", game.city.traffic.size(), " RTW driving + emergency lights + siren + treatment + hospital delivery + career")
    quit(0)
