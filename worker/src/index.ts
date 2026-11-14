import { Hono } from "hono";
import type { Context } from "hono";
import { z } from "zod";

import {
  AREA_LABEL,
  AREAS,
  DebriefSchema,
  DraftSchema,
  FileSchema,
  MAX_TURNS,
  MIN_TURNS,
  PlanCheckSchema,
  QuestionSchema,
  ReplySchema,
  TurnSchema,
  ask,
  callContext,
  contractForTalk,
  changePrompt,
  contract,
  debriefPrompt,
  draftPrompt,
  filePrompt,
  interviewPrompt,
  planPrompt,
  reflectPrompt,
  ReflectSchema,
  DayListSchema,
  dayListPrompt,
  SortSchema,
  sortPrompt,
  SceneSchema,
  scenePrompt,
  KpiSetSchema,
  kpiPrompt,
  WeekSchema,
  weekPrompt,
  transcript,
} from "./coach.ts";
import type { Draft, Env, Goal, PlanCheck } from "./coach.ts";
import { FOCUS_LABEL, MAX_SPOKEN_TURNS, GOOD_DAY, berlinDay, dayScore, kpiMet, listScore, mondayOf, weekSummary, berlinHour, callDue, callableNumber, canConfirm, changeBlocked, coolingOffEnd, lockedUntil, normaliseFile, streak } from "./rules.ts";
import type { CallCandidate, Kpi, ListItem } from "./rules.ts";
import type { ChangeRow } from "./rules.ts";

type Vars = { device: string };
type DayPlan = { tasks: { text: string; done: boolean }[]; check: PlanCheck };
type Profile = Pick<Draft, "vision" | "why" | "values">;
type Talk = { summary: string; insight: string; at: string };

const app = new Hono<{ Bindings: Env; Variables: Vars }>();

class HttpError extends Error {
  constructor(
    readonly status: 400 | 404 | 409 | 429 | 502,
    message: string,
  ) {
    super(message);
  }
}

app.onError((err, c) => {
  if (err instanceof HttpError) return c.json({ error: err.message }, err.status);
  if (err instanceof z.ZodError) return c.json({ error: "Ungültige Eingabe." }, 400);
  console.error(err);
  return c.json({ error: "Der Coach ist gerade nicht erreichbar. Versuch es gleich noch einmal." }, 502);
});

app.get("/", (c) => c.text("vision8"));

/** Vision board images, public under an unguessable id (the app loads them like any picture). */
app.get("/img/:id", async (c) => {
  const id = c.req.param("id");
  if (!/^[0-9a-f-]{36}$/.test(id)) return c.text("not found", 404);
  const row = await c.env.DB.prepare("SELECT mime, bytes FROM boards WHERE id = ?").bind(id).first<{ mime: string; bytes: ArrayBuffer }>();
  if (!row) return c.text("not found", 404);
  return new Response(new Uint8Array(row.bytes), { headers: { "content-type": row.mime, "cache-control": "public, max-age=31536000, immutable" } });
});

async function sha256(s: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
}

/** Constant-time bearer check; an unset secret rejects everything. */
async function bearerOk(header: string | undefined, secret: string | undefined): Promise<boolean> {
  if (!secret) return false;
  const [a, b] = await Promise.all([sha256(header ?? ""), sha256(`Bearer ${secret}`)]);
  return crypto.subtle.timingSafeEqual(a, b);
}

/** voice-kit reports the outcome of the evening call; it becomes today's reflection. */
app.post("/internal/call-result", async (c) => {
  if (!(await bearerOk(c.req.header("authorization"), c.env.VOICE_WEBHOOK_KEY))) return c.json({ error: "unauthorized" }, 401);
  const body = z
    .object({ phone: z.string().regex(/^\+[1-9]\d{7,14}$/), summary: z.string().max(1200), reply: z.string().max(900), cause: z.string().max(500).optional(), fix: z.string().max(500).optional() })
    .parse(await c.req.json());
  const user = await c.env.DB.prepare(
    "SELECT u.device_id FROM users u LEFT JOIN days d ON d.device_id = u.device_id AND d.day = ? WHERE u.phone = ? ORDER BY d.called_at DESC LIMIT 1",
  )
    .bind(berlinDay(new Date()), body.phone)
    .first<{ device_id: string }>();
  if (!user) return c.json({ error: "unknown phone" }, 404);
  // A reflection the user typed is never replaced by the call summary.
  const existing = await c.env.DB.prepare("SELECT reflection_json FROM days WHERE device_id = ? AND day = ?").bind(user.device_id, berlinDay(new Date())).first<{ reflection_json: string | null }>();
  const typed = existing?.reflection_json ? (JSON.parse(existing.reflection_json) as { via?: string }).via !== "call" : false;
  if (!typed) {
    await saveDay(c.env, user.device_id, "reflection_json", { text: body.summary, reply: body.reply, via: "call", ...(body.cause && { cause: body.cause }), ...(body.fix && { fix: body.fix }) });
  }
  const material = `Zusammenfassung des Anrufs: ${body.summary}${body.cause ? `\nUrsache laut Coach (Einschätzung): ${body.cause}` : ""}${body.fix ? `\nVereinbarung für morgen: ${body.fix}` : ""}`;
  c.executionCtx.waitUntil(updateFile(c.env, user.device_id, "Abend-Anruf", material));
  return c.json({ ok: true });
});

app.use("/v1/*", async (c, next) => {
  const device = c.req.header("x-device-id") ?? "";
  if (c.req.header("x-v8-key") !== c.env.APP_KEY || !/^[0-9A-Fa-f-]{36}$/.test(device)) return c.json({ error: "unauthorized" }, 401);
  c.set("device", device.toLowerCase());
  await c.env.DB.prepare("INSERT OR IGNORE INTO users (device_id, created_at) VALUES (?, ?)").bind(device.toLowerCase(), new Date().toISOString()).run();
  await next();
});

/** Per-device daily cap on model calls; the gateway key budget is the hard limit behind it. */
async function meter(c: Context<{ Bindings: Env; Variables: Vars }>): Promise<void> {
  const env = c.env;
  const day = berlinDay(new Date());
  const count = (key: string) =>
    env.DB.prepare("INSERT INTO usage (device_id, day, n) VALUES (?, ?, 1) ON CONFLICT (device_id, day) DO UPDATE SET n = n + 1 RETURNING n")
      .bind(key, day)
      .first<{ n: number }>();
  if (((await count(c.var.device))?.n ?? 0) > Number(env.MAX_LLM_CALLS_PER_DAY)) throw new HttpError(429, "Für heute ist das Coach-Kontingent aufgebraucht.");
  // The device id is chosen by the client: one network address and the whole service are capped as well.
  if (((await count(`ip:${c.req.header("cf-connecting-ip") ?? "unknown"}`))?.n ?? 0) > Number(env.MAX_LLM_CALLS_PER_IP_PER_DAY)) {
    throw new HttpError(429, "Von diesem Anschluss kamen heute schon sehr viele Anfragen. Morgen geht es weiter.");
  }
  if (((await count("*"))?.n ?? 0) > Number(env.MAX_LLM_CALLS_GLOBAL_PER_DAY)) throw new HttpError(429, "Der Coach ist für heute ausgelastet. Morgen geht es weiter.");
}

async function nameOf(env: Env, device: string): Promise<string | null> {
  return (await env.DB.prepare("SELECT name FROM users WHERE device_id = ?").bind(device).first<{ name: string | null }>())?.name ?? null;
}

async function loadDraft(env: Env, device: string): Promise<{ draft: Draft; goals: (Goal & { id: string; lockedUntil: string })[]; name: string | null; file: string | null }> {
  const user = await env.DB.prepare("SELECT profile_json, name, file FROM users WHERE device_id = ? AND committed_at IS NOT NULL")
    .bind(device)
    .first<{ profile_json: string; name: string | null; file: string | null }>();
  if (!user) throw new HttpError(409, "Du hast noch keinen Zielvertrag.");
  const rows = await env.DB.prepare("SELECT id, json, locked_until FROM goals WHERE device_id = ?").bind(device).all<{ id: string; json: string; locked_until: string }>();
  const order = ["10y", "3y", "1y", "month"];
  const goals = rows.results
    .map((r) => ({ ...(JSON.parse(r.json) as Goal), id: r.id, lockedUntil: r.locked_until }))
    .sort((a, b) => order.indexOf(a.horizon) - order.indexOf(b.horizon));
  const profile = JSON.parse(user.profile_json) as Profile;
  return { draft: { ...profile, goals }, goals, name: user.name, file: user.file };
}

