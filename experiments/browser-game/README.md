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

Die Google-Drive-Datei muss **das Weltformat `assets/world.json`** enthalten. Der Server liest ausschließlich die explizit konfigurierte ID, prüft JSON, hält maximal **2 MiB im RAM und auf Server-Festplatte** für 10 Minuten (einstellbar), lädt bei Bedarf neu und verwendet niemals die Token im Browser. **Nicht** die 35-GB-ATS-TAR als Level angeben. Für echte, größere Browser-Spiele wäre eine chunk-basierte Asset-API mit Zugriffskontrolle und Cache-Grenzen notwendig.

## Neu: Grafikschnittstelle erkennen, Datentransfer minimieren, Spielstand sichern

**Client-Grafikprüfung:** Bei jedem Seitenaufruf prüft JavaScript in einem
separaten Canvas auf WebGL2 und, sofern der Browser in einem sicheren Kontext
läuft, auf einen WebGPU-Adapter. Die Webseite meldet nur diese booleschen
Fähigkeiten an `POST /api/client`. Der Server muss dafür keine GPU haben und
kann weder eine GPU im PC aus der Ferne direkt lesen noch zuverlässig zwischen
echter Hardwarebeschleunigung und einem Software-Renderer unterscheiden.
Der Browser wählt dann für die Demo WebGPU, WebGL2 oder (als ausdrücklich
gekennzeichnete CPU-Notlösung) Canvas2D.

**Datenverkehr:** JavaScript/CSS werden nach dem ersten Laden mit HTTP
`Cache-Control: max-age=3600` im Browser zwischengespeichert; die Weltdatei
wird bis zu 300 Sekunden im Browser gecacht. ETags ermöglichen
`304 Not Modified` statt eines erneuten Transfers. Während des Fahrens
werden keine Videobilder, sondern lediglich alle 30 Sekunden ein kleiner
Spielstand übertragen. Die Webseite zeigt eine Schätzung des tatsächlichen
HTTP-Datentransfers des Browser-Tabs an, und `GET /api/stats` zeigt die
ausgelieferten Bytes des Servers insgesamt (über alle Geräte). Beim ersten
Aufruf müssen **alle benötigten Spieldaten trotzdem übertragen werden**;
bei großen Spielen kann das beträchtlich sein.

**Google Drive:** Nur das explizit konfigurierte maximal 2-MiB-Demo-Level
wird aus Drive abgerufen. Der Server speichert es zusätzlich zu seinem
RAM-Cache dauerhaft in `.runtime/drive` und liest den Disk-Cache bei
einem Neustart innerhalb des konfigurierten TTL wieder. So wird Drive nicht
bei jedem Start unnötig belastet. Beispiel:

```bash
export BROWSER_GAME_DATA_DIR=/var/lib/truck-browser
export DRIVE_LEVEL_FILE_ID='ID_EINER_KLEINEN_WORLD_JSON'
export GOOGLE_CLIENT_ID='...'
export GOOGLE_CLIENT_SECRET='...'
export GOOGLE_REFRESH_TOKEN='...'
HOST=0.0.0.0 PORT=8765 python3 server.py
```

**Spielstände:** `POST /api/session` stellt eine zufällige Demo-Sitzung bereit;
`GET/POST /api/save` liest/schreibt vier begrenzte Zahlenwerte. Die Datei
liegt unter `BROWSER_GAME_DATA_DIR/saves`. Der Browser behält einen anonymen
Sitzungsschlüssel in localStorage. Der explizite Button „Spiel beenden und
speichern“ ist zuverlässiger als die automatische Sicherung beim Schließen.
**Das ist keine Steam Cloud und kein Steam-Login.**

**Sicherheitsgrenze:** Die Demo hat noch kein produktionsreifes Benutzer-Login.
Im Internet nie direkt ohne HTTPS, Proxy-Zugriffsschutz und Ressourcenlimits
öffentlich freigeben. Für Xbox Edge im LAN ist die Verfügbarkeit der
WebGPU/WebGL-Funktionen geräte- und browserabhängig; die Unterstützung ist
hier nicht auf realer Xbox-Hardware getestet.

## Auf deinem Linux-Server (Docker, keine GPU notwendig)

Der Testserver läuft als nicht privilegierter Benutzer in einem Container,
mit einem persistenten Daten-Volume für Cache und Spielstände. Alle
Grafikberechnungen finden im Browser des jeweiligen Geräts statt. Die GPU
des Linux-Servers ist nicht nötig.

```bash
git clone https://github.com/nikl223-ctrl/LibreMediaConverter.git
cd LibreMediaConverter/experiments/browser-game
cp .env.example .env
docker compose up -d --build
curl http://127.0.0.1:8765/health
```

**Nur im privaten LAN:** In der `.env` `BIND_HOST=0.0.0.0` setzen,
`docker compose up -d --build` erneut ausführen und im Windows-11- oder
Xbox-Edge-Browser `http://LINUX-SERVER-LAN-IP:8765/` öffnen. Nur auf
vertrauenswürdigen LANs verwenden und per Firewall auf das LAN begrenzen.
Bei einem entfernten Server im Rechenzentrum ist das **nicht** genug;
dann HTTPS mit Zugriffsschutz einsetzen.

**Über das Internet von Windows und Xbox:**

1. Eine eigene Domain oder Subdomain per A/AAAA auf die IP des Servers
   zeigen lassen. TCP 80 und 443 (und optional UDP 443) in der Firewall
   für das automatische HTTPS-Zertifikat zulassen.
