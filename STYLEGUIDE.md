# Vision 8 – Style Guide

🇬🇧 English · 🇩🇪 [Deutsch](STYLEGUIDE.de.md)

Calm, warm, high quality. The app feels like a personal coach in a quiet room early in the morning: a dark background, warm light, little at a time, every movement on purpose.

## Colour (`Ink`)
| Token | Use |
|---|---|
| `night` | Background of all pages |
| `surface` | Cards, lists, input fields |
| `line` | Hairlines, card borders |
| `paper` | Text |
| `muted` | Secondary text, hints, inactive symbols |
| `dawn` | Accent: one main button per view, eyebrows, progress |
| `good` | Done, reached |
| `drift` | Errors, delete, hang up, the most important to-do of the day |

At most one filled `dawn` button per view. Colour carries meaning, never decoration.

## Type
| Role | Token | Use |
|---|---|---|
| Page title | `.pageTitle` (serif 34) | "Hallo Mia", "Vision", "Profil" |
| Section | `.sectionTitle` (serif 22) | "Deine Bereiche", "Dein Weg dorthin" |
| Card title | `.cardTitle` (rounded headline) | Title inside a card |
| Text | `.bodyText` | List entries, running text |
| Secondary text | `.callout` / `.note` | Reasons, hints |
| Eyebrow | `Eyebrow` (caption, capitals, letter spacing) | Context above titles |
| Quote | `.quote` (serif italic) | The why, coach sentences |

Serif = voice (titles, vision, coach). Rounded = controls.

## Spacing (`Space`)
- Page margin left and right: `page` (20), the same everywhere.
- Between sections: `section` (28). Inside a section: `s` (12). Title to content: `xs` (8).
- Card padding: `page` (20). List rows: 14 horizontal, 12 vertical, at least 44 pt high.
- Pages use `Page { … }` for the shared rhythm.

## Shapes (`Radius`)
Card 22, control 16, list row 14, chips as capsules. Always `.continuous`.

## Motion (`Motion`)
- `snappy` – tap, tick off, toggle.
- `smooth` – content that changes (lists, texts).
- `gentle` – pages and cards appearing; `.appear(index)` fades sections in one after another.
- Animate only in response to an action, never to show off. "Reduce Motion" is respected.
- Numbers change with `.contentTransition(.numericText())`.

## Haptics
A light impulse when a main button is pressed, success when something is done or saved, a warning on delete. Never on plain scrolling.

## Loading
`Skeleton` instead of a spinner when content is expected. `CoachThinking` while the coach is writing something.

## Copy
The app speaks German, informal "du", short. Buttons start with a verb ("Gespräch starten"). No exclamation marks in controls.
