# Rettungsdienst Simulator Android · Eigenständige Neuprogrammierung

**Android-Spielprojekt** inspiriert vom PC-Titel „Rettungswagen-Simulator 2012“ (2011, Z-Software / astragon). Mit Godot 4.5.2 und ARM64-APK über GitHub Actions. Das ist **kein offizieller Port und keine 1:1-Version**.

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
