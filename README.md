# Vision 8

**Vision 8 = Vision Aid.** Ein persönlicher KI-Coach als iOS-App, der Menschen hilft, eine eigene Vision zu entwickeln, daraus Ziele nach der SMART-Definition abzuleiten und sie Tag für Tag umzusetzen.

## Das Problem

Viele Menschen haben Momente großer Motivation, aber die Umsetzung scheitert: Ziele bleiben vage, sind nicht emotional verankert und gehen im Alltag unter. Es fehlt jemand, der zuhört, nachfragt und dranbleibt.

## Die Lösung

Vision 8 ist ein Coach, mit dem man spricht wie mit einem Menschen, und der die Brücke von der langfristigen Vision bis zur heutigen Aufgabe schlägt.

1. **Kennenlerngespräch (ca. 10 Minuten, per Sprache in Echtzeit).** Der Coach fragt strukturiert nach Ausgangslage, Werten, dem Bild in drei Jahren und dem emotionalen „Warum“. Er hört aktiv zu („Habe ich dich richtig verstanden …?“) und bietet bei jeder Frage zwei, drei Antworten an, damit niemand vor einer leeren Frage steht.
2. **Zielvertrag.** Aus dem Gespräch entstehen Vision, Warum, Werte und SMART-Ziele für 10 Jahre, 3 Jahre, 12 Monate und diesen Monat. Was nicht passt, klärt man im Live-Gespräch mit dem Coach, während der Vertrag sichtbar bleibt. Mit der Unterschrift sind die Ziele 30 Tage fest; Änderungen brauchen eine Begründung und 48 Stunden Bedenkzeit.
3. **Heute.** Eine einzige Liste für den Tag, die der Coach aus der Vision, den Zielen und den bisherigen Gesprächen zusammenstellt, sortiert nach wichtig und dringend: *Zuerst*, *Dein Schritt nach vorn*, *Wenn Zeit bleibt*. Eigene Einträge sortiert der Coach ein. Ein Tagesscore und ein Streak (wie bei Duolingo) machen Fortschritt sichtbar.
4. **Coach jederzeit.** Ein Tipp auf die Kugel startet ein Live-Gespräch, das im Hintergrund weiterläuft, während man die App weiter nutzt. Der Coach kennt die Liste des Tages, fragt nach offenen Punkten und hilft, Hindernisse zu beseitigen. In Folgegesprächen macht er Werte und hinderliche Glaubenssätze sichtbar, fragt nach ihrer Herkunft und hilft, sie neu zu fassen – mit klarer Grenze zur Therapie und Verweis auf die Telefonseelsorge in Krisen.
5. **Vision Board.** Die Vision schön aufbereitet, mit einem KI-generierten Bild, den neu gefassten Glaubenssätzen und dem Weg von zehn Jahren bis zu diesem Monat.
6. **Akte.** Der Coach führt eine Akte über die Person und schreibt sie nach jedem Kontakt fort, damit er nie bei null anfängt. Die Person kann sie jederzeit einsehen und mit einem Tipp löschen.
7. **Abend-Anruf (optional).** Zu gewählter Uhrzeit und an gewählten Wochentagen ruft der Coach an, geht die Liste durch und vereinbart eine konkrete Sache für morgen.

## Architektur

```
iOS-App (SwiftUI)  ──HTTPS──▶  Worker (Cloudflare Workers, Hono, Zod, D1)  ──▶  Sprachmodell (EU, OpenAI-kompatibles Gateway)
      │                                  │                                     └▶  Bildmodell (nur anonymisierte Szenenbeschreibung)
      └──WebSocket (Audio, μ-law 8 kHz)──┴──▶  Echtzeit-Sprachdienst  ──▶  Echtzeit-Sprachmodell (EU)
```

