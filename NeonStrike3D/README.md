# RIVERLANDS STRIKE 3D — Outdoor 4K Edition

Real-time 3D first-person shooter for Android (ARM64). This edition replaces the original neon arena with a nature-inspired river valley: green riverbanks, a winding reflective-style river, dense trees and undergrowth, shoreline rocks, clouds and daylight.

> **Visual fidelity note:** The outdoor scene is procedurally generated and photograph-inspired, not a photoreal AAA engine scene. The dedicated graphics worker generates **4096 × 4096 source textures**. The actual smartphone build currently uses **2048 × 2048 downscaled texture variants** for performance; 4K source assets are available separately. This does not claim 4K real-time frame rendering or a measured 60 FPS on any particular phone.

## Downloadable Android APK (GitHub Actions)

The `riverlands-4k` branch is isolated from `main`, so the existing LibreMediaConverter on `main` remains unchanged.

1. Go to [Riverlands 4K Actions runs](https://github.com/nikl223-ctrl/LibreMediaConverter/actions/workflows/riverlands-4k.yml).
2. Choose the newest **successful (green)** run.
3. Under **Artifacts**, download **Riverlands-Strike-3D-APK**, extract the ZIP, and install `RiverlandsStrike3D.apk`.
4. The **Riverlands-4K-Master-Textures** artifact contains full-resolution generated texture masters.

Two actual GitHub-hosted workers are required:

- **Worker 1 / 4K Material Renderer:** Generates grass, soil, tree bark, rock and water source textures at 4096 × 4096 pixels, then optimizes each for mobile to 2048 × 2048 pixels; uploads both output artifacts.
- **Worker 2 / Android APK Build:** Downloads the optimized textures from Worker 1, imports Godot 4.5.2, runs GDScript compile checks and a startup smoke test, builds a debug-signed ARM64 APK, then publishes it as a downloadable artifact.

## Game features

- Fully navigable outdoor arena with hand-coded 3D geometry
- Sine-curved river with moving water shader, procedural hills, sky atmosphere
- GPU-instanced trees, leafy tree canopies, wild grass, shoreline stones and clouds
- Wave-based Sentinel and Brute enemies with pursuit and contact attacks
- Plasma rifle, hit detection, projectile tracers, sound, pickups, score and health
- Android touch movement, look, firing, reload, dash, pause (landscape)
- Desktop controls for testing: WASD, mouse, LMB fire, R reload, Space dash, Escape pause
- Offline. No external game servers or telemetry.

## Source code

- `scripts/game.gd`: arena game logic, enemy AI, weapons, FPS camera and score
- `scripts/outdoor.gd`: procedural daylight landscape, sky, river, forest, rocks, shaders and GPU instancing
- `scripts/hud.gd`: touch controls and tactical HUD
- `tools/generate_4k_textures.py`: Pillow/NumPy terrain and foliage material renderer
- `assets/generated/`: textures populated during GitHub Actions job
- `../../.github/workflows/riverlands-4k.yml`: two-worker build pipeline

## Run locally

Install Godot 4.5.2. Optional but recommended: generate the textures before opening the project:

```sh
pip install pillow numpy
python NeonStrike3D/tools/generate_4k_textures.py
```

Open `NeonStrike3D/project.godot` and press F6/F5.

For a phone, only sideload APKs from workflows you trust. This is a testing APK, not a Play Store release. Each debug build gets a temporary signing key, so if Android refuses to update it, uninstall the older **Riverlands** test build before installing a new one. The separate package identifier avoids overwriting the original Neon Strike test APK.
