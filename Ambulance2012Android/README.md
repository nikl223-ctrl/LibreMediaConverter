# Rettungsdienst Simulator Android · Eigenständige Neuprogrammierung

**Android-Spielprojekt** inspiriert vom PC-Titel „Rettungswagen-Simulator 2012“ (2011, Z-Software / astragon). Mit Godot 4.5.2 und ARM64-APK über GitHub Actions. Das ist **kein offizieller Port und keine 1:1-Version**.

## Wichtig: Originalgrafik und Originalsound (neuer privater Build)

Der erste öffentliche Android-Prototyp enthält **nicht** die Original-3D-Modelle, die Originaltextures oder die FMOD-Aufnahmen. **Die Dateien sind nicht beim APK-Export verschwunden – sie waren schlicht nie in diesem Build enthalten.**

Die Windows-Prüfung des user-provided `city.v` ist jetzt gelungen:

| Originaldatei | Auslesen / Konvertieren | Ergebnis |
|---|---|---|
| `textures/vehicles/RTW/aussen_1.dds` | DDS nach WebP | Erfolg, 1024 × 1024 |
| `textures/vehicles/RTW/cockpit_1.dds` | DDS nach WebP | Erfolg, 2048 × 2048 |
| `textures/buildings/city_hr1_var01_diff.dds` | DDS nach WebP | Erfolg, 2048 × 2048 |
| `textures/buildings/Gehwege.dds` | DDS nach WebP | Erfolg, 1024 × 1024 |
| `Spielerfahrzeug_Sirene_Loop_V` | FSB4 nach WAV | Erfolg, 8,78 Sekunden Stereo |
| `RTW_NEU_Leerlauf_01` | FSB4 nach WAV | Erfolg |
| `RTW_NEU_Langsam_01` | FSB4 nach WAV | Erfolg |
| `RTW_NEU_Hoch_04` | FSB4 nach WAV | Erfolg |
| `models/vehicle/RTW/chassis.Model` | Vision VBIN/HSMV → GLB | **Noch nicht konvertiert** |
| `models/vehicle/RTW/cockpit.Model` | Vision VBIN/HSMV → GLB | **Noch nicht konvertiert** |

Ein **fertiger GitHub-Actions-Workflow** ist im Repository enthalten:

[PRIVATE Rettungswagen – Originalsound/Originaltexturen zu Android](https://github.com/nikl223-ctrl/LibreMediaConverter/blob/ambulance-2012-android/.github/workflows/ambulance-private-assets.yml)

Der Workflow ist in diesem **öffentlichen** Repository aus gutem Grund deaktiviert (`github.event.repository.private == true`). Für eine nur persönlich nutzbare APK mit den Originalaufnahmen:

1. Ein **neues, leeres, privates** GitHub-Repository unter https://github.com/new anlegen, zum Beispiel `Rettungsdienst-2012-Android`. Nicht den bestehenden Media Converter umbauen.
2. Den Quellcode aus dem Branch `ambulance-2012-android` in das private Repository kopieren, inklusive `.github/workflows/ambulance-private-assets.yml`.
3. Dem neuen Repo in GitHub Actions die **eigenen** Secrets `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` und `GOOGLE_REFRESH_TOKEN` hinzufügen, ohne die Werte zu veröffentlichen. Der Client muss zum privaten OAuth-Projekt `160241343420` gehören.
4. Auf dem privaten GitHub-Repository den Workflow starten. Worker 1 lädt das nur für den Build benötigte Originalarchiv, importiert die WAVs/WebPs und überträgt sie als **privates** Build-Artefakt an Worker 2. Worker 2 prüft die Originaldateien und baut eine neue APK.
5. Im Spiel zeigt der Startbildschirm an, ob Originalton/Texturen tatsächlich installiert sind. Auch in diesem privaten Build wären die echten **3D-Fahrzeug- und Gebäudemodelle** vorerst noch nicht enthalten; dafür brauchen wir zusätzlich einen getesteten VBIN/HSMV-Konverter, einschließlich originalgetreuer UVs, Skalierung, Materialien und Platzierung.

**Bitte eine private Build-APK nicht als 1:1-Port weiterverbreiten.** Du müsstest die entsprechenden Rechte für Originalgrafiken und Originalaufnahmen haben. Der Import-Prozess ist für eine eigene, persönliche Kopie vorbereitet; wir haben bislang nur die Funktion des Audio-/Texturkonverters im kurzlebigen Windows-Analyseworker geprüft, nicht den kompletten privaten Android-Build.

## Geschwindigkeit und technische Diagnose

Die alte Fahrzeugphysik reduzierte Geschwindigkeit bereits bei Bodenkontakt. Dieser Fehler wurde behoben. Der GitHub-Test hat mit Vollgas einen RTW-Wert von etwa **120,6 km/h** gemessen. Zivilverkehr wurde auf programmierte **36 bis 68 km/h** gesetzt. Das HUD zeigt nun neben dem Tacho auch die **tatsächliche Bildrate**, um niedrige Smartphone-FPS von einem Fahrphysikproblem zu unterscheiden.

---

## APK per GitHub herunterladen

[GitHub Actions: Rettungsdienst Simulator – Android APK](https://github.com/nikl223-ctrl/LibreMediaConverter/actions/workflows/ambulance-android-apk.yml)

1. Öffne den neuesten **grünen** Build.
2. Klicke unter **Artifacts** auf `RettungsdienstSimulator-Android-APK`.
3. Entpacke das ZIP, öffne `RettungsdienstSimulator.apk` und installiere sie auf deinem Android-Handy.

**Das erste APK-Build enthält keine Originalgrafiken, Modell-Dateien oder Sounds** aus dem Windows-Spiel, sondern generierte Platzhalter. Die Engine kann nicht direkt das PC-Programm oder Vision-3D-Modelle ausführen.

## Spielfunktionen (erster Prototyp)

- 3D-Stadt von ca. 630 × 630 Metern; Straßen, Markierungen, Gebäude, Ampeln, Bäume.
- Umherfahrende Zivilfahrzeuge, Rettungswagen in 3 Varianten (RTW / NEF / KTW).
- 3D-Fahrzeugbewegung inkl. Beschleunigung, Bremse, Rückwärtsgang, Kollisionen.
- Blaulicht, synthetisches Martinshorn, synthetischer Motorsound.
- Kamera hinter dem Fahrzeug und Cockpitansicht.
- Mehrstufige Rettungseinsätze: Meldung, Einsatzort erreichen, Patient versorgen, Klinikfahrt, Karrierebelohnung.
- Karrierefortschritt lokal gespeichert.
- Android-Touch-Lenken (linker Joystick), Gas/Bremse (rechte Pedale), Kamera, Blaulicht, Martinshorn und R/D-Gangwahl.
- Debug-Tastatur: WASD, H Sirene, B Blaulicht, C Kamera, R Rückwärtsgang, T Patient versorgen.

## Originaldateien: *city.v* erfolgreich erkannt

Quelle: Der vom Nutzer bereitgestellte [Drive-Ordner](https://drive.google.com/drive/folders/1ddUvXS4sHtkEt8-4Wi4sOofu3JmWWcYm).

Auf einem separaten GitHub-**Windows-2022**-Worker wurden folgende Dateien **nur zur Analyse** heruntergeladen:

- `bin9/rtws_app.exe` (x86 Windows)
- `bin9/plugins/rtws_gamedll.vPlugin` (x86 Windows)
- `bin9/Vision90.dll` (x86 Windows)
- `data/city.v` (452,795,096 Byte)

Ergebnis: `city.v` ist ein mit **XOR 0x55** kodiertes **ZIP-Archiv** mit 9.650 Einträgen. Es umfasst unter anderem ca. 1.759 `.vmesh`, 412 `.dds`-Texturen, 54 `.png`-Bilder, 514 `.xml` und FMOD `.fsb`-Audio-Banks; auch `vehicles/rtw.xvd`, `vehicles/ktw.xvd` wurden gefunden.

Details über den Aufbau lassen sich in der [Windows-Analyse](https://github.com/nikl223-ctrl/LibreMediaConverter/actions/workflows/ambulance-windows-inspect.yml) nachlesen. Die Dateien sind nicht Teil des APKs und werden nicht öffentlich ins Repository kopiert.

### Konvertierung zu nativen Android-Ressourcen

- DDS kann üblicherweise in PNG/WebP oder mobile komprimierte Texturen umgewandelt werden.
- FSB-Banks können eventuell über einen FMOD-kompatiblen Decoder wie vgmstream in WAV/Ogg umgewandelt werden.
- Vision Engine `.vmesh/.model/.vmesh_data` sind proprietär; **noch kein getesteter Export** nach GLB/GLTF, ohne den das 1:1-Modell nicht verwendbar ist.
- Die `cluster.xml` und `city.xml` könnten Platzierungen enthalten, müssen aber erst detailliert ausgewertet werden.
- Originalgrafik und Sound aus einem kommerziellen Spiel dürfen nicht ohne passende Rechte öffentlich weiterverbreitet werden. Ein persönlicher Build mit solchen Assets muss deshalb mit den entsprechenden Nutzungsrechten und einer privaten Veröffentlichungsumgebung abgestimmt werden.

## Quellcode

- `scripts/main.gd`: Fahrer, Fahrphysik, Navigation, Sirene, Einsatzablauf, Speichern.
- `scripts/city.gd`: Straßen, Gebäude, Rettungswagen, Zivilverkehr, Licht.
- `scripts/hud.gd`: Touchsteuerung, Tachometer, Leitstelle, Minikarte.
- `tools/test_ambulance.gd`: echter Missionsablaufstest für GitHub.
- `tools/windows_inspect.ps1`: temporärer Download aus Google Drive mit bestehenden privaten GitHub-Secrets.
- `tools/decode_vision.py`: XOR-Dekodierung des ursprünglichen ZIPs und Dateitypenliste (ohne Veröffentlichung von Assets).
- `tools/inspect_city.py`: Headerprüfung zur Erkennung des Originalformats.

**Hinweis:** 60 FPS auf dem Galaxy S24 Ultra sind ein Optimierungsziel, keine bestätigte Messung. Noch fehlen hochdetaillierte 3D-Modelle, echte Fahrphysik und eine originalgetreue Rekonstruktion der Stadt.