| Ordner | Inhalt |
|---|---|
| `ios/` | SwiftUI-App (iOS 17+), Projekt per [XcodeGen](https://github.com/yonaskolb/XcodeGen). Echtzeit-Audio mit `AVAudioEngine` und Echounterdrückung, HealthKit (Schritte, Gewicht), Kalender-Eintrag über EventKit. |
| `worker/` | Backend als Cloudflare Worker: Erstgespräch, Zielvertrag, Tagesliste, Score und Streak, Akte, Vision Board, Abend-Anruf (Cron). Datenbank: Cloudflare D1 (EU-Jurisdiktion). |
| `voice/agents/` | Die vier Sprach-Coaches als Daten: Kennenlerngespräch, Vertragsanpassung, Folgegespräch und Abend-Anruf (Prompt, Modell, Stimme, Werkzeuge). Sie laufen in einem separaten Echtzeit-Sprachdienst, der nicht Teil dieses Repos ist. |

### Schnittstelle zum Echtzeit-Sprachdienst

- `POST /app/session/<agent>` mit `{ "context": { … } }` (Bearer-Schlüssel) → `{ "callSid", "token", "url" }`
- WebSocket auf `url`: erste Nachricht `{"event":"start","start":{"callSid","customParameters":{"token"}}}`, danach Audio als `{"event":"media","media":{"payload":"<base64 μ-law>"}}` in 20-ms-Rahmen. Der Dienst sendet Audio, `clear` (Unterbrechung) und `{"event":"transcript","speaker","text"}`.
- `POST /outbound/<agent>` startet einen Telefonanruf; das Ergebnis meldet der Dienst an `POST /internal/call-result` des Workers.

## Datenschutz

- Personenbezogene Inhalte (Gespräche, Ziele, Akte) werden nur von Modellen mit Verarbeitung in der EU verarbeitet.
- Für das Vision-Board-Bild erzeugt das EU-Modell zuerst eine Szenenbeschreibung ohne Namen, Orte, Firmen, Gesundheitsdetails und erkennbare Personen; nur diese geht an das Bildmodell.
- Keine Tonaufnahmen. Transkripte des Sprachdienstes werden nach 30 Tagen gelöscht. „Alle meine Daten löschen“ entfernt Konto, Akte, Listen und Bilder.
- Kostenschutz: tägliche Obergrenzen pro Gerät, pro Anschluss und gesamt für Modellaufrufe, Sprachgespräche, Anrufe und Bilder.

## Selbst aufsetzen

**Worker**

```bash
cd worker
npm ci
npx wrangler d1 create vision8 --jurisdiction eu     # database_id in wrangler.jsonc eintragen
npx wrangler d1 migrations apply vision8 --remote
npx wrangler secret put LITELLM_KEY     # Schlüssel für ein OpenAI-kompatibles Modell-Gateway
npx wrangler secret put APP_KEY         # gemeinsamer Schlüssel der App
npx wrangler secret put VOICE_KIT_KEY   # Schlüssel des Echtzeit-Sprachdienstes
npx wrangler secret put VOICE_WEBHOOK_KEY
npx wrangler secret put CALL_ALLOWLIST  # Nummern, die angerufen werden dürfen
npx wrangler secret put FAL_KEY         # Bildmodell für das Vision Board
npm run typecheck && npm test
npm run deploy
```

Die übrigen Werte (`LLM_BASE`, `LLM_ALIAS`, `VOICE_KIT_URL`, Obergrenzen) stehen als Platzhalter in `worker/wrangler.jsonc`.

**iOS-App**

```bash
cd ios
cp Vision8/Secrets.example.swift.txt Vision8/Secrets.swift   # API-Adresse und APP_KEY eintragen
xcodegen generate
open Vision8.xcodeproj
```

In `project.yml` das eigene Apple-Team (`DEVELOPMENT_TEAM`) eintragen. UI-Abläufe für [Maestro](https://maestro.mobile.dev) liegen in `ios/.maestro/`.

## Entstanden

Beim Hackathon in Magdeburg, November 2026.
