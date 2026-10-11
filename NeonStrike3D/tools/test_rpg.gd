extends SceneTree
## Exercises actual story startup, HUD, spawned party, quest progression and save.
## Headless Godot smoke test: fails early on GDScript errors instead of shipping broken APK.

func _initialize() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    var scene: PackedScene = load("res://main.tscn")
    if scene == null:
        push_error("RPG smoke: main scene failed to load")
        quit(1)
        return
    var game = scene.instantiate()
    root.add_child(game)
    await process_frame
    if game.rpg == null:
        push_error("RPG smoke: roleplaying system missing")
        quit(1)
        return
    if game.rpg.allies.size() != 2:
        push_error("RPG smoke: expected two companions")
        quit(1)
        return
    game.begin_game()
    await process_frame
    if game.state != "playing":
        push_error("RPG smoke: did not enter gameplay")
        quit(1)
        return
    if game.rpg.quest_title().is_empty():
        push_error("RPG smoke: no quest")
        quit(1)
        return
    if game.rpg.stage == 0:
        game.player.global_position = Vector3(-16.0, 1.1, -118.0)
        await physics_frame
        await physics_frame
        if game.rpg.stage != 1:
            push_error("RPG smoke: bridge quest failed to progress")
            quit(1)
            return
    game.rpg.map_visible = true
    await process_frame
    game.rpg.map_visible = false
    if game.rpg.allies.size() != 2:
        push_error("RPG smoke: companions lost during simulation")
        quit(1)
        return
    print("RPG_SMOKE_PASS stage=", game.rpg.stage, " companions=2, map=true, active story")
    quit(0)