/** Rewrites the coach's file with new material. Runs in waitUntil and never throws: on failure it logs and gives up.
 *  The UPDATE only lands if nobody else wrote the file since it was read (file_updated_at) and the contract is the
 *  same one (committed_at, so a deleted and recreated account never gets the old file); otherwise one retry. */
async function updateFile(env: Env, device: string, source: string, material: string): Promise<void> {
  try {
    for (let attempt = 0; attempt < 2; attempt++) {
      const row = await env.DB.prepare("SELECT file, file_updated_at, committed_at FROM users WHERE device_id = ?")
        .bind(device)
        .first<{ file: string | null; file_updated_at: string | null; committed_at: string | null }>();
      if (!row?.committed_at) return;
      const { file } = await ask(env, FileSchema, filePrompt(row.file ?? "", source, material, berlinDay(new Date())));
      const text = normaliseFile(file);
      if (!text) {
        console.error("file update: no usable section", device, source);
        return;
      }
      const res = await env.DB.prepare("UPDATE users SET file = ?, file_updated_at = ? WHERE device_id = ? AND committed_at = ? AND file_updated_at IS ?")
        .bind(text, new Date().toISOString(), device, row.committed_at, row.file_updated_at)
        .run();
      if (res.meta.changes > 0) return;
    }
    console.error("file update: lost the race twice", device, source);
  } catch (err) {
    console.error("file update", device, source, err);
  }
}

