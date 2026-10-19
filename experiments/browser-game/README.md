# Truck Browser Proof – Kein Cloud Gaming

Ein testbarer, eigenständiger Prototyp für einen **GPU-losen Dateiserver** und ein **im Client gerendertes Browser-Spiel**. Enthält **keine ETS-/ATS-/Steam-Dateien**, sondern eine kleine selbst erstellte 3D-Szene mit fahrbarem Truck und Gamepad-Unterstützung.

## Starten

```bash
cd experiments/browser-game
python3 server.py
```

Im Browser `http://127.0.0.1:8765/` öffnen. Zur Nutzung von anderen Geräten im LAN `HOST=0.0.0.0 PORT=8765 python3 server.py` ausführen und `http://SERVER-IP:8765` öffnen. Ein öffentlich erreichbarer Server benötigt **HTTPS und Zugriffsschutz**. WebGPU ist nur in sicheren Kontexten verfügbar (localhost oder HTTPS), sonst verwendet die Demo nach Möglichkeit WebGL2.

W/↑ beschleunigen, S/↓ bremsen, A/D oder ←/→ lenken; Controller und Touch-Buttons unterstützt. Der Server schickt Dateien und berechnet keine Grafikframes. Ein HTTP-Range-Endpunkt unterstützt Teilabrufe. `GET /api/stats` zeigt die übertragenen Bytes.

## Optional: Welt-Datei aus Google Drive, nur serverseitig

```bash
export DRIVE_LEVEL_FILE_ID='DEINE_JSON_DATEI_ID'
export GOOGLE_CLIENT_ID='...'
export GOOGLE_CLIENT_SECRET='...'
export GOOGLE_REFRESH_TOKEN='...'
export DRIVE_CACHE_SECONDS=600
python3 server.py
```

Die Google-Drive-Datei muss **das Weltformat `assets/world.json`** enthalten. Der Server liest ausschließlich die explizit konfigurierte ID, prüft JSON, hält maximal **2 MiB im RAM** für 10 Minuten (einstellbar), lädt bei Bedarf neu und verwendet niemals die Token im Browser. **Nicht** die 35-GB-ATS-TAR als Level angeben. Für echte, größere Browser-Spiele wäre eine chunk-basierte Asset-API mit Zugriffskontrolle und Cache-Grenzen notwendig.

## Tests

```bash
python3 -m unittest discover -s tests -v
python3 -m pip install playwright
python3 -m playwright install chromium
python3 tests/browser_smoke.py
```

Die GitHub-Action führt beide Tests auf dem Runner aus. `browser_smoke.png` zeigt einen realen Headless-Chromium-Browser mit WebGL2-/WebGPU-Ausgabe. Ein softwarebasierter Testadapter ist möglich: Das bestätigt den Browser-Rendering-Pfad, aber **nicht** die Geschwindigkeit einer Xbox oder die tatsächliche Hardware-GPU deines PCs.

## Grenzen: ETS2/ATS/Steam

Eine `.exe` aus ETS2/ATS ist **kein** WebAssembly-Modul. Das Hinzufügen einer `.dll` oder eines WebGPU-Wrappers zu den Daten reicht nicht, um sie in Edge/Chrome auszuführen. Dafür bräuchte man die portierbare Spielengine mit Quellcode und die Anpassung von Windows-/Steam-/DirectX-/Vulkan-Aufrufen; die Engine von ETS2/ATS ist nicht öffentlich dafür verfügbar. Ein Browser kann auch nicht einfach Steam installieren oder die Windows-EXE auf einer Xbox ausführen. Die Daten müssen beim Client eintreffen; dass die Daten auf Drive liegen, spart **nicht** automatisch Bandbreite. Als PC-only-Alternative könnte die Webseite eine lokale Hilfsanwendung ansprechen, die das native Spiel **auf dem PC** startet; das funktioniert nicht ohne Installation und nicht auf Xbox.

Dieser Prototyp beweist die technisch mögliche Architektur für **Browser-kompatible Spiele**: Server-Dateien → Browser-Engine → Client-GPU.
