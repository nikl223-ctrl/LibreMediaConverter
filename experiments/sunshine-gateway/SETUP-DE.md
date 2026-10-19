# Ein-Befehl-Cloud-Gaming: Sunshine + Moonlight

## Zweck und ehrliche Grenzen

Der alte Linux-Server (1 vCPU / 2 GiB RAM) behält die bisherige Moonlight-Einstiegsadresse und leitet Daten im Kernel per WireGuard/nftables weiter. Ein autorisierter stärkerer Linux-Rechner betreibt die **gesamte** Grafik-Session: Chromium + GeForce NOW/Xbox Cloud Gaming + Sunshine. Die CPU/RAM-Ausstattung der alten VM wird NICHT erweitert. Der Gateway-Server muss Netzwerkverkehr und ggf. WireGuard-Verschlüsselung verarbeiten; damit ist seine Last klein, aber nicht null.

Ein Startbefehl auf dem alten Server reicht **nach einmaliger Installation**. Nach 6 Stunden stoppt systemd die Sitzung; der starke Rechner selbst wird dadurch **nicht** beim Cloud-Anbieter gelöscht. Dafür ist dessen Verwaltungs-API erforderlich.

GitHub Actions dient ausschließlich Software-Tests. Verwende einen tatsächlich verfügbaren, von dir autorisierten externen Rechner.

## Voraussetzung auf dem starken Rechner

- Linux mit einer bereits funktionierenden grafischen Sitzung (X11/Wayland/Virtual Display), Sunshine, Chromium und Audio.
- Eine geeignete GPU mit **Videoencoder**, z.B. NVIDIA L4/T4 oder RTX. Achtung: NVIDIA H100/H200 hat **kein NVENC**; ggf. Software-Encoding oder anderen Host wählen.
- WireGuard-Tunnel zum alten Gateway, erreichbar über die **VPN-IP** des starken Rechners. Beispiel-IP im Quellcode ist **keine** bekannte echte IP.
- SSH vom alten Server per Key zum dedizierten, unprivilegierten Desktop-Nutzer auf dem starken Rechner.
- Bestehende Sunshine-Konfiguration (standardmäßig `~/.config/sunshine`) und Chromium-Profil müssen auf **persistenter, zugriffsgeschützter, möglichst verschlüsselter Platte** verbleiben.
- Vor Änderungen alte Sunshine-Konfiguration sichern. Das bestehende Sunshine auf dem kleinen Server darf während des Tests nicht mit den weitergeleiteten Ports kollidieren.
- Kein Kopieren von Chrome-Passwörtern, Cookies oder Sessions nach GitHub. Bei **erstmaliger** Verwendung auf dem starken Rechner ist eine normale Browser-Anmeldung nötig; später sollte das Profil diese behalten, aber Dienste können jederzeit Re-Login/MFA anfordern. Beim **Wechsel auf einen anderen** externen Host funktioniert das nicht automatisch.

## Einmalige Installation durch Codex / Administrator

Auf dem starken Rechner, als der Sunshine-Desktop-Benutzer:

```bash
git clone --branch experiment/sunshine-gateway-20261019 --single-branch \
  https://github.com/nikl223-ctrl/LibreMediaConverter.git "$HOME/cloudgaming-tools"
cd "$HOME/cloudgaming-tools/experiments/sunshine-gateway"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 755 cloudgaming-session-launch "$HOME/.local/bin/cloudgaming-session-launch"
install -m 644 cloudgaming-session.service "$HOME/.config/systemd/user/cloudgaming-session.service"
systemctl --user daemon-reload
# Dies startet noch KEIN Spiel. Unit absichtlich nicht dauerhaft 'enable'-n.
```

Remote-Kontrollprogramm auf dem starken Rechner in den systemweiten PATH installieren (mit Administratorrechten):

```bash
sudo install -m 755 cloudgaming-remote-control /usr/local/bin/cloudgaming-remote-control
```

Den Desktop-User-Systemd-Bus sicherstellen, ggf. durch den Administrator `loginctl enable-linger <desktop-user>` (nur wenn notwendig). Die systemd-Unit setzt beispielhaft `DISPLAY=:0` und `XAUTHORITY=%h/.Xauthority`; das muss Codex anhand der **tatsächlichen Desktop-Sitzung** prüfen und ggf. korrigieren. Ohne funktionierende grafische Sitzung kann Sunshine nicht einfach ein Cloud-Gaming-Bild erfassen.

Auf dem kleinen Gateway-Server:

```bash
git clone --branch experiment/sunshine-gateway-20261019 --single-branch \
  https://github.com/nikl223-ctrl/LibreMediaConverter.git "$HOME/cloudgaming-tools"
cd "$HOME/cloudgaming-tools/experiments/sunshine-gateway"
mkdir -p "$HOME/.config/cloudgaming-gateway"
cp cloudgaming-config.example.json "$HOME/.config/cloudgaming-gateway/config.json"
chmod 700 "$HOME/.config/cloudgaming-gateway"
chmod 600 "$HOME/.config/cloudgaming-gateway/config.json"
```

`config.json` an die eigenen SSH-Zugangsdaten, starke WireGuard-IP und den richtigen Benutzernamen anpassen. Lege einen SSH-Key an, wenn noch keiner besteht; füge **nur den Public Key** der Authorized-Keys-Datei des dedizierten Remote-Benutzers hinzu. Vertraue dem SSH-Hostkey erst nach Überprüfung.

Der alte Gateway benötigt außerdem die mit `render_nft.py` generierte und vom Administrator **bewusst freigegebene** nftables-NAT-Konfiguration, IP-Forwarding und FORWARD-Firewallregeln. Lies die andere README im gleichen Ordner. **Nicht** ungeprüft existierende Firewallregeln überschreiben oder sämtliche Ports freigeben. Sunshine-Webverwaltung-Port 47990 bleibt geschlossen. Moonlight wird ggf. einmalig gegen Sunshine auf dem starken Rechner gepairt; Sunshine-Schlüssel auf diesem Rechner bleiben dann persistent.

## Danach: ein Befehl auf dem kleinen Gateway

```bash
cd "$HOME/cloudgaming-tools/experiments/sunshine-gateway"
python3 cloudgamingctl.py start
```

Weitere Befehle:

```bash
python3 cloudgamingctl.py status
python3 cloudgamingctl.py logs
python3 cloudgamingctl.py stop
```

Der starke Rechner startet Sunshine und den Browser in seiner vorhandenen grafischen Sitzung. Die Unit begrenzt **jede** Sitzung mit `RuntimeMaxSec=6h`. Erneutes `start` nach Ablauf erzeugt eine neue Sitzung; keine GitHub-Worker-Rotation oder Umgehung von Nutzungsbeschränkungen.

Browserprofil: `~/.local/share/cloudgaming/chromium-profile` auf dem starken Host. Sunshine-Keys: `~/.config/sunshine`. Beide werden nicht gelöscht. Diese Persistenz bedeutet ausdrücklich, dass bei einem Hostwechsel ohne gemeinsamen verschlüsselten Speicher **keine** nahtlose Sitzung garantiert werden kann.

## Tests

```bash
cd "$HOME/cloudgaming-tools/experiments/sunshine-gateway"
python3 -m unittest discover -s . -p 'test_*.py' -v
python3 cloudgamingctl.py start --dry-run
```

Die GitHub CI prüft Steuerung und Routingregel-Generierung **ohne echte Serververbindung**. Ein vollständiger Sunshine/Moonlight/GeForce-NOW-Test erfordert echten SSH-, WireGuard- und Gaming-Host-Zugriff.