app.post("/v1/name", async (c) => {
  // Letters, spaces, hyphens and apostrophes only: the name goes into prompts and is spoken aloud.
  const { name } = z.object({ name: z.string().trim().min(1).max(40).regex(/^[\p{L}][\p{L} '’-]*$/u) }).parse(await c.req.json());
  await c.env.DB.prepare("UPDATE users SET name = ? WHERE device_id = ?").bind(name, c.var.device).run();
  return c.json({ ok: true });
});

const InterviewBody = z.object({ area: z.enum(AREAS), turns: z.array(TurnSchema).max(MAX_TURNS), voice: z.boolean().default(false) });

app.post("/v1/interview/next", async (c) => {
  const { area, turns, voice } = InterviewBody.parse(await c.req.json());
  if (turns.length >= MAX_TURNS) return c.json(QuestionSchema.parse({ done: true, phase: "ziel" }));
  await meter(c);
  const name = await nameOf(c.env, c.var.device);
  let q = await ask(c.env, QuestionSchema, interviewPrompt(area, turns, voice, name));
  // Too early to finish: the draft would lack the SMART answers. Ask once more for a question.
  if (q.done && turns.length < MIN_TURNS) {
    q = await ask(c.env, QuestionSchema, `${interviewPrompt(area, turns, voice, name)}\n\nEs ist zu früh für "done": true. Stelle die nächste fehlende Frage.`);
  }
  // Spoken questions cannot show options: fold them into the question so the person hears them.
  if (voice && !q.done) {
    const spoken = q.options.length > 1 ? ` Zum Beispiel: ${q.options.slice(0, -1).join(", ")} oder ${q.options.at(-1)}.` : "";
    const scale = q.input === "scale" && !/zehn|10/.test(q.question) ? " Sag mir eine Zahl von eins bis zehn." : "";
    q = { ...q, question: `${q.question}${spoken}${scale}`, input: "text", options: [], hint: "" };
  }
  return c.json(q);
});

app.post("/v1/draft", async (c) => {
  // A spoken conversation has more, shorter turns than the typed interview.
  // `previous` + `feedback`: revise an existing draft (feedback is typed, or the transcript of the revise talk).
  const body = InterviewBody.extend({ turns: z.array(TurnSchema).max(MAX_SPOKEN_TURNS), feedback: z.string().max(8000).optional(), previous: DraftSchema.optional() }).parse(await c.req.json());
  await meter(c);
  return c.json(await ask(c.env, DraftSchema, draftPrompt(body.area, body.turns, berlinDay(new Date()), body.feedback, await nameOf(c.env, c.var.device), body.previous)));
});

const VoiceSessionReply = z.object({ callSid: z.string().min(1), token: z.string().min(1), url: z.string().url() });

const IntakeSessionBody = z.object({ area: z.enum(AREAS), turns: z.array(TurnSchema).max(MAX_SPOKEN_TURNS).default([]) });
const SessionKind = z.object({ kind: z.enum(["intake", "followup", "revise"]).default("intake"), focus: z.enum(["beliefs", "values", "open", "help", "todo"]).default("open"), topic: z.string().trim().max(200).default("") });

/** Newest agreement between coach and person: the fix of the latest reflection that has one. */
async function lastAgreement(env: Env, device: string): Promise<string> {
  const row = await env.DB.prepare("SELECT reflection_json FROM days WHERE device_id = ? AND COALESCE(json_extract(reflection_json, '$.fix'), '') <> '' ORDER BY day DESC LIMIT 1")
    .bind(device)
    .first<{ reflection_json: string }>();
  return row ? ((JSON.parse(row.reflection_json) as StoredReflection).fix ?? "") : "";
}

/** Opens a realtime conversation with voice-kit: the intake interview before the contract, a follow-up after it.
 *  The app then streams audio to the returned url itself. */
app.post("/v1/voice/session", async (c) => {
  const raw: unknown = await c.req.json();
  const { kind, focus, topic } = SessionKind.parse(raw);
  const device = c.var.device;
  const env = c.env;
  let agent: string;
  let context: Record<string, string>;
  if (kind === "intake") {
    const { area, turns } = IntakeSessionBody.parse(raw);
    const user = await env.DB.prepare("SELECT committed_at FROM users WHERE device_id = ?").bind(device).first<{ committed_at: string | null }>();
    if (user?.committed_at) throw new HttpError(409, "Dein Zielvertrag steht bereits.");
    const prior = turns.map((t) => `Frage: ${t.question}\nAntwort: ${t.answer}`).join("\n").slice(-3900);
    agent = env.VOICE_INTAKE_AGENT;
    context = { NAME: (await nameOf(env, device)) ?? "", AREA: AREA_LABEL[area] ?? area, PRIOR: prior };
  } else if (kind === "revise") {
    // Talking about the drafted contract before it is signed; the person sees the draft on screen.
    const { draft } = z.object({ draft: DraftSchema }).parse(raw);
    const user = await env.DB.prepare("SELECT committed_at FROM users WHERE device_id = ?").bind(device).first<{ committed_at: string | null }>();
    if (user?.committed_at) throw new HttpError(409, "Dein Zielvertrag steht bereits. Änderungen laufen über die Bedenkzeit.");
    agent = env.VOICE_REVISE_AGENT;
    context = { NAME: (await nameOf(env, device)) ?? "", CONTRACT: contractForTalk(draft) };
  } else {
    const { draft, name, file } = await loadDraft(env, device);
    const { NAME, AKTE, GOALS } = callContext(draft, null, name, file);
    agent = env.VOICE_FOLLOWUP_AGENT;
    context = { NAME, AKTE, GOALS, LAST: await lastAgreement(env, device), FOCUS: FOCUS_LABEL[focus], TOPIC: focus === "todo" ? topic : "", TODAY: await listForCoach(env, device) };
  }
  const today = berlinDay(new Date());
  // Slots are taken before calling voice-kit and never handed back: the device row first, then the global row ('*').
  // Intake and follow-up sessions share these counters.
  const take = (key: string, cap: string) =>
    env.DB.prepare("INSERT INTO voice_sessions (device_id, day, n) VALUES (?1, ?2, 1) ON CONFLICT (device_id, day) DO UPDATE SET n = n + 1 WHERE n < ?3 RETURNING n")
      .bind(key, today, Number(cap))
      .first<{ n: number }>();
  if (!(await take(device, env.MAX_VOICE_SESSIONS_PER_DAY))) throw new HttpError(429, "Für heute hast du genug Gespräche gestartet. Du kannst tippen oder morgen weitersprechen.");
  // The device id is chosen by the client, so one network address is capped as well.
  if (!(await take(`ip:${c.req.header("cf-connecting-ip") ?? "unknown"}`, env.MAX_VOICE_SESSIONS_PER_IP_PER_DAY))) {
    throw new HttpError(429, "Von diesem Anschluss wurden heute schon viele Gespräche gestartet. Du kannst tippen oder morgen weitersprechen.");
  }
  if (!(await take("*", env.MAX_VOICE_SESSIONS_GLOBAL_PER_DAY))) throw new HttpError(429, "Heute sind keine Gespräche mehr frei. Du kannst tippen oder morgen weitersprechen.");
  const res = await fetch(`${env.VOICE_KIT_URL}/app/session/${agent}`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.VOICE_KIT_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ context }),
    signal: AbortSignal.timeout(10_000),
  }).catch((err: unknown) => {
    console.error("voice-kit unreachable", err);
    return null;
  });
  const session = res?.ok ? VoiceSessionReply.safeParse(await res.json().catch(() => null)) : null;
  if (!session?.success) {
    if (res && !res.ok) console.error("voice-kit session", res.status, await res.text());
    throw new HttpError(
      502,
      kind === "intake"
        ? "Das Gespräch konnte gerade nicht gestartet werden. Versuch es gleich noch einmal oder tippe deine Antworten."
        : "Das Gespräch konnte gerade nicht gestartet werden. Versuch es gleich noch einmal.",
    );
  }
  const { url, token, callSid } = session.data;
  return c.json({ url, token, callSid });
});

/** After a follow-up conversation: what the coach takes away, shown in the app; the transcript goes into the file. */
app.post("/v1/voice/debrief", async (c) => {
  const { turns } = z.object({ turns: z.array(TurnSchema).min(1).max(MAX_SPOKEN_TURNS) }).parse(await c.req.json());
  const device = c.var.device;
  const { draft, name, file } = await loadDraft(c.env, device);
  // Metered before anything runs; the file update counts as part of this call. It is scheduled before the summary,
  // so the conversation is kept even when the summary fails.
  await meter(c);
  c.executionCtx.waitUntil(updateFile(c.env, device, "Folgegespräch", transcript(turns)));
  const { summary, insight } = await ask(c.env, DebriefSchema, debriefPrompt(draft, turns, name, file));
  const talk: Talk = { summary, insight, at: new Date().toISOString() };
  await c.env.DB.prepare("UPDATE users SET last_talk_json = ? WHERE device_id = ?").bind(JSON.stringify(talk), device).run();
  return c.json({ summary, insight });
});

app.post("/v1/commit", async (c) => {
  const { area, draft, turns } = z.object({ area: z.enum(AREAS), draft: DraftSchema, turns: z.array(TurnSchema).max(MAX_SPOKEN_TURNS).default([]) }).parse(await c.req.json());
  const device = c.var.device;
  const now = new Date();
  const profile: Profile = { vision: draft.vision, why: draft.why, values: draft.values };
  const claimed = await c.env.DB.prepare("UPDATE users SET area = ?, profile_json = ?, committed_at = ? WHERE device_id = ? AND committed_at IS NULL")
    .bind(area, JSON.stringify(profile), now.toISOString(), device)
    .run();
  if (claimed.meta.changes === 0) throw new HttpError(409, "Dein Zielvertrag steht bereits. Änderungen laufen über die Bedenkzeit.");
  await c.env.DB.batch(
    draft.goals.map((g) =>
      c.env.DB.prepare("INSERT INTO goals (id, device_id, horizon, json, locked_until) VALUES (?, ?, ?, ?, ?)").bind(
        crypto.randomUUID(),
        device,
        g.horizon,
        JSON.stringify(g),
        lockedUntil(now),
      ),
    ),
  );
  const material = `${turns.length ? `Gespräch:\n${transcript(turns)}\n\n` : ""}Zielvertrag, den die Person unterschrieben hat:\n${contract(draft)}`;
  c.executionCtx.waitUntil(updateFile(c.env, device, "Erstgespräch", material));
  c.executionCtx.waitUntil(setupKpis(c.env, device, material));
  return c.json({ ok: true });
});

app.get("/v1/state", async (c) => {
  const device = c.var.device;
  const user = await c.env.DB.prepare("SELECT area, profile_json, committed_at, phone, nudge_consent, call_hour, call_minute, call_days, file, file_updated_at, last_talk_json, board_id, board_caption FROM users WHERE device_id = ?")
    .bind(device)
    .first<{
      area: string | null;
      profile_json: string | null;
      committed_at: string | null;
      phone: string | null;
      nudge_consent: number;
      call_hour: number;
      call_minute: number;
      call_days: string;
      file: string | null;
      file_updated_at: string | null;
      last_talk_json: string | null;
      board_id: string | null;
      board_caption: string | null;
    }>();
  if (!user?.committed_at || !user.profile_json) return c.json({ committed: false });
  const today = berlinDay(new Date());
  const since = new Date(`${today}T12:00:00Z`);
  since.setUTCDate(since.getUTCDate() - 60);
  const [kpis, logs, week, reflected] = await Promise.all([
    loadKpis(c.env, device),
    kpiLogs(c.env, device, since.toISOString().slice(0, 10)),
    loadWeek(c.env, device, mondayOf(today)),
    c.env.DB.prepare("SELECT day, plan_json IS NOT NULL AS planned, reflection_json IS NOT NULL AS reflected, list_json FROM days WHERE device_id = ? AND day >= ?")
      .bind(device, since.toISOString().slice(0, 10))
      .all<{ day: string; planned: number; reflected: number; list_json: string | null }>(),
  ]);
  // Day scores for the last 60 days: the week view and the streak with its joker read them.
  const scores: Record<string, number> = {};
  const habits = new Map(reflected.results.map((r) => [r.day, r]));
  for (const day of new Set([...Object.keys(logs), ...habits.keys()])) {
    const h = habits.get(day);
    // Days with the one list score by it; older days by the to-do formula.
    scores[day] = h?.list_json ? listScore(JSON.parse(h.list_json) as ListItem[]) : dayScore(kpis, logs[day] ?? {}, h?.planned === 1, h?.reflected === 1);
  }
  const [{ goals }, day, planned, change, carry] = await Promise.all([
    loadDraft(c.env, device),
    c.env.DB.prepare("SELECT plan_json, reflection_json FROM days WHERE device_id = ? AND day = ?").bind(device, today).first<{ plan_json: string | null; reflection_json: string | null }>(),
    c.env.DB.prepare("SELECT day FROM days WHERE device_id = ? AND plan_json IS NOT NULL ORDER BY day DESC LIMIT 120").bind(device).all<{ day: string }>(),
    c.env.DB.prepare("SELECT id, goal_id, proposed, coach_reply, effective_at FROM change_requests WHERE device_id = ? AND status = 'pending'").bind(device).first(),
    c.env.DB.prepare("SELECT reflection_json FROM days WHERE device_id = ? AND day < ? AND COALESCE(json_extract(reflection_json, '$.fix'), '') <> '' ORDER BY day DESC LIMIT 1").bind(device, today).first<{ reflection_json: string }>(),
  ]);
  return c.json({
    committed: true,
    committedAt: user.committed_at,
    name: await nameOf(c.env, device),
    area: user.area,
    profile: JSON.parse(user.profile_json) as Profile,
    goals,
    list: await loadList(c.env, device, today),
    coachStreak: await coachStreak(c.env, device, today, berlinDay(new Date(user.committed_at))),
    today: { day: today, plan: day?.plan_json ? (JSON.parse(day.plan_json) as DayPlan) : null, reflection: day?.reflection_json ? (JSON.parse(day.reflection_json) as unknown) : null },
    streak: streak(planned.results.map((r) => r.day), today),
    // What the coach and the person agreed last time, shown while planning the next day.
    carry: carry?.reflection_json ? ((JSON.parse(carry.reflection_json) as StoredReflection).fix ?? null) : null,
    pendingChange: change ?? null,
    contact: { phone: user.phone, consent: user.nudge_consent === 1, callHour: user.call_hour, callMinute: user.call_minute, days: [...user.call_days].map(Number) },
    file: user.file,
    fileUpdatedAt: user.file_updated_at,
    lastTalk: user.last_talk_json ? (JSON.parse(user.last_talk_json) as Talk) : null,
    week,
    kpis,
    kpiToday: logs[today] ?? {},
    dayScore: scores[today] ?? 0,
    board: user.board_id ? { image: `${new URL(c.req.url).origin}/img/${user.board_id}`, caption: user.board_caption ?? "" } : null,
    weekScore: weekSummary(today, scores, berlinDay(new Date(user.committed_at))),
  });
});

async function saveDay(env: Env, device: string, column: "plan_json" | "reflection_json", value: unknown): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO days (device_id, day, ${column}, last_activity) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (device_id, day) DO UPDATE SET ${column} = ?3, last_activity = ?4`,
  )
    .bind(device, berlinDay(new Date()), JSON.stringify(value), new Date().toISOString())
    .run();
}

async function todayPlan(env: Env, device: string): Promise<DayPlan> {
  const row = await env.DB.prepare("SELECT plan_json FROM days WHERE device_id = ? AND day = ?").bind(device, berlinDay(new Date())).first<{ plan_json: string | null }>();
  if (!row?.plan_json) throw new HttpError(409, "Für heute gibt es noch keinen Plan.");
  return JSON.parse(row.plan_json) as DayPlan;
}

app.post("/v1/day/plan", async (c) => {
  const { tasks } = z.object({ tasks: z.array(z.string().trim().min(1).max(200)).min(1).max(12) }).parse(await c.req.json());
  const { draft, name, file } = await loadDraft(c.env, c.var.device);
  await meter(c);
  const kpiText = await kpiStatus(c.env, c.var.device);
  // The daily KPIs ride along with the file so the plan check can point at the ones still open.
  const withKpis = kpiText ? `${file ?? ""}\n\nTägliche To-dos, Stand jetzt:\n${kpiText}` : file;
  const check = await ask(c.env, PlanCheckSchema, planPrompt(draft, tasks, name, withKpis));
  if (check.items.length !== tasks.length) throw new Error("plan check length mismatch");
  const plan: DayPlan = { tasks: tasks.map((text) => ({ text, done: false })), check };
  await saveDay(c.env, c.var.device, "plan_json", plan);
  return c.json(plan);
});

async function loadKpis(env: Env, device: string): Promise<Kpi[]> {
  const row = await env.DB.prepare("SELECT kpis_json FROM users WHERE device_id = ?").bind(device).first<{ kpis_json: string | null }>();
  const kpis = row?.kpis_json ? (JSON.parse(row.kpis_json) as Kpi[]) : [];
  // Daily to-dos are ticked, never measured; only Health-backed ones keep a number.
  return kpis.map((k) => (k.source === "manual" && k.direction !== "check" ? { ...k, direction: "check", target: 1, unit: "" } : k));
}

async function kpiLogs(env: Env, device: string, from: string): Promise<Record<string, Record<string, number>>> {
  const rows = await env.DB.prepare("SELECT day, kpi_id, value FROM kpi_logs WHERE device_id = ? AND day >= ?").bind(device, from).all<{ day: string; kpi_id: string; value: number }>();
  const out: Record<string, Record<string, number>> = {};
  for (const r of rows.results) (out[r.day] ??= {})[r.kpi_id] = r.value;
  return out;
}

/** Today's KPIs as one line each, for the coach ("Schritte: 6200 von mindestens 8000 – noch nicht erreicht"). */
async function kpiStatus(env: Env, device: string): Promise<string> {
  const kpis = await loadKpis(env, device);
  if (!kpis.length) return "";
  const today = berlinDay(new Date());
  const logged = (await kpiLogs(env, device, today))[today] ?? {};
  const word = { atLeast: "mindestens", atMost: "höchstens", check: "" } as const;
  return kpis
    .map((k) => {
      const v = logged[k.id];
      const goal = k.direction === "check" ? "erledigen" : `${word[k.direction]} ${k.target} ${k.unit}`;
      if (v === undefined) return `${k.name}: heute noch nicht erfasst (Ziel: ${goal})`;
      const value = k.direction === "check" ? (v >= 1 ? "erledigt" : "nicht erledigt") : `${v} ${k.unit}`;
      return `${k.name}: ${value} (Ziel: ${goal}) – ${kpiMet(k, v) ? "erreicht" : "noch nicht erreicht"}`;
    })
    .join("\n");
}

/** Lets the coach set the daily KPIs from the contract (and the interview, when given). Never throws. */
async function setupKpis(env: Env, device: string, material: string): Promise<Kpi[]> {
  try {
    const { draft, name, file } = await loadDraft(env, device);
    const area = (await env.DB.prepare("SELECT area FROM users WHERE device_id = ?").bind(device).first<{ area: string | null }>())?.area ?? "karriere";
    const { kpis } = await ask(env, KpiSetSchema, kpiPrompt(draft, area, material.slice(0, 6000), name, file));
    const made: Kpi[] = kpis.map((k) => ({ ...k, id: crypto.randomUUID(), target: k.direction === "check" ? 1 : k.target }));
    await env.DB.prepare("UPDATE users SET kpis_json = ? WHERE device_id = ?").bind(JSON.stringify(made), device).run();
    return made;
  } catch (err) {
    console.error("kpi setup failed", device, err);
    return [];
  }
}

app.post("/v1/kpis/setup", async (c) => {
  const { fresh } = z.object({ fresh: z.boolean().default(false) }).parse(await c.req.json().catch(() => ({})));
  const existing = await loadKpis(c.env, c.var.device);
  if (existing.length && !fresh) return c.json({ kpis: existing });
  await loadDraft(c.env, c.var.device); // 409 without a contract
  await meter(c);
  const kpis = await setupKpis(c.env, c.var.device, "");
  if (!kpis.length) throw new Error("kpi setup failed");
  return c.json({ kpis });
});

const AreaKpi = z.object({
  area: z.enum(AREAS),
  name: z.string().trim().min(1).max(60),
});

async function saveKpis(env: Env, device: string, kpis: Kpi[]): Promise<void> {
  await env.DB.prepare("UPDATE users SET kpis_json = ? WHERE device_id = ?").bind(JSON.stringify(kpis.slice(0, 15)), device).run();
}

/** The person sets a KPI for a life area themselves. */
app.post("/v1/kpis/add", async (c) => {
  const k = AreaKpi.parse(await c.req.json());
  await loadDraft(c.env, c.var.device); // 409 without a contract
  const kpis = await loadKpis(c.env, c.var.device);
  kpis.push({ ...k, id: crypto.randomUUID(), source: "manual", direction: "check", target: 1, unit: "" });
  await saveKpis(c.env, c.var.device, kpis);
  return c.json({ kpis });
});

/** The coach suggests one or two KPIs for a life area that has none yet. */
app.post("/v1/kpis/suggest", async (c) => {
  const { area } = z.object({ area: z.enum(AREAS) }).parse(await c.req.json());
  const { draft, name, file } = await loadDraft(c.env, c.var.device);
  await meter(c);
  const userArea = (await c.env.DB.prepare("SELECT area FROM users WHERE device_id = ?").bind(c.var.device).first<{ area: string | null }>())?.area ?? area;
  const made = await ask(c.env, KpiSetSchema, kpiPrompt(draft, userArea, "", name, file, area));
  const kpis = await loadKpis(c.env, c.var.device);
  for (const k of made.kpis.slice(0, 2)) kpis.push({ ...k, area, id: crypto.randomUUID(), target: k.direction === "check" ? 1 : k.target });
  await saveKpis(c.env, c.var.device, kpis);
  return c.json({ kpis });
});

app.post("/v1/kpis/remove", async (c) => {
  const { id } = z.object({ id: z.string().uuid() }).parse(await c.req.json());
  const kpis = (await loadKpis(c.env, c.var.device)).filter((k) => k.id !== id);
  await saveKpis(c.env, c.var.device, kpis);
  return c.json({ kpis });
});

/** Creates (or with `fresh` recreates) the vision board image from the signed vision. */
app.post("/v1/vision/board", async (c) => {
  const { fresh } = z.object({ fresh: z.boolean().default(false) }).parse(await c.req.json().catch(() => ({})));
  const env = c.env;
  const device = c.var.device;
  const origin = new URL(c.req.url).origin;
  const current = await env.DB.prepare("SELECT board_id, board_caption FROM users WHERE device_id = ?").bind(device).first<{ board_id: string | null; board_caption: string | null }>();
  if (current?.board_id && !fresh) return c.json({ image: `${origin}/img/${current.board_id}`, caption: current.board_caption ?? "" });
  if (!env.FAL_KEY) throw new HttpError(409, "Das Vision Board ist gerade nicht verfügbar.");
  const { draft } = await loadDraft(env, device);
  // Images cost real money outside the model budget: capped per device and in total, per Berlin day.
  const today = berlinDay(new Date());
  const take = (key: string, cap: string) =>
    env.DB.prepare("INSERT INTO voice_sessions (device_id, day, n) VALUES (?1, ?2, 1) ON CONFLICT (device_id, day) DO UPDATE SET n = n + 1 WHERE n < ?3 RETURNING n")
      .bind(key, today, Number(cap))
      .first<{ n: number }>();
  if (!(await take(`img:${device}`, env.MAX_BOARDS_PER_DAY))) throw new HttpError(429, "Für heute hast du genug Bilder erzeugt. Morgen wieder.");
  // The device id is chosen by the client, so one network address is capped as well.
  if (!(await take(`img:ip:${c.req.header("cf-connecting-ip") ?? "unknown"}`, env.MAX_BOARDS_PER_IP_PER_DAY))) {
    throw new HttpError(429, "Von diesem Anschluss wurden heute schon viele Bilder erzeugt. Morgen wieder.");
  }
  if (!(await take("img:*", env.MAX_BOARDS_GLOBAL_PER_DAY))) throw new HttpError(429, "Heute sind keine Bilder mehr frei. Morgen wieder.");
  await meter(c);
  const scene = await ask(env, SceneSchema, scenePrompt(draft));
  const res = await fetch("https://fal.run/fal-ai/gpt-image-2", {
    method: "POST",
    headers: { authorization: `Key ${env.FAL_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ prompt: scene.prompt, image_size: { width: 1024, height: 1280 }, quality: "medium", num_images: 1, output_format: "jpeg" }),
    signal: AbortSignal.timeout(120_000),
  }).catch((err: unknown) => {
    console.error("fal unreachable", err);
    return null;
  });
  const out = res?.ok ? ((await res.json().catch(() => null)) as { images?: { url?: string }[] } | null) : null;
  const url = out?.images?.[0]?.url;
  if (!url) {
    if (res && !res.ok) console.error("fal", res.status, (await res.text()).slice(0, 300));
    throw new HttpError(502, "Das Bild konnte gerade nicht erzeugt werden. Versuch es gleich noch einmal.");
  }
  const image = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (!image.ok) throw new HttpError(502, "Das Bild konnte gerade nicht geladen werden. Versuch es gleich noch einmal.");
  const bytes = await image.arrayBuffer();
  const id = crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare("INSERT INTO boards (id, device_id, created_at, mime, bytes) VALUES (?, ?, ?, ?, ?)").bind(id, device, new Date().toISOString(), image.headers.get("content-type") ?? "image/jpeg", bytes),
    env.DB.prepare("DELETE FROM boards WHERE device_id = ? AND id != ?").bind(device, id),
    env.DB.prepare("UPDATE users SET board_id = ?, board_caption = ? WHERE device_id = ?").bind(id, scene.caption, device),
  ]);
  return c.json({ image: `${origin}/img/${id}`, caption: scene.caption });
});

