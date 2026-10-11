# RIVERLANDS STORY RPG · Android 3D adventure (prototype v3)

This playable open-world-style shooter RPG is the next iteration of **Riverlands Strike 3D**. It uses a larger procedural river valley and adds quest-driven adventure gameplay, a pair of AI companions and automatic saving. It's built for Android ARM64, including Samsung Galaxy S24 Ultra.

## Download APK

1. Visit [Riverlands Story RPG GitHub Actions](https://github.com/nikl223-ctrl/LibreMediaConverter/actions/workflows/riverlands-rpg.yml).
2. Choose the most recent **successful (green)** workflow run.
3. Download the artifact **Riverlands-Story-RPG-APK**, extract it, and install **RiverlandsRPG.apk**.
4. APK already bundles the mobile textures. **Do not install the 4K asset ZIP**; that artifact contains source textures for developers only.

A GitHub login may be required to download a workflow artifact. APKs are debug-signed for sideload testing and builds may be signed by different temporary keys. Uninstall the previous test version before installing a new version if Android reports a signature mismatch.

## Adventure and questline

Chapter: **Das verlorene Licht** (The Lost Light).
- Meet **Kael** (guardian companion who follows and shoots enemies) and **Mira** (medic companion who follows, helps in combat and heals the player).
- Quest 1: Find the ancient bridge with your companions.
- Quest 2: Defeat six attackers at the bridge.
- Quest 3: Reach the ruins of the first light.
- Quest 4: Recover the valley's lost light core.
- Quest 5: Return to the forest camp and finish the story.

There are six story stages (0–5); this is a *short prototype storyline*, not a fully voiced or cinematic RPG. Enemies attack only in the ambush stage, while exploration and companions run throughout. Kills and objectives grant XP, and levels improve maximum energy. Quest stage, player level and XP are saved in `user://riverlands_rpg.json`.

## Graphics, scope and performance

- **720 × 720-meter** generated region: approximately **17×** the area of the original 172 × 172-meter level (rough estimate, square-to-square).
- Winding river, textured ground, fuller woodland, handmade hero trees, shrub clusters, small flowers, rocks, rolling outer terrain, moving water, daytime sky and fog.
- Trees and vegetation use **GPU-instanced MultiMesh batches with 96-meter culling tiles** to avoid making one scene node per plant.
- Quest landmarks: forest camp, a wooden bridge and ruins with a glowing relic.
- Two distinct in-world companion characters generated using original polygon geometry.
- **Worker 1:** procedurally renders five **4096 × 4096** original material master textures and 2048 × 2048 phone texture derivatives.
- **Worker 2:** downloads optimized textures, compiles scripts, launches the game for runtime testing, checks companions and first story objective, and builds the Android ARM64 APK.

**Visual expectation:** the cinematic picture shared in chat is a *concept render*, not a screenshot of this APK. The live game remains a small Godot procedural 3D prototype with simpler foliage, models, reflections and shadows than the photorealistic concept. 4K textures alone do not produce photorealistic AAA rendering. FPS has **not** been measured on a real S24 Ultra; hardware testing and iteration are needed.

## Controls

**Android landscape:** left drag to move; drag the right side to aim; FEUER to shoot; R to reload; DASH to sprint briefly; MAP for full world map, tap again to close; pause button at right side. On the map, player is cyan; objective markers are gold.

**Desktop testing:** WASD move, mouse aim, left mouse shoot, R reload, Space dash, Escape pause, **M** open/close map.

## Code and build

- `scripts/game.gd`: character physics, FPS combat, hit detection, health, enemy logic.
- `scripts/rpg.gd`: story stages, persistent progress, quest landmarks and companion AI.
- `scripts/outdoor.gd`: valley mesh, river, trees, bushes, rocks, daylight and culling.
- `scripts/hud.gd`: on-screen mobile controls, quest UI and map.
- `tools/generate_4k_textures.py`: procedural texture renderer.
- `tools/test_rpg.gd`: automated **actual gameplay** startup and quest progression test.
- `.github/workflows/riverlands-rpg.yml`: independent texture and APK build workers.

### Limitations

This is an offline singleplayer prototype. The explorable valley terrain has an optimized simple flat physics collision surface; visually raised hills and the bridge are currently decorative, not a fully navigable 3D physical landscape. Companions follow with simple direct steering and can teleport when separated, not obstacle-aware navigation. The story has text dialogue and proximity-triggered objectives, not animations, real voice actors, full inventory, crafting or large settlements. Further modeling, animations, terrain collisions, content streaming and mobile profiling will be necessary before it resembles the target image.
