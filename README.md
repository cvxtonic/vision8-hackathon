# Vision 8

🇬🇧 English · 🇩🇪 [Deutsch](README.de.md)

**Vision 8 = Vision Aid.** A personal AI coach named **Clara**, built as an iOS app. Clara helps people develop a vision of their own, turn it into goals that meet the SMART definition, and work toward those goals every day.

## The problem

Many people have moments of strong motivation, but follow-through fails. Goals stay vague, have no emotional anchor and get lost in daily life. Nobody listens, nobody asks and nobody keeps at it with them.

## The solution

Vision 8 is a coach you talk to like a person. It connects the long-term vision to today's task.

1. **Intake talk (about 10 minutes, real-time voice).** The coach asks about the current situation, values, the picture in three years and the emotional "why". It listens actively ("Did I understand you correctly …?") and offers two or three possible answers to each question, so nobody faces a blank question.
2. **Goal contract.** The talk produces a vision, a why, values and SMART goals for 10 years, 3 years, 12 months and this month. Anything that does not fit is clarified in a live talk with the coach while the contract stays on screen. After signing, the goals are fixed for 30 days. A change needs a reason and 48 hours to think it over.
3. **Today.** The day score at the top, below it the five life areas (career, health, finances, relationships, personal growth) with their daily to-dos. Every morning Clara rates all to-dos against the vision and the monthly goal. The most important one is marked in red. Every to-do gets points, and the most important one gets the most. The day score is the share of points reached. With one tap, Clara files a to-do the person writes into the right area. A streak (as in Duolingo) counts days with progress.
4. **Coach any time.** A tap on the orb starts a live talk with Clara. The talk continues in the background while the person keeps using the app. The coach knows the day's list, asks about open items and helps remove obstacles. In follow-up talks it brings values and limiting beliefs to light, asks where they come from and helps reframe them. It keeps a clear boundary to therapy and refers to crisis lines when needed.
5. **Vision board.** The vision, nicely presented, with an AI-generated image, the reframed beliefs and the path from ten years down to this month.
6. **File.** The coach keeps a file on the person and updates it after every contact, so it never starts from zero. The person can read the file at any time and delete it with one tap.
7. **Evening call (optional).** At a chosen time and on chosen weekdays the coach calls, goes through the list and agrees on one concrete thing for tomorrow.

## Architecture

```
iOS app (SwiftUI)  ──HTTPS──▶  Worker (Cloudflare Workers, Hono, Zod, D1)  ──▶  Language model (EU, OpenAI-compatible gateway)
      │                                  │                                     └▶  Image model (anonymised scene description only)
      └──WebSocket (audio, μ-law 8 kHz)──┴──▶  Real-time voice service  ──▶  Real-time voice model (EU)
```

| Folder | Contents |
|---|---|
| `ios/` | SwiftUI app (iOS 17+), project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen). Real-time audio with `AVAudioEngine` and echo cancellation, HealthKit (steps, weight), calendar entries through EventKit. |
| `worker/` | Backend as a Cloudflare Worker: intake, goal contract, day ranking with score points, score and streak, file, vision board, evening call (cron). Database: Cloudflare D1 (EU jurisdiction). |
| `voice/agents/` | The four voice coaches as data: intake, contract revision, follow-up and evening call (prompt, model, voice, tools). They run in a separate real-time voice service that is not part of this repository. The prompts are in German, because the app speaks German. |
| `README.md` / `README.de.md`, `STYLEGUIDE.md` / `STYLEGUIDE.de.md` | Documentation in English and German. |
| `pitch/` | Pitch deck and demo script, in English and German. |

### Interface to the real-time voice service

- `POST /app/session/<agent>` with `{ "context": { … } }` (bearer key) → `{ "callSid", "token", "url" }`
- WebSocket on `url`: first message `{"event":"start","start":{"callSid","customParameters":{"token"}}}`, then audio as `{"event":"media","media":{"payload":"<base64 μ-law>"}}` in 20 ms frames. The service sends audio, `clear` (interruption) and `{"event":"transcript","speaker","text"}`.
- `POST /outbound/<agent>` starts a phone call. The service reports the result to the worker at `POST /internal/call-result`.

## Privacy and safety

- Clara introduces herself as an AI coach (label in the app, at the start of every call) and never claims to be human.
- Personal content (talks, goals, file) is processed only by models that process data in the EU.
- For the vision board image, the EU model first writes a scene description without names, places, companies, health details or recognisable people. Only this description goes to the image model.
- No audio recordings. Transcripts in the voice service are deleted after 30 days. "Delete all my data" removes the account, file, lists and images.
- Cost protection: daily limits per device, per network address and in total for model calls, voice talks, calls and images.

## Set it up yourself

**Worker**

```bash
cd worker
npm ci
npx wrangler d1 create vision8 --jurisdiction eu     # put the database_id into wrangler.jsonc
npx wrangler d1 migrations apply vision8 --remote
npx wrangler secret put LITELLM_KEY     # key for an OpenAI-compatible model gateway
npx wrangler secret put APP_KEY         # shared key of the app
npx wrangler secret put VOICE_KIT_KEY   # key of the real-time voice service
npx wrangler secret put VOICE_WEBHOOK_KEY
npx wrangler secret put CALL_ALLOWLIST  # numbers the coach may call
npx wrangler secret put FAL_KEY         # image model for the vision board
npm run typecheck && npm test
npm run deploy
```

The other values (`LLM_BASE`, `LLM_ALIAS`, `VOICE_KIT_URL`, limits) are placeholders in `worker/wrangler.jsonc`.

**iOS app**

```bash
cd ios
cp Vision8/Secrets.example.swift.txt Vision8/Secrets.swift   # enter the API address and APP_KEY
xcodegen generate
open Vision8.xcodeproj
```

Enter your own Apple team (`DEVELOPMENT_TEAM`) in `project.yml`. UI flows for [Maestro](https://maestro.mobile.dev) are in `ios/.maestro/`.

## Origin

Built at the hackathon in Magdeburg, November 2026.