/** Numbers for the overview tab: what happened since the person started. */
app.get("/v1/stats", async (c) => {
  const env = c.env;
  const device = c.var.device;
  const user = await env.DB.prepare("SELECT committed_at FROM users WHERE device_id = ?").bind(device).first<{ committed_at: string | null }>();
  if (!user?.committed_at) throw new HttpError(409, "Du hast noch keinen Zielvertrag.");
  const today = berlinDay(new Date());
  const start = berlinDay(new Date(user.committed_at));
  const from = new Date(`${today}T12:00:00Z`);
  from.setUTCDate(from.getUTCDate() - 29);
  const since30 = from.toISOString().slice(0, 10);
  const [kpis, logs, days, talks, requests, weeks] = await Promise.all([
    loadKpis(env, device),
    kpiLogs(env, device, start),
    env.DB.prepare("SELECT day, plan_json IS NOT NULL AS planned, reflection_json IS NOT NULL AS reflected FROM days WHERE device_id = ? AND day >= ?").bind(device, start).all<{ day: string; planned: number; reflected: number }>(),
    env.DB.prepare("SELECT COALESCE(SUM(n), 0) AS n FROM voice_sessions WHERE device_id = ?").bind(device).first<{ n: number }>(),
    env.DB.prepare("SELECT COALESCE(SUM(n), 0) AS n FROM usage WHERE device_id = ?").bind(device).first<{ n: number }>(),
    env.DB.prepare("SELECT json FROM weeks WHERE device_id = ?").bind(device).all<{ json: string }>(),
  ]);
  const habits = new Map(days.results.map((d) => [d.day, d]));
  const scores: Record<string, number> = {};
  for (const day of new Set([...Object.keys(logs), ...habits.keys()])) {
    const h = habits.get(day);
    scores[day] = dayScore(kpis, logs[day] ?? {}, h?.planned === 1, h?.reflected === 1);
  }
  const trend: { day: string; score: number }[] = [];
  for (const d = new Date(`${since30 < start ? start : since30}T12:00:00Z`); d.toISOString().slice(0, 10) <= today; d.setUTCDate(d.getUTCDate() + 1)) {
    const day = d.toISOString().slice(0, 10);
    trend.push({ day, score: scores[day] ?? 0 });
  }
  const byId = new Map(kpis.map((k) => [k.id, k]));
  let todosDone = 0;
  const perArea: Record<string, number> = {};
  for (const [day, values] of Object.entries(logs)) {
    if (day < since30) continue;
    for (const [id, value] of Object.entries(values)) {
      const kpi = byId.get(id);
      if (!kpi || !kpiMet(kpi, value)) continue;
      todosDone++;
      const area = kpi.area ?? "karriere";
      perArea[area] = (perArea[area] ?? 0) + 1;
    }
  }
  const weekItems = weeks.results.flatMap((w) => (JSON.parse(w.json) as WeekPlan).items);
  const msPerDay = 86_400_000;
  return c.json({
    since: start,
    daysWith: Math.floor((Date.parse(`${today}T12:00:00Z`) - Date.parse(`${start}T12:00:00Z`)) / msPerDay) + 1,
    goodDays: Object.values(scores).filter((s) => s >= GOOD_DAY).length,
    streak: weekSummary(today, scores, start).streak,
    trend,
    todosDone,
    perArea,
    weekTodosDone: weekItems.filter((i) => i.done).length,
    weekTodosTotal: weekItems.length,
    plans: days.results.filter((d) => d.planned === 1).length,
    evenings: days.results.filter((d) => d.reflected === 1).length,
    talks: talks?.n ?? 0,
    requests: requests?.n ?? 0,
  });
});

