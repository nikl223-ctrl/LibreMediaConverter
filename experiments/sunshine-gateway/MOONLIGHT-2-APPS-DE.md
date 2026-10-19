# Moonlight mit fester Gateway-IP und zwei getrennten Anwendungen

## Was die Architektur leistet

Dein kleiner 1-vCPU-/2-GB-RAM-Server bleibt die **feste Adresse** in Moonlight. Dieser Gateway leitet TCP/UDP an die feste interne WireGuard-IP des autorisierten Compute-Rechners weiter. Auf dem Compute-Rechner läuft Sunshine und präsentiert:

- **GeForce NOW**
- **Xbox Cloud Gaming**

Erst wenn du in Moonlight einen Eintrag wählst, startet der jeweilige Browser auf dem Compute-Rechner. Sunshine kodiert dort den Desktop. Der Gateway dekodiert keine Frames; CPU-Belastung durch Paketweiterleitung und ggf. WireGuard bleibt dennoch möglich.

Ein **GitHub-hosted Actions-Worker** kann für diese Gaming-Session nicht eingesetzt werden. GitHub Actions dient hier nur der Entwicklung und dem automatisierten Test.

## Warum Moonlight immer dieselbe IP verwendet

Moonlight speichert nur die **öffentliche IP oder die VPN-IP deines bisherigen Gateways**. Die NAT-Konfiguration auf dem Gateway leitet die GameStream-Ports an die WireGuard-IP des Compute-Rechners weiter. Eine wechselnde öffentliche IP des Compute-Rechners muss Moonlight nicht kennen.

Der Compute-Rechner muss erreichbar sein und Sunshine **bereits ausführen**, damit Moonlight eine Liste mit GeForce NOW und Xbox Cloud Gaming abrufen kann. Bei einem vollständig abgeschalteten Compute-Rechner muss dieser zunächst per `python3 cloudgamingctl.py start` (nach Provisionierung und aktiver SSH-Verbindung) aktiviert werden. Ein unmittelbarer automatischer Rechnerstart aus dem ersten Moonlight-Verbindungsversuch ist **noch nicht implementiert**.

## Einmalige Vorbereitung auf dem externen Compute-Rechner

Installiere Sunshine, Chromium/Chrome und eine funktionierende grafische Linux-Sitzung. Einrichtung und SSH-/WireGuard-Voraussetzungen stehen in [SETUP-DE.md](SETUP-DE.md).

Aktualisiere zunächst die Skripte aus diesem Experiment-Branch. Installiere folgende Dateien als der Sunshine-Desktop-Benutzer:

```bash
cd "$HOME/cloudgaming-tools/experiments/sunshine-gateway"
install -m 755 cloudgaming-app "$HOME/.local/bin/cloudgaming-app"
install -m 755 cloudgaming-session-launch "$HOME/.local/bin/cloudgaming-session-launch"
install -m 644 cloudgaming-session.service "$HOME/.config/systemd/user/cloudgaming-session.service"
systemctl --user daemon-reload
```

**Vor Änderungen** die vorhandenen Sunshine-Anwendungen sichern, das bisherige JSON nicht überschreiben, bevor es geprüft wurde:

```bash
mkdir -p "$HOME/.config/sunshine"
cd "$HOME/cloudgaming-tools/experiments/sunshine-gateway"
apps="$HOME/.config/sunshine/apps.json"
if [ -f "$apps" ]; then
  cp -a "$apps" "$apps.backup.$(date +%Y%m%d-%H%M%S)"
  python3 make_sunshine_apps.py --existing "$apps" > "$HOME/sunshine-apps-reviewed.json"
else
  python3 make_sunshine_apps.py > "$HOME/sunshine-apps-reviewed.json"
fi
python3 -m json.tool "$HOME/sunshine-apps-reviewed.json" >/dev/null
```

Die Datei `$HOME/sunshine-apps-reviewed.json` prüfen. Wenn alles stimmt, Sunshine vor dem Austausch der Apps-Liste geordnet beenden, die neue Datei installieren und Sunshine wieder starten:

```bash
install -m 600 "$HOME/sunshine-apps-reviewed.json" "$HOME/.config/sunshine/apps.json"
systemctl --user restart cloudgaming-session.service
```

Der letzte Befehl funktioniert nur, wenn die systemd-Unit bereits installiert ist und die grafische Sitzung in ihrer Umgebung verfügbar ist. Läuft Sunshine bereits über einen anderen Dienst, muss Codex zuerst sicherstellen, dass nicht **zwei** Instanzen auf denselben Ports starten. Moonlight-Pairings und Konfigurationsschlüssel bleiben auf dem starken Rechner erhalten; verändere sie nicht ohne Sicherung.

## Verwendung

