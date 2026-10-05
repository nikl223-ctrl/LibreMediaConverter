# External assets used by the Android build

All external assets below are downloaded by GitHub Actions before the Godot import step.

## Poly Haven — CC0
- Asphalt 01
- Grass Ground
- Concrete Wall 009
- Red Brick
- Brick Pavement 04

Poly Haven states that all of its HDRIs, textures and 3D models are licensed CC0.

## OpenGameArt — CC0
- racing car engine sound loops — domasx2
- Car engine Start Up 02 — looneybits
- Car 1 — Yaroslav_Novikov
- wind whoosh loop — SketchMan3

The build downloads only the audio files listed in the workflow. They are used as embedded game audio, with pitch/volume controlled dynamically from vehicle speed.