async function loadList(env: Env, device: string, day: string): Promise<ListItem[] | null> {
  const row = await env.DB.prepare("SELECT list_json FROM days WHERE device_id = ? AND day = ?").bind(device, day).first<{ list_json: string | null }>();
  return row?.list_json ? (JSON.parse(row.list_json) as ListItem[]) : null;
}

async function saveList(env: Env, device: string, items: ListItem[]): Promise<void> {
  await env.DB.prepare(
    "INSERT INTO days (device_id, day, list_json, last_activity) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (device_id, day) DO UPDATE SET list_json = ?3, last_activity = ?4",
  )
    .bind(device, berlinDay(new Date()), JSON.stringify(items), new Date().toISOString())
    .run();
}

const ORDER = { now: 0, next: 1, later: 2 } as const;
const sortList = (items: ListItem[]) => [...items].sort((a, b) => ORDER[a.quadrant] - ORDER[b.quadrant]);

/** The coach builds today's list from vision, goals, talks, habits and what is still open (or rebuilds it with `fresh`). */
app.post("/v1/today/list", async (c) => {
  const { fresh } = z.object({ fresh: z.boolean().default(false) }).parse(await c.req.json().catch(() => ({})));
  const env = c.env;
  const device = c.var.device;
  const today = berlinDay(new Date());
  const existing = await loadList(env, device, today);
  if (existing && !fresh) return c.json({ items: existing });
  const { draft, name, file } = await loadDraft(env, device);
  await meter(c);
  const kpis = (await loadKpis(env, device)).filter((k) => k.source === "manual");
  const yesterday = new Date(`${today}T12:00:00Z`);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  const before = existing ?? (await loadList(env, device, yesterday.toISOString().slice(0, 10))) ?? [];
  const open = before.filter((i) => !i.done && i.source !== "habit").map((i) => i.title).join("; ");
  const made = await ask(env, DayListSchema, dayListPrompt(draft, today, name, file, await lastAgreement(env, device), kpis.map((k) => `${k.id}: ${k.name}`).join("; "), open));
  const logged = (await kpiLogs(env, device, today))[today] ?? {};
  const kpiIds = new Set(kpis.map((k) => k.id));
  // A fresh list keeps what is already done today.
  const kept = (existing ?? []).filter((i) => i.done);
  const items: ListItem[] = made.items.map((i) => {
    const kpiId = kpiIds.has(i.habit) ? i.habit : undefined;
    return { id: crypto.randomUUID(), title: i.title, why: i.why, quadrant: i.quadrant, source: kpiId ? "habit" : "coach", ...(kpiId && { kpiId }), done: kpiId ? (logged[kpiId] ?? 0) >= 1 : false };
  });
  const list = sortList([...kept, ...items.filter((i) => !kept.some((k) => k.title === i.title))]).slice(0, 12);
  await saveList(env, device, list);
  return c.json({ items: list });
});