1. Starken Rechner einschalten/bereitstellen und die SSH-/WireGuard-Verbindung herstellen.
2. Auf deinem kleinen Gateway `python3 cloudgamingctl.py start` ausführen, sofern Remote-Sunshine noch nicht läuft.
3. In Moonlight deinen **bisherigen Gateway-Server** auswählen (oder seine IP einmalig hinzufügen).
4. **GeForce NOW** oder **Xbox Cloud Gaming** antippen. Sunshine startet nur diesen Browser auf dem leistungsstarken Host.
5. Nach Abschluss in Moonlight die Anwendung ausdrücklich **beenden** (Quit Game), statt die Verbindung nur zu unterbrechen. Das beendet den gestarteten App-Prozess; ein einfacher Disconnect kann die Anwendung zum Wiederverbinden aktiv lassen.
6. Beim Wechsel zu einer anderen App startet **ein neuer** bis zu sechs Stunden laufender Browserprozess mit eigener Zeitbegrenzung.
7. Wenn du die komplette Sitzung/Remote-Sunshine beenden möchtest, verwende `python3 cloudgamingctl.py stop`. Das schaltet den Compute-Rechner selbst nicht aus.

Der Browser verwendet pro Dienst einen persistenten Profilordner: `~/.local/share/cloudgaming/geforce-now` beziehungsweise `~/.local/share/cloudgaming/xbox-cloud`. **Einmalige Anmeldung auf dem starken Rechner ist erforderlich**. Chrome-Profile lassen sich nicht zuverlässig einfach zwischen fremden Linux-Hosts kopieren, weil Cookies und Tokens teilweise an lokale Schlüsselverwaltung gebunden sind. Keine Passwörter/Session-Cookies in GitHub Secrets, Git-Historie oder Worker-Artefakte übertragen. Dienste können Re-Login oder Zwei-Faktor-Prüfung verlangen.

Die Sechs-Stunden-Begrenzung beginnt **beim Start der jeweiligen Moonlight-App**, nicht beim Start des Sunshine-Hintergrunddienstes. Sunshine selbst darf für die App-Auswahl weiterlaufen. Nach sechs Stunden beendet sich der Browserprozess; Sunshine kann anschließend eine neue Session anbieten. Automatische kostenpflichtige Compute-Server-Provisionierung, Abschaltung und Ersatzrechner-Migration sind **noch nicht implementiert** und erfordern die APIs/Einverständnis des tatsächlich genutzten Hostinganbieters.

## Wichtige technische Grenzen

- **Eine feste Eingangs-IP ist technisch möglich**, eine jederzeit erreichbare Anwendungsliste setzt aber einen erreichbaren Sunshine-Host voraus. Das reine NAT-Gateway zeigt keine Apps an.
- Bleibt bei einem Backendwechsel der Sunshine-Pairing-Schlüssel nicht identisch, kann Moonlight eine **erneute Kopplung** verlangen. Die Kopplung gehört dem Sunshine-Host, nicht dem Gateway.
- Die Sunshine-Konfigurationsoberfläche auf TCP 47990 **nicht öffentlich freigeben**. Für Pairing auf einem Remote-Host eine vertrauenswürdige VPN-/SSH-Verbindung verwenden.
- Bei Moonlight- oder Internetproblemen die tatsächlichen Forwarding-Ports, Firewall/FORWARD-Regeln, WireGuard-MTU, Zertifikatsidentität, Audio, Controller und CPU-Auslastung prüfen.
- Ein Internet-Cloud-Gaming-Stream, der anschließend nochmals mit Sunshine an Moonlight kodiert wird, fügt mindestens einen weiteren Kodierungs-/Dekodierungsschritt hinzu. Konstante 60 FPS und perfekte Input-Synchronität müssen live gemessen werden; GitHub-CI beweist das nicht.
- Bei 1 vCPU kann **auch WireGuard-Verschlüsselung** einen messbaren Anteil der CPU verbrauchen. Falls sie zu hoch ist, den Moonlight-Datenverkehr direkt zum Remote-Sunshine-Rechner routen und nur die Steuerebene über den kleinen Gateway führen.

## Zuordnung Quellcode

- `make_sunshine_apps.py` erzeugt die zwei Moonlight-Kacheln, ohne vorhandene Sunshine-Apps zu löschen.
- `cloudgaming-app` startet Chrome/Chromium mit eigenem Profil und 6-Stunden-Limit.
- `cloudgaming-session-launch` startet lediglich Sunshine; der Gaming-Browser startet **erst bei App-Auswahl**.
- `cloudgamingctl.py` steuert Remote-Sunshine per SSH.
- `render_nft.py` erzeugt Beispielregeln für die feste Gateway-IP.
- `stream_health.py` überwacht Gateway-CPU/Netzwerk. Siehe [PERFORMANCE-DE.md](PERFORMANCE-DE.md).
