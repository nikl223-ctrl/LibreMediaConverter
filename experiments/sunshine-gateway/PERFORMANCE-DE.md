# Stabiler Moonlight-Stream: Bild, Ton, Controller, 60 FPS

## Ziel

- Sunshine + Cloud-Gaming-Browser + Grafikdarstellung + Audio + Video-Encoding laufen gemeinsam auf einem geeigneten **externen Rechenserver**.
- Moonlight zeigt 60 Bilder pro Sekunde, sofern auch das Cloud-Gaming-Angebot sie stabil liefert.
- Der kleine Linux-Server ist nur der bisherige Zugangspunkt und leitet IP-Pakete über die WireGuard-/nftables-Konfiguration weiter. Er betreibt **keine** Chromium- und Sunshine-Bildverarbeitung mehr.
- Controller-Eingaben, Audio und Videopakete nutzen die Moonlight/Sunshine-Protokollverbindungen in **beide Richtungen**.
- Bei Audio-, FPS- und Latenzproblemen wird **vor** Änderungen gemessen.

**Wichtig:** Stabilität und Input-to-Photon-Latenz werden nicht durch CI-Tests garantiert. Dafür braucht man die tatsächliche GPU, die laufende Anwendung, die Verbindung und einen Moonlight-Client.

## Einmalig auf der Remote-Maschine prüfen

1. Cloud-Gaming-Browser mit nutzbarer **hardwarebeschleunigter Videodekodierung**. Prüfe insbesondere 60-FPS-Wiedergabe des GeForce-NOW- bzw. Xbox-Cloud-Streams in Chromium.
2. Sunshine mit einem **funktionierenden Hardwareencoder** (NVENC, VAAPI, QSV, Vulkan, je nach echter Maschine), vorzugsweise H.264 1080p60. Nicht einfach `encoder = nvenc` setzen, wenn kein NVIDIA-Encoder existiert.
3. Sunshine muss den tatsächlich verwendeten Desktop oder virtuellen Display erfassen können. Konfiguriere 1920×1080/60 Hz an der grafischen Ausgabe, sofern unterstützt.
4. Verwende einen gewöhnlichen, persistenten Benutzer-Desktop, einen stabilen Audioausgang und einen persistierenden Browser-Profilordner, der nicht bei jedem Sessionstart gelöscht wird.
5. Kopple Moonlight einmalig mit Sunshine auf dem starken Rechner; die Sunshine-Pairing-Keys bleiben auf dem **starken** Host, auch wenn die Session nach 6 Stunden stoppt. Ein Wechsel auf einen anderen Rechner ohne dieselben autorisierten Schlüssel kann eine neue Kopplung verlangen.
6. Für einen möglichst konstanten Frame-Takt: Host-Display 60 Hz, Moonlight 60 FPS, Cloud-Gaming-Ausgabe idealerweise 60 FPS. Sunshine erzeugt keine fehlenden Quellbilder neu; Desktop-Inaktivität kann niedrigere FPS melden.
7. Vermeide doppeltes Encoding. Der externe Browser dekodiert die eingehenden Bilder einmal; Sunshine encodiert den erfassten Desktop einmal; der kleine Server leitet die Pakete nur weiter.

## Moonlight-Client (Startwerte, dann messen)

- 1920×1080, 60 FPS.
- H.264 für den ersten Test, danach ggf. HEVC prüfen, wenn beide Seiten hardwarebeschleunigt arbeiten.
- Beginne mit 15 Mbit/s; bei gutem Ergebnis testweise auf 20 Mbit/s steigern oder senken, falls die Verbindung schwankt. Diese Werte sind Startwerte, **keine garantierte Optimalkonfiguration**.
- Hardware-Videodekodierung am Moonlight-Endgerät aktivieren.
- Bildschirm/TV auf 60 Hz (oder eine kompatible Bildwiederholrate) stellen.
- Controller wenn möglich direkt an das Moonlight-Endgerät koppeln. Der Eingabepfad muss vom Client über Sunshine bis zu GeForce NOW/Xbox Cloud Gaming reichen. Manche Webdienste unterstützen die Weitergabe von Gamepads in verschachtelten Remote-Sessions nur eingeschränkt.
- Moonlight-Statistikeinblendung einschalten; insbesondere Client-FPS, Host-/Stream-FPS, Network frame drops, jitter-related drops, decode/queue/render latency und Audio prüfen.