/** The person adds an entry; the coach sorts it in (or advises to let it wait). */
app.post("/v1/today/add", async (c) => {
  const { title } = z.object({ title: z.string().trim().min(1).max(90) }).parse(await c.req.json());
  const env = c.env;
  const device = c.var.device;
  const { draft, file } = await loadDraft(env, device);
  await meter(c);
  const sorted = await ask(env, SortSchema, sortPrompt(draft, title, file));
  const list = (await loadList(env, device, berlinDay(new Date()))) ?? [];
  const item: ListItem = { id: crypto.randomUUID(), title, why: sorted.why, quadrant: sorted.quadrant === "drop" ? "later" : sorted.quadrant, source: "own", done: false };
  const next = sortList([...list, item]).slice(0, 15);
  await saveList(env, device, next);
  return c.json({ items: next, advice: sorted.quadrant === "drop" ? sorted.why : null });
});

app.post("/v1/today/check", async (c) => {
  const { id, done } = z.object({ id: z.string().uuid(), done: z.boolean() }).parse(await c.req.json());
  const env = c.env;
  const device = c.var.device;
  const today = berlinDay(new Date());
  const list = await loadList(env, device, today);
  const item = list?.find((i) => i.id === id);
  if (!list || !item) throw new HttpError(404, "Diesen Eintrag gibt es nicht mehr.");
  item.done = done;
  await saveList(env, device, list);
  // Habits are also the daily to-dos of their life area.
  if (item.kpiId) {
    await env.DB.prepare("INSERT INTO kpi_logs (device_id, day, kpi_id, value) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (device_id, day, kpi_id) DO UPDATE SET value = ?4")
      .bind(device, today, item.kpiId, done ? 1 : 0)
      .run();
  }
  return c.json({ items: list });
});

app.post("/v1/today/remove", async (c) => {
  const { id } = z.object({ id: z.string().uuid() }).parse(await c.req.json());
  const list = ((await loadList(c.env, c.var.device, berlinDay(new Date()))) ?? []).filter((i) => i.id !== id);
  await saveList(c.env, c.var.device, list);
  return c.json({ items: list });
});

/**
 * The coach streak (like Duolingo): a day counts when the person answered the coach at least once - ticked
 * something on the list, talked with the coach, or took the evening call. One missed day per week is forgiven.
 */
async function coachStreak(env: Env, device: string, today: string, start: string): Promise<{ days: number; today: boolean; jokerUsed: boolean }> {
  const since = new Date(`${today}T12:00:00Z`);
  since.setUTCDate(since.getUTCDate() - 120);
  const from = since.toISOString().slice(0, 10) < start ? start : since.toISOString().slice(0, 10);
  const [days, kpiDone, talks] = await Promise.all([
    env.DB.prepare("SELECT day, list_json, plan_json, reflection_json FROM days WHERE device_id = ? AND day >= ?").bind(device, from).all<{ day: string; list_json: string | null; plan_json: string | null; reflection_json: string | null }>(),
    env.DB.prepare("SELECT DISTINCT day FROM kpi_logs WHERE device_id = ? AND day >= ? AND value >= 1").bind(device, from).all<{ day: string }>(),
    env.DB.prepare("SELECT day FROM voice_sessions WHERE device_id = ? AND day >= ? AND n > 0").bind(device, from).all<{ day: string }>(),
  ]);
  const active: Record<string, number> = {};
  for (const d of days.results) {
    const ticked = (d.list_json && (JSON.parse(d.list_json) as ListItem[]).some((i) => i.done)) || (d.plan_json && (JSON.parse(d.plan_json) as DayPlan).tasks.some((t) => t.done));
    if (ticked || d.reflection_json) active[d.day] = 100;
  }
  for (const r of [...kpiDone.results, ...talks.results]) active[r.day] = 100;
  const summary = weekSummary(today, active, start);
  return { days: summary.streak, today: active[today] === 100, jokerUsed: summary.jokerUsed };
}

const QUADRANT_LABEL = { now: "wichtig und dringend", next: "Schritt nach vorn", later: "wenn Zeit bleibt" } as const;

/** Today's list as the coach reads it, plus what stayed open yesterday: "erledigt: … (wichtig und dringend)". */
async function listForCoach(env: Env, device: string): Promise<string> {
  const today = berlinDay(new Date());
  const yesterday = new Date(`${today}T12:00:00Z`);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  const [now, before] = await Promise.all([loadList(env, device, today), loadList(env, device, yesterday.toISOString().slice(0, 10))]);
  const lines = (now ?? []).map((i) => `${i.done ? "erledigt" : "offen"}: ${i.title} (${QUADRANT_LABEL[i.quadrant]})`);
  const missed = (before ?? []).filter((i) => !i.done && i.source !== "habit" && !(now ?? []).some((n) => n.title === i.title));
  const out = [lines.length ? `Heute:\n${lines.join("\n")}` : "Für heute gibt es noch keine Liste.", missed.length ? `Gestern offen geblieben:\n${missed.map((i) => i.title).join("\n")}` : ""];
  return out.filter(Boolean).join("\n\n").slice(0, 3000);
}

/** Logs today's value of one KPI (typed by the person or read from the Health app). */
app.post("/v1/kpis/log", async (c) => {
  const { id, value } = z.object({ id: z.string().uuid(), value: z.number().min(0).max(1_000_000) }).parse(await c.req.json());
  const kpis = await loadKpis(c.env, c.var.device);
  if (!kpis.some((k) => k.id === id)) throw new HttpError(404, "Dieses To-do gibt es nicht mehr.");
  await c.env.DB.prepare("INSERT INTO kpi_logs (device_id, day, kpi_id, value) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (device_id, day, kpi_id) DO UPDATE SET value = ?4")
    .bind(c.var.device, berlinDay(new Date()), id, value)
    .run();
  return c.json({ ok: true });
});

