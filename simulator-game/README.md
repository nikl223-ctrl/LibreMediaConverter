# RoadLife Simulator — HD Android build

Android-Fahr- und Liefer-Simulator mit Godot 4.7.2. Der Android-Build ist jetzt auf den Vulkan-Mobile-Renderer und starke Smartphones ausgelegt.

## Grafik
- 4K PBR-Materialien mit Diffuse-, OpenGL-Normal- und Roughness-Maps
- Asphalt 01, Grass Ground, Concrete Wall 009, Red Brick und Brick Pavement 04 von Poly Haven (CC0)
- Vulkan Mobile Renderer
- 4x MSAA im Ultra-Modus
- ACES-Tonemapping, Glow, Fog und Debanding
- dynamischer Tag-/Nacht-Zyklus
- Straßenlaternen und Reflection Probes
- Metallic/Clearcoat-Fahrzeuglack, Glas, Felgen, Scheinwerfer und Bremslicht
- Performance-, High- und Ultra-Grafikmodus direkt im Spiel

## Audio
- Motorstart
- zwei dynamisch gemischte Motor-Layer
- Straßen-/Abrollgeräusch
- geschwindigkeitsabhängiger Wind
- Kollisionssound
- Pitch und Lautstärke ändern sich mit Fahrzeugtempo und Last

## Gameplay
- frei befahrbare Stadt
- Multi-Touch-Steuerung
- Tastatur- und Gamepad-Unterstützung
- geschwindigkeitsabhängige Lenkung, Gas, Bremse, Rückwärtsgang und Handbremse
- Sprit, Tankstelle und Fahrzeugschaden
- Lieferaufträge mit Bezahlung
- persistentes Geld- und Speichersystem
- Garage mit Motor-, Brems-, Tank- und Karosserie-Upgrades
- Stadtverkehr

## Warum kein DLSS auf Android?
NVIDIA DLSS benötigt GeForce-RTX-Hardware bzw. Tensor Cores. Der Android-Build verwendet stattdessen Vulkan und auf Mobile-Hardware abgestimmte Qualitätsstufen.

## Assets
Siehe ASSET_LICENSES.md. Die externen PBR-Texturen und Audiodateien werden beim GitHub-Actions-Build geladen und anschließend in die APK eingebettet.

## APK
GitHub -> Actions -> **Build RoadLife Android APK** -> neuesten erfolgreichen Lauf öffnen -> Artifact **RoadLifeSimulator-APK** herunterladen.