2. In `.env` `SITE_DOMAIN=deine-domain.example` setzen.
3. Mit `docker run --rm -it caddy:2 caddy hash-password` einen
   BCrypt-Passworthash erstellen. Den Hash in der `.env` als
   `BASIC_AUTH_HASH='...'` eintragen (einfaches Anführungszeichen
   schützt die enthaltenen `# Truck Browser Proof – Kein Cloud Gaming

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

Die Google-Drive-Datei muss **das Weltformat `assets/world.json`** enthalten. Der Server liest ausschließlich die explizit konfigurierte ID, prüft JSON, hält maximal **2 MiB im RAM und auf Server-Festplatte** für 10 Minuten (einstellbar), lädt bei Bedarf neu und verwendet niemals die Token im Browser. **Nicht** die 35-GB-ATS-TAR als Level angeben. Für echte, größere Browser-Spiele wäre eine chunk-basierte Asset-API mit Zugriffskontrolle und Cache-Grenzen notwendig.

## Neu: Grafikschnittstelle erkennen, Datentransfer minimieren, Spielstand sichern

**Client-Grafikprüfung:** Bei jedem Seitenaufruf prüft JavaScript in einem
separaten Canvas auf WebGL2 und, sofern der Browser in einem sicheren Kontext
läuft, auf einen WebGPU-Adapter. Die Webseite meldet nur diese booleschen
Fähigkeiten an `POST /api/client`. Der Server muss dafür keine GPU haben und
kann weder eine GPU im PC aus der Ferne direkt lesen noch zuverlässig zwischen
echter Hardwarebeschleunigung und einem Software-Renderer unterscheiden.
Der Browser wählt dann für die Demo WebGPU, WebGL2 oder (als ausdrücklich
gekennzeichnete CPU-Notlösung) Canvas2D.

**Datenverkehr:** JavaScript/CSS werden nach dem ersten Laden mit HTTP
`Cache-Control: max-age=3600` im Browser zwischengespeichert; die Weltdatei
wird bis zu 300 Sekunden im Browser gecacht. ETags ermöglichen
`304 Not Modified` statt eines erneuten Transfers. Während des Fahrens
werden keine Videobilder, sondern lediglich alle 30 Sekunden ein kleiner
Spielstand übertragen. Die Webseite zeigt eine Schätzung des tatsächlichen
HTTP-Datentransfers des Browser-Tabs an, und `GET /api/stats` zeigt die
ausgelieferten Bytes des Servers insgesamt (über alle Geräte). Beim ersten
Aufruf müssen **alle benötigten Spieldaten trotzdem übertragen werden**;
bei großen Spielen kann das beträchtlich sein.

**Google Drive:** Nur das explizit konfigurierte maximal 2-MiB-Demo-Level
wird aus Drive abgerufen. Der Server speichert es zusätzlich zu seinem
RAM-Cache dauerhaft in `.runtime/drive` und liest den Disk-Cache bei
einem Neustart innerhalb des konfigurierten TTL wieder. So wird Drive nicht
bei jedem Start unnötig belastet. Beispiel:

```bash
export BROWSER_GAME_DATA_DIR=/var/lib/truck-browser
export DRIVE_LEVEL_FILE_ID='ID_EINER_KLEINEN_WORLD_JSON'
export GOOGLE_CLIENT_ID='...'
export GOOGLE_CLIENT_SECRET='...'
export GOOGLE_REFRESH_TOKEN='...'
HOST=0.0.0.0 PORT=8765 python3 server.py
```

**Spielstände:** `POST /api/session` stellt eine zufällige Demo-Sitzung bereit;
`GET/POST /api/save` liest/schreibt vier begrenzte Zahlenwerte. Die Datei
liegt unter `BROWSER_GAME_DATA_DIR/saves`. Der Browser behält einen anonymen
Sitzungsschlüssel in localStorage. Der explizite Button „Spiel beenden und
speichern“ ist zuverlässiger als die automatische Sicherung beim Schließen.
**Das ist keine Steam Cloud und kein Steam-Login.**

**Sicherheitsgrenze:** Die Demo hat noch kein produktionsreifes Benutzer-Login.
Im Internet nie direkt ohne HTTPS, Proxy-Zugriffsschutz und Ressourcenlimits
öffentlich freigeben. Für Xbox Edge im LAN ist die Verfügbarkeit der
WebGPU/WebGL-Funktionen geräte- und browserabhängig; die Unterstützung ist
hier nicht auf realer Xbox-Hardware getestet.

-Zeichen vor Compose-Interpolation).
4. `docker compose -f compose.yaml -f compose.public.yaml up -d --build`
   ausführen. Danach die Domain über `https://` auf dem PC oder
   in Xbox Edge öffnen, mit dem Benutzernamen **gamer** und dem
   selbst gewählten Passwort anmelden und auf „Spielen“ drücken.

Die Caddy-Konfiguration schützt die Demo per HTTPS und Basic Auth. Für einen
produktiven Multiuser-Dienst wären darüber hinaus Benutzerverwaltung,
Quota/Rate-Limits und Geheimnisverwaltung notwendig. **Keine Steam-Logins
oder Passwörter auf dieser Demo-Webseite eingeben.**

Die nativen Steam-/ETS-/ATS-Dateien sind kein Browser-Spiel: Auch bei einem
funktionierenden Xbox-WebGL2-Test sind diese Titel dadurch nicht direkt
spielbar. Die tatsächliche Xbox-Unterstützung muss am Gerät geprüft werden.

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