## Server während einer Spielsession messen

Auf dem kleinen Gateway im Projektordner:

```bash
python3 stream_health.py --interface wg0 --seconds 60 --ping-ip 10.77.0.2
```

`wg0` und `10.77.0.2` sind **Beispielwerte**; den realen WireGuard-Namen und die Remote-WireGuard-IP verwenden. Optional ohne ICMP mit `python3 stream_health.py --interface wg0 --seconds 60`.

Der Test liest /proc/stat und /proc/net/dev und sendet optional einmal pro Sekunde genau einen ICMP-Ping zum angegebenen Gegenüber; er ist **read-only**, verändert keine Firewall, erzeugt keinen Videostream und benötigt keine Root-Rechte. Er erfasst Gateway-CPU, Bytezähler, Netzwerkschnittstellenfehler sowie Ping-Median, p95 und Maximum. **Er misst nicht die clientseitigen FPS, Controller-Verzögerung oder Audio-/Videosynchronität.**

### Prüfkriterien für den anschließenden echten Live-Test

| Signal | Erwartung / Interpretation |
|---|---|
| Bildrate des Cloud-Gaming-Originalstreams | Möglichst stabile 60 FPS. Falls Original nur 30 liefert, kann Sunshine keine echten 60 neuen Quellbilder liefern. |
| Moonlight-Statistik | Nahe 60 tatsächlich dargestellte FPS, ohne längere Aussetzer. |
| Frame-Drops durch Netzwerk und Jitter | Möglichst nahe 0 %, für den Test idealerweise deutlich unter 1 %. |
| Dekodier-, Framequeue- und Renderzeiten | Zusammen und einzeln beurteilen; eine Queue über 16,7 ms bei 60 FPS kann auf Frame-Pacing-/Darstellungsprobleme hindeuten. |
| Gateway CPU-Auslastung | Deutlich unter anhaltender 100%-Auslastung; Beispiel-Ziel weniger als 60 % im 60-Sekunden-Test. **Kein zugesicherter Wert**. |
| Gateway RX/TX-Fehler, Drops | Keine oder möglichst wenige neu hinzugekommene Fehler. |
| Audio & Input | 5 Minuten gleichzeitig Controllerbewegung, Bildwechsel und kontinuierlichen Ton beurteilen. Keine wahrnehmbaren Hänger, Drift oder Aussetzer. |

## Wenn die kleine CPU trotzdem hoch ausgelastet ist

- WireGuard braucht CPU für Verschlüsselung/Entschlüsselung; NAT/Forwarding ist günstig, aber nicht kostenlos.
- Prüfe erst die tatsächliche Geschwindigkeit der schwächsten Verbindung und MTU: Falsche WireGuard-MTU kann Fragmentierung verursachen. Keine pauschalen MTU-Werte erzwingen.
- Testweise direkte, geschützte Verbindung Moonlight → Remote-Sunshine statt Umweg über den kleinen Server. Damit wird die 1-vCPU-Instanz aus dem Videopfad entfernt. Die bisherige Serveradresse bleibt in diesem Fall nicht mehr der eigentliche Streaming-Datenpfad.
- iPerf3 UDP-Tests nur auf der eigenen, autorisierten Strecke; keine ungeschützten öffentlich erreichbaren Testserver.
- WireGuard/NAT-Routing darf keine Schleife und keine doppelte Weiterleitung verursachen.
- Kein automatisches Abrufen von GitHub Actions-CPUs oder GitHub-Runnern für reale Gaming-Sitzungen.

## Quellen

- Offizielle Moonlight FAQ: https://github.com/moonlight-stream/moonlight-docs/wiki/Frequently-Asked-Questions
- Sunshine Troubleshooting: https://github.com/LizardByte/Sunshine/blob/master/docs/troubleshooting.md
- Sunshine Configuration: https://github.com/LizardByte/Sunshine/blob/master/docs/configuration.md

## Grenzen

Die GitHub CI prüft Konfigurationsgenerierung, Befehls-Sicherheit und den Python-Diagnosecode; die endgültige Eignung für **60 FPS mit synchronem Audio und Controller** kann nur ein live laufender Sunshine-/Moonlight-Test zeigen. Eine Cloud-Gaming-Verbindung, die über einen weiteren Cloud-Gaming-Stream läuft, fügt zwangsläufig einen zweiten Encode-/Decode- und Eingabeweg hinzu.
