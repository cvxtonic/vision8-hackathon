# CLAUDE.md – Vision 8

iOS-App (SwiftUI, `ios/`) + Backend (Cloudflare Worker, `worker/`). Details: `README.de.md`, Stil: `STYLEGUIDE.de.md`.

## App bauen (Mac)
- `cd ios && xcodegen generate`, dann `Vision8.xcodeproj` in Xcode öffnen, Simulator wählen, Cmd+R.
- `ios/Vision8/Secrets.swift` ist nicht im Repo (Vorlage: `Secrets.example.swift.txt`). Nie committen.
- Nach Änderungen an `project.yml` oder neuen Dateien immer `xcodegen generate` neu laufen lassen.

## TestFlight-Update
1. `CURRENT_PROJECT_VERSION` in `ios/project.yml` um 1 erhöhen, committen.
2. `xcodegen generate`, in Xcode Ziel „Any iOS Device (arm64)“, Product → Archive.
3. Organizer → Distribute App → TestFlight & App Store → Upload (automatische Signierung, Team KC29A3B79D).
4. Nach ca. 10–20 Min. ist der Build in TestFlight; die Gruppe „Intern“ bekommt ihn automatisch.

## Regeln
- Backend (`worker/`) deployt Jay. Änderungen dort committen und Jay Bescheid geben.
- Keine Secrets, `.dev.vars`, Keys oder Zugangsdaten ins Repo.
- Nutzertexte auf Deutsch, Code und Kommentare auf Englisch.
