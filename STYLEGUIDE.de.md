# Vision 8 – Style Guide

🇬🇧 [English](STYLEGUIDE.md) · 🇩🇪 Deutsch

Ruhig, warm, hochwertig. Die App fühlt sich an wie ein persönlicher Coach in einem stillen Raum am frühen Morgen: dunkler Grund, warmes Licht, wenig gleichzeitig, jede Bewegung mit Absicht.

## Farbe (`Ink`)
| Token | Verwendung |
|---|---|
| `night` | Hintergrund aller Seiten |
| `surface` | Karten, Listen, Eingabefelder |
| `line` | Haarlinien, Kartenränder |
| `paper` | Text |
| `muted` | Nebentext, Hinweise, inaktive Symbole |
| `dawn` | Akzent: ein Hauptknopf pro Ansicht, Eyebrows, Fortschritt |
| `good` | erledigt, erreicht |
| `drift` | Fehler, Löschen, Auflegen, das wichtigste To-do des Tages |

Pro Ansicht höchstens ein gefüllter `dawn`-Knopf. Farbe trägt Bedeutung, nie Dekoration.

## Schrift
| Rolle | Token | Einsatz |
|---|---|---|
| Seitentitel | `.pageTitle` (Serif 34) | „Hallo Mia“, „Vision“, „Profil“ |
| Abschnitt | `.sectionTitle` (Serif 22) | „Deine Bereiche“, „Dein Weg dorthin“ |
| Kartentitel | `.cardTitle` (Rounded Headline) | Titel innerhalb einer Karte |
| Text | `.bodyText` | Listeneinträge, Fließtext |
| Nebentext | `.callout` / `.note` | Begründungen, Hinweise |
| Eyebrow | `Eyebrow` (Caption, Versalien, Sperrung) | Kontext über Titeln |
| Zitat | `.quote` (Serif kursiv) | Warum, Coach-Sätze |

Serif = Stimme (Titel, Vision, Coach). Rounded = Bedienung.

## Abstände (`Space`)
- Seitenrand links/rechts: `page` (20) – überall gleich.
- Zwischen Abschnitten: `section` (28). Innerhalb eines Abschnitts: `s` (12). Titel zu Inhalt: `xs` (8).
- Karten-Innenabstand: `page` (20). Listenzeilen: 14 horizontal, 12 vertikal, mindestens 44 pt hoch.
- Seiten nutzen `Page { … }` für den gemeinsamen Rhythmus.

## Formen (`Radius`)
Karte 22, Bedienelement 16, Listenzeile 14, Chips als Kapsel. Immer `.continuous`.

## Bewegung (`Motion`)
- `snappy` – Tippen, Abhaken, Umschalten.
- `smooth` – Inhalte, die sich ändern (Listen, Texte).
- `gentle` – Erscheinen von Seiten und Karten; `.appear(index)` lässt Abschnitte nacheinander einblenden.
- Nur auf Handlung animieren, nie zum Angeben. „Bewegung reduzieren“ wird respektiert.
- Zahlen wechseln mit `.contentTransition(.numericText())`.

## Haptik
Leichter Impuls beim Drücken eines Hauptknopfs, Erfolg beim Erledigen und Speichern, Warnung beim Löschen. Nie bei bloßem Scrollen.

## Laden
`Skeleton` statt Spinner, wenn Inhalt erwartet wird. `CoachThinking`, wenn der Coach etwas formuliert.

## Texte
Deutsch, du-Form, kurz. Knöpfe mit Verb vorn („Gespräch starten“). Keine Ausrufezeichen in Bedienelementen.