type WeekItem = z.infer<typeof WeekSchema>["items"][number] & { id: string; done: boolean };
type WeekPlan = { week: string; focus: string; items: WeekItem[] };

async function loadWeek(env: Env, device: string, week: string): Promise<WeekPlan | null> {
  const row = await env.DB.prepare("SELECT json FROM weeks WHERE device_id = ? AND week = ?").bind(device, week).first<{ json: string }>();
  return row ? (JSON.parse(row.json) as WeekPlan) : null;
}

async function saveWeek(env: Env, device: string, plan: WeekPlan): Promise<void> {
  await env.DB.prepare("INSERT INTO weeks (device_id, week, json) VALUES (?1, ?2, ?3) ON CONFLICT (device_id, week) DO UPDATE SET json = ?3")
    .bind(device, plan.week, JSON.stringify(plan))
    .run();
}

/** Creates (or with `fresh` recreates) this week's to-dos from the contract, the file and last week. */
app.post("/v1/week/plan", async (c) => {
  const { fresh } = z.object({ fresh: z.boolean().default(false) }).parse(await c.req.json().catch(() => ({})));
  const device = c.var.device;
  const today = berlinDay(new Date());
  const week = mondayOf(today);
  const existing = await loadWeek(c.env, device, week);
  if (existing && !fresh) return c.json(existing);
  const { draft, name, file } = await loadDraft(c.env, device);
  await meter(c);
  const prevMonday = new Date(`${week}T12:00:00Z`);
  prevMonday.setUTCDate(prevMonday.getUTCDate() - 7);
  const previous = await loadWeek(c.env, device, prevMonday.toISOString().slice(0, 10));
  // On a fresh plan this week's own list counts as the previous one, so finished items are not planned again.
  const before = existing ?? previous;
  const done = before ? before.items.map((i) => `${i.done ? "erledigt" : "offen"}: ${i.title}`).join("; ") : "";
  const made = await ask(c.env, WeekSchema, weekPrompt(draft, week, today, name, file, await lastAgreement(c.env, device), done));
  const kept = existing ? existing.items.filter((i) => i.done) : [];
  const plan: WeekPlan = { week, focus: made.focus, items: [...kept, ...made.items.map((i) => ({ ...i, id: crypto.randomUUID(), done: false }))].slice(0, 9) };
  await saveWeek(c.env, device, plan);
  return c.json(plan);
});

app.post("/v1/week/check", async (c) => {
  const { id, done } = z.object({ id: z.string().uuid(), done: z.boolean() }).parse(await c.req.json());
  const plan = await loadWeek(c.env, c.var.device, mondayOf(berlinDay(new Date())));
  const item = plan?.items.find((i) => i.id === id);
  if (!plan || !item) throw new HttpError(404, "Dieses To-do gibt es nicht mehr.");
  item.done = done;
  await saveWeek(c.env, c.var.device, plan);
  return c.json(plan);
});

app.post("/v1/day/check", async (c) => {
  const { index, done } = z.object({ index: z.number().int().min(0).max(11), done: z.boolean() }).parse(await c.req.json());
  const plan = await todayPlan(c.env, c.var.device);
  const task = plan.tasks[index];
  if (!task) throw new HttpError(400, "Diese Aufgabe gibt es nicht.");
  task.done = done;
  await saveDay(c.env, c.var.device, "plan_json", plan);
  return c.json(plan);
});

type StoredReflection = { causes?: { task: string; cause: string }[]; fix?: string };

app.post("/v1/day/reflect", async (c) => {
  const body = z
    .object({
      text: z.string().trim().max(2000).default(""),
      causes: z.array(z.object({ index: z.number().int().min(0).max(11), cause: z.string().trim().min(1).max(80) })).max(12).default([]),
    })
    .parse(await c.req.json());
  const device = c.var.device;
  const { draft, name, file } = await loadDraft(c.env, device);
  const plan = await todayPlan(c.env, device);
  const causeOf = new Map(body.causes.map((x) => [x.index, x.cause]));
  const open = plan.tasks.some((t) => !t.done);
  if (!body.text && open && causeOf.size === 0) throw new HttpError(400, "Sag kurz, woran es bei den offenen Aufgaben lag.");
  await meter(c);
  const today = berlinDay(new Date());
  const earlier = await c.env.DB.prepare("SELECT reflection_json FROM days WHERE device_id = ? AND day < ? AND reflection_json IS NOT NULL ORDER BY day DESC LIMIT 7")
    .bind(device, today)
    .all<{ reflection_json: string }>();
  const counts = new Map<string, number>();
  for (const row of earlier.results) for (const x of (JSON.parse(row.reflection_json) as StoredReflection).causes ?? []) counts.set(x.cause, (counts.get(x.cause) ?? 0) + 1);
  const history = [...counts].map(([cause, n]) => `${cause} (${n}x)`).join(", ");
  const kpiText = await kpiStatus(c.env, device);
  const lines = `${plan.tasks.map((t, i) => (t.done ? `[erledigt] ${t.text}` : `[offen – Grund: ${causeOf.get(i) ?? "nicht genannt"}] ${t.text}`)).join("\n")}${kpiText ? `\n\nTägliche To-dos:\n${kpiText}` : ""}`;
  const coach = await ask(c.env, ReflectSchema, reflectPrompt(draft, lines, body.text, history, name, file));
  const causes = plan.tasks.flatMap((t, i) => (!t.done && causeOf.has(i) ? [{ task: t.text, cause: causeOf.get(i) ?? "" }] : []));
  const reflection = { text: body.text, ...coach, causes };
  await saveDay(c.env, device, "reflection_json", reflection);
  const material = `Tagesplan und Stand:\n${lines}\nErgänzung der Person: ${body.text || "(keine)"}\nUrsache laut Coach (Einschätzung): ${coach.cause}\nVereinbarung für morgen: ${coach.fix}`;
  c.executionCtx.waitUntil(updateFile(c.env, device, "Abend-Rechenschaft", material));
  return c.json(reflection);
});

