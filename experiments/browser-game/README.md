# Linux CPU-only → Browser-GPU Demonstration

Ein selbst entwickeltes kleines Fahrspiel. Der Linux-Server benötigt weder
GPU noch GPU-Treiber. Windows 11 und Xbox Edge können dieselbe Webseite
laden; die Browsergrafik wird mit WebGPU/WebGL2 gerendert (wenn verfügbar).

**Kein universeller Steam-/ETS2-/ATS-Spielstarter.** Die Kompatibilität auf
einer echten Xbox Series X ist noch nicht überprüft. Ein GitHub-Runner kann
WebGL mittels Softwareemulation ausführen.

## Zwei Betriebsarten

- **Client-Modus:** Der Browser berechnet die Bewegung und rendert selbst.
- **Remote-CPU-Modus:** Im Startfenster „Simulation auf Linux-CPU ausführen“
  aktivieren oder die URL um ?remote=1 ergänzen. Die Linux-CPU berechnet
  Fahrzeugposition und Geschwindigkeit, der Browser zeichnet die 3D-Welt.
  Ungefähr zehnmal pro Sekunde sendet er Gas, Bremse und Lenkeingabe über
  HTTP; zurück kommen kleine numerische Positionsdaten. Der Server schickt
  keine Video-Frames. Die eigentliche Spiele-Engine dieser Demo ist jedoch
  für diesen Modus speziell programmiert.

## Docker auf deinem Linux-Server

Voraussetzung: Docker samt Compose-Plugin. Kein GPU-Zugriff nötig.

    git clone https://github.com/nikl223-ctrl/LibreMediaConverter.git
    cd LibreMediaConverter/experiments/browser-game
    cp .env.example .env
    docker compose up -d --build
    curl http://127.0.0.1:8765/health

Standardmäßig ist der Dienst nur am Server selbst (127.0.0.1:8765)
erreichbar. Für ein vertrauenswürdiges privates LAN in .env
BIND_HOST=0.0.0.0 eintragen und Docker Compose neu starten. Danach:

    http://LAN-IP-DES-SERVERS:8765/?remote=1

Auf dem Windows-11-PC oder in Xbox Edge öffnen. Zugriff per Firewall
auf das LAN begrenzen.

Bei Servern, die über das Internet statt ein privates LAN erreicht werden,
unbedingt HTTPS und Anmeldeschutz einsetzen. Für eine eigene Domain liegen
Caddyfile und compose.public.yaml bei. Domain-DNS, Ports 80/443 und einen
starken BCrypt-Passworthash in der lokalen .env konfigurieren:

    docker run --rm -it caddy:2 caddy hash-password
    docker compose -f compose.yaml -f compose.public.yaml up -d --build

Keine Passwörter oder OAuth-Geheimnisse in GitHub hochladen.

## Google Drive, Cache und Datenverbrauch

- Die Demo-Leveldatei wird beim Start vom Server geladen, statische
  JavaScript/CSS-Dateien über HTTP-Cache und ETag zwischengespeichert.
- Optional holt der Server ein explizit konfiguriertes kleines world.json
  (maximal 2 MiB) über Google OAuth von Drive. Nur die auf dem Server
  konfigurierte Datei wird abgerufen; die geheimen Tokens bleiben dort.
- Eine echte Steam-/ETS2-Installation kann nicht als world.json verwendet
  und über WebGPU automatisch ausführbar gemacht werden.
- Bei aktivem Remote-CPU-Modus werden nur kleine Kontroll- und
  Zustandsnachrichten geschickt, nicht jede einzelne Grafikausgabe.
- Unter /api/stats stehen Zähler für Remote-Schritte und ausgelieferte
  HTTP-Payload-Bytes. TCP/IP/TLS/HTTP-Header und Internet-Overhead sind
  dort nicht enthalten. Bei großen Spielen müssen Modelle, Texturen und
  Spielcode zusätzlich auf dem Client vorhanden sein.
- Der Browser stellt keine verlässliche physische GPU-Identifikation bereit.
  Er prüft, ob WebGPU oder WebGL2 verfügbar ist; Canvas2D-CPU-Fallback
  ist keine GPU-Beschleunigung.

Für Drive in der lokalen .env folgende Einstellungen bei Bedarf
ergänzen: DRIVE_LEVEL_FILE_ID, GOOGLE_CLIENT_ID,
GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN, DRIVE_CACHE_SECONDS=600.

## Steuerung, Speicherstände und Tests

W/S/A/D, Pfeiltasten, Gamepad und Touch funktionieren bei der Demo.
Spielstand-Speichern/Beenden legt kleine Zustandsdateien im persistenten
Docker-Volume ab. Automatisches Speichern läuft alle 30 Sekunden.
Keine Steam-Cloud-Synchronisation und kein Steam-Login.

    python3 -m unittest discover -s tests -v
    python3 -m pip install playwright
    python3 -m playwright install --with-deps chromium
    python3 tests/browser_smoke.py

GitHub Actions prüft den Linux-Container und die Browser-Demo. Eine echte
Xbox-Series-X-Hardwareprüfung ist damit nicht verbunden.

**Technische Grenze:** Der Server kann seine CPU nicht pauschal an die
GPU eines fremden Geräts koppeln, um native Windows-/Steam-Spiele ohne
eigene Engine-Anpassung im Browser auszuführen. Dieser Prototyp beweist
nur die gezielt entwickelte CPU-Server/GPU-Browser-Aufteilung.