app.post("/v1/goals/change", async (c) => {
  const body = z.object({ goalId: z.string().uuid(), proposed: z.string().trim().min(5).max(160), reason: z.string().trim().min(10).max(800) }).parse(await c.req.json());
  const device = c.var.device;
  const { draft, goals } = await loadDraft(c.env, device);
  const goal = goals.find((g) => g.id === body.goalId);
  if (!goal) throw new HttpError(404, "Ziel nicht gefunden.");
  const history = await c.env.DB.prepare("SELECT status, created_at, effective_at FROM change_requests WHERE device_id = ?").bind(device).all<ChangeRow>();
  const now = new Date();
  const blocked = changeBlocked(history.results, now);
  if (blocked) throw new HttpError(409, blocked);
  await meter(c);
  const { reply } = await ask(c.env, ReplySchema, changePrompt(draft, goal.title, body.proposed, body.reason));
  const row = { id: crypto.randomUUID(), goal_id: goal.id, proposed: body.proposed, coach_reply: reply, effective_at: coolingOffEnd(now) };
  await c.env.DB.prepare("INSERT INTO change_requests (id, device_id, goal_id, reason, proposed, coach_reply, created_at, effective_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
    .bind(row.id, device, row.goal_id, body.reason, row.proposed, row.coach_reply, now.toISOString(), row.effective_at)
    .run();
  return c.json(row);
});

app.post("/v1/goals/change/:action{confirm|withdraw}", async (c) => {
  const { id } = z.object({ id: z.string().uuid() }).parse(await c.req.json());
  const device = c.var.device;
  const change = await c.env.DB.prepare("SELECT goal_id, proposed, status, created_at, effective_at FROM change_requests WHERE id = ? AND device_id = ?")
    .bind(id, device)
    .first<ChangeRow & { goal_id: string; proposed: string }>();
  if (!change || change.status !== "pending") throw new HttpError(404, "Keine offene Änderung gefunden.");
  if (c.req.param("action") === "withdraw") {
    await c.env.DB.prepare("UPDATE change_requests SET status = 'withdrawn' WHERE id = ?").bind(id).run();
    return c.json({ ok: true });
  }
  const now = new Date();
  if (!canConfirm(change, now)) throw new HttpError(409, "Die Bedenkzeit läuft noch.");
  const goal = await c.env.DB.prepare("SELECT json FROM goals WHERE id = ? AND device_id = ?").bind(change.goal_id, device).first<{ json: string }>();
  if (!goal) throw new HttpError(404, "Ziel nicht gefunden.");
  const updated: Goal = { ...(JSON.parse(goal.json) as Goal), title: change.proposed };
  await c.env.DB.batch([
    c.env.DB.prepare("UPDATE goals SET json = ?, locked_until = ? WHERE id = ?").bind(JSON.stringify(updated), lockedUntil(now), change.goal_id),
    c.env.DB.prepare("UPDATE change_requests SET status = 'applied', effective_at = ? WHERE id = ?").bind(now.toISOString(), id),
  ]);
  return c.json({ ok: true });
});

app.post("/v1/contact", async (c) => {
  const body = z
    .object({
      phone: z.string().regex(/^\+[1-9]\d{7,14}$/).nullable(),
      callHour: z.number().int().min(8).max(21),
      callMinute: z.union([z.literal(0), z.literal(15), z.literal(30), z.literal(45)]).default(0),
      days: z.array(z.number().int().min(1).max(7)).max(7).default([1, 2, 3, 4, 5, 6, 7]),
    })
    .parse(await c.req.json());
  // Entering the number on the "Abend-Anruf" card is the consent to be called on it; an empty number withdraws it.
  const days = [...new Set(body.days)].sort().join("");
  // ponytail: no ownership proof (SMS code) yet. Until then a number bound to one device cannot be claimed
  // by another (unique index users_phone), so nobody can redirect someone else's calls or call summaries.
  try {
    await c.env.DB.prepare("UPDATE users SET phone = ?, nudge_consent = ?, call_hour = ?, call_minute = ?, call_days = ? WHERE device_id = ?")
      .bind(body.phone, body.phone ? 1 : 0, body.callHour, body.callMinute, days, c.var.device)
      .run();
  } catch (err) {
    if (String(err).includes("UNIQUE")) throw new HttpError(409, "Diese Nummer ist bereits mit einem anderen Gerät verbunden.");
    throw err;
  }
  return c.json({ ok: true });
});

/** Shared by the button and the cron: checks consent and caps, then asks voice-kit to place the call. */
async function triggerCall(env: Env, device: string): Promise<void> {
  const user = await env.DB.prepare("SELECT phone, nudge_consent, committed_at FROM users WHERE device_id = ?")
    .bind(device)
    .first<{ phone: string | null; nudge_consent: number; committed_at: string | null }>();
  if (!user?.committed_at) throw new HttpError(409, "Der Coach ruft erst an, wenn dein Zielvertrag steht.");
  if (user.nudge_consent !== 1 || !user.phone) throw new HttpError(409, "Speichere zuerst deine Nummer und deine Einwilligung für den Anruf.");
  if (!callableNumber(user.phone)) throw new HttpError(409, "Der Coach ruft nur Nummern aus Deutschland, Österreich und der Schweiz an.");
  // ponytail: numbers are not verified (no SMS code yet), so only allowlisted numbers are dialled. Unset = no calls.
  // Replace with a verification step before opening this to the public.
  if (!(env.CALL_ALLOWLIST ?? "").split(",").includes(user.phone)) {
    throw new HttpError(409, "Anrufe sind in der Testphase nur für freigeschaltete Nummern möglich.");
  }
  const now = new Date();
  const hour = berlinHour(now);
  if (hour < 8 || hour >= 22) throw new HttpError(409, "Der Coach ruft nur zwischen 8 und 22 Uhr an.");
  const today = berlinDay(now);
  // Slots are taken before calling voice-kit and never handed back, so concurrent requests cannot exceed the caps.
  const slot = await env.DB.prepare(
    "INSERT INTO call_log (phone, day, n) VALUES (?1, ?2, 1) ON CONFLICT (phone, day) DO UPDATE SET n = n + 1 WHERE n < ?3 RETURNING n",
  )
    .bind(user.phone, today, Number(env.MAX_CALLS_PER_DAY))
    .first<{ n: number }>();
  if (!slot) throw new HttpError(429, "Für heute hat der Coach dich schon oft genug angerufen.");
  const total = await env.DB.prepare("SELECT SUM(n) AS n FROM call_log WHERE day = ?").bind(today).first<{ n: number }>();
  if ((total?.n ?? 0) > Number(env.MAX_CALLS_GLOBAL_PER_DAY)) throw new HttpError(429, "Heute sind keine Anrufe mehr frei. Morgen wieder.");
  // Marked as called before dialling: a slow voice-kit answer must not make the cron dial the same person again.
  await env.DB.prepare("INSERT INTO days (device_id, day, called_at) VALUES (?1, ?2, ?3) ON CONFLICT (device_id, day) DO UPDATE SET called_at = ?3")
    .bind(device, today, now.toISOString())
    .run();
  const { draft, name, file } = await loadDraft(env, device);
  const day = await env.DB.prepare("SELECT plan_json FROM days WHERE device_id = ? AND day = ?").bind(device, today).first<{ plan_json: string | null }>();
  const list = await loadList(env, device, today);
  const plan = list
    ? { tasks: list.map((i) => ({ text: `${i.title}${i.quadrant === "now" ? " (wichtig und dringend)" : i.quadrant === "next" ? " (Schritt nach vorn)" : ""}`, done: i.done })), check: { score: listScore(list) } }
    : day?.plan_json
      ? (JSON.parse(day.plan_json) as DayPlan)
      : null;
  const res = await fetch(`${env.VOICE_KIT_URL}/outbound/${env.VOICE_AGENT}`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.VOICE_KIT_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ to: user.phone, context: callContext(draft, plan, name, file, await kpiStatus(env, device)) }),
    signal: AbortSignal.timeout(10_000),
  }).catch((err: unknown) => {
    console.error("voice-kit unreachable", err);
    return null;
  });
  if (!res?.ok) {
    if (res) console.error("voice-kit", res.status, await res.text());
    throw new HttpError(502, "Der Anruf konnte gerade nicht gestartet werden. Versuch es später noch einmal.");
  }
}

app.post("/v1/call/now", async (c) => {
  await triggerCall(c.env, c.var.device);
  return c.json({ ok: true });
});

app.delete("/v1/me", async (c) => {
  const d = c.var.device;
  await c.env.DB.batch(["users", "goals", "change_requests", "days", "usage", "weeks", "kpi_logs", "boards"].map((t) => c.env.DB.prepare(`DELETE FROM ${t} WHERE device_id = ?`).bind(d)));
  return c.json({ ok: true });
});

/** Every 15 minutes: call users whose chosen Berlin hour has come and who were not called today. */
async function scheduled(controller: ScheduledController, env: Env): Promise<void> {
  const now = new Date(controller.scheduledTime);
  const rows = await env.DB.prepare(
    "SELECT u.device_id, u.phone, u.nudge_consent, u.committed_at, u.call_hour, u.call_minute, u.call_days, d.called_at FROM users u LEFT JOIN days d ON d.device_id = u.device_id AND d.day = ? WHERE u.nudge_consent = 1 AND u.call_hour = ? AND d.called_at IS NULL AND d.reflection_json IS NULL",
  )
    .bind(berlinDay(now), berlinHour(now))
    .all<CallCandidate & { device_id: string }>();
  for (const u of rows.results.filter((r) => callDue(r, now)).slice(0, 20)) {
    try {
      await triggerCall(env, u.device_id);
    } catch (err) {
      console.error("scheduled call", u.device_id, err instanceof Error ? err.message : err);
    }
  }
}

export default { fetch: app.fetch, scheduled } satisfies ExportedHandler<Env>;
