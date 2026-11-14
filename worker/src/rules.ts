// Accountability rules for locked goals. Pure, so they are testable without D1.

export const LOCK_DAYS = 30;
export const COOLING_OFF_HOURS = 48;
const DAY_MS = 86_400_000;

export type ChangeRow = { status: "pending" | "applied" | "withdrawn"; created_at: string; effective_at: string };

export function lockedUntil(from: Date): string {
  return new Date(from.getTime() + LOCK_DAYS * DAY_MS).toISOString();
}

export function coolingOffEnd(from: Date): string {
  return new Date(from.getTime() + COOLING_OFF_HOURS * 3_600_000).toISOString();
}

/** null = allowed; otherwise the German reason shown to the user. */
export function changeBlocked(history: ChangeRow[], now: Date): string | null {
  if (history.some((c) => c.status === "pending")) return "Es läuft bereits eine Änderung in der Bedenkzeit.";
  const recent = history.find((c) => c.status === "applied" && now.getTime() - Date.parse(c.effective_at) < LOCK_DAYS * DAY_MS);
  if (recent) return `Du hast in den letzten ${LOCK_DAYS} Tagen schon ein Ziel geändert. Bleib dran.`;
  return null;
}

export function canConfirm(change: ChangeRow, now: Date): boolean {
  return change.status === "pending" && now.getTime() >= Date.parse(change.effective_at);
}

/** YYYY-MM-DD in Europe/Berlin. */
export function berlinDay(d: Date): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Berlin" }).format(d);
}

export function berlinHour(d: Date): number {
  return Number(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Berlin", hour: "2-digit", hourCycle: "h23" }).format(d));
}

/** Consecutive planned days ending today or yesterday. `days` = planned days, any order. */
export function streak(days: string[], today: string): number {
  const set = new Set(days);
  const cursor = new Date(`${today}T12:00:00Z`);
  if (!set.has(today)) cursor.setUTCDate(cursor.getUTCDate() - 1);
  let n = 0;
  while (set.has(cursor.toISOString().slice(0, 10))) {
    n++;
    cursor.setUTCDate(cursor.getUTCDate() - 1);
  }
  return n;
}

const CALL_PREFIXES = ["+49", "+43", "+41"];

/** Calls only go to DE, AT and CH numbers. */
export function callableNumber(phone: string | null): phone is string {
  return phone !== null && CALL_PREFIXES.some((p) => phone.startsWith(p));
}

export type CallCandidate = { phone: string | null; nudge_consent: number; committed_at: string | null; call_hour: number; call_minute: number; call_days: string; called_at: string | null };

/** The evening call is due in the user's chosen Berlin hour, once per day, only with consent and a signed contract. */
export function callDue(u: CallCandidate, now: Date): boolean {
  const hour = berlinHour(now);
  const minute = Number(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Berlin", minute: "2-digit" }).format(now));
  return (
    u.nudge_consent === 1 &&
    u.committed_at !== null &&
    callableNumber(u.phone) &&
    u.call_days.includes(String(berlinWeekday(now))) &&
    u.call_hour === hour &&
    minute >= u.call_minute &&
    u.called_at === null
  );
}

/** ISO weekday in Berlin: 1 = Monday ... 7 = Sunday. */
export function berlinWeekday(d: Date): number {
  const day = new Date(`${berlinDay(d)}T12:00:00Z`).getUTCDay();
  return day === 0 ? 7 : day;
}

/** A spoken conversation is longer than the typed interview; /v1/draft accepts this many turns. */
export const MAX_SPOKEN_TURNS = 60;

export type TranscriptEntry = { speaker: "agent" | "caller"; text: string };

/** Realtime transcript -> interview turns. Each caller entry answers the agent text since the previous caller entry
 *  (consecutive agent entries are joined). Agent text nobody answered is dropped. Keeps the last 60 turns.
 *  The app does this pairing (LiveVoice.pair); this copy documents and tests the rule. */
export function pairTranscript(entries: TranscriptEntry[]): { question: string; answer: string }[] {
  const turns: { question: string; answer: string }[] = [];
  let question = "";
  for (const e of entries) {
    const text = e.text.trim();
    if (!text) continue;
    if (e.speaker === "agent") {
      question = question ? `${question} ${text}` : text;
    } else {
      turns.push({ question: question.slice(0, 600), answer: text.slice(0, 2000) });
      question = "";
    }
  }
  return turns.slice(-MAX_SPOKEN_TURNS);
}

/** Follow-up focus chosen in the app -> the FOCUS value the voice-kit follow-up agent expects. */
export const FOCUS_LABEL = { beliefs: "Glaubenssätze", values: "Werte", open: "offen", help: "Hilfe jetzt", todo: "To-do" } as const;

export type Kpi = { id: string; area?: string; name: string; unit: string; target: number; direction: "atLeast" | "atMost" | "check"; source: "manual" | "steps" | "weight" };

/** Whether a logged value meets the KPI's daily target. */
export function kpiMet(kpi: Kpi, value: number): boolean {
  if (kpi.direction === "check") return value >= 1;
  return kpi.direction === "atLeast" ? value >= kpi.target : value <= kpi.target;
}

/** One entry of the day's list. `quadrant`: now = important and urgent, next = important not urgent, later = urgent not important. */
export type ListItem = { id: string; title: string; why: string; quadrant: "now" | "next" | "later"; source: "coach" | "habit" | "own"; kpiId?: string; done: boolean };

/** Steps forward weigh most, urgent small stuff least. */
export const QUADRANT_WEIGHT = { now: 3, next: 4, later: 1 } as const;

/** Day score from the day's list: the weighted share of done items, 0-100. */
export function listScore(items: ListItem[]): number {
  const total = items.reduce((sum, i) => sum + QUADRANT_WEIGHT[i.quadrant], 0);
  if (!total) return 0;
  return Math.round((items.filter((i) => i.done).reduce((sum, i) => sum + QUADRANT_WEIGHT[i.quadrant], 0) / total) * 100);
}

/** A day counts as good (for the streak) from this score on. */
export const GOOD_DAY = 70;

/**
 * Score of one day, 0-100: 70 for the to-dos (logging and meeting each count half), 30 for the day plan.
 * Without to-dos, the plan makes up the whole score. (`reflected` no longer counts; kept for callers.)
 */
export function dayScore(kpis: Kpi[], logged: Record<string, number>, planned: boolean, reflected: boolean): number {
  void reflected;
  const habits = planned ? 30 : 0;
  if (!kpis.length) return Math.round((habits / 30) * 100);
  let parts = 0;
  for (const kpi of kpis) {
    const value = logged[kpi.id];
    if (value === undefined) continue;
    parts += 1;
    if (kpiMet(kpi, value)) parts += 1;
  }
  return Math.round((parts / (2 * kpis.length)) * 70 + habits);
}

export type WeekSummary = { average: number; days: { day: string; score: number }[]; streak: number; jokerUsed: boolean };

/**
 * `scores`: day -> score for every day that has one (missing days score 0). The week average runs over Monday..today.
 * The streak counts good days back from today (or yesterday while today is not good yet); one missed day per
 * ISO week is forgiven (the joker), so a single slip does not end it.
 */
/** `since`: the day the person signed; earlier days of the week do not count. */
export function weekSummary(today: string, scores: Record<string, number>, since = ""): WeekSummary {
  const days = weekDaysUntil(today).filter((d) => d >= since).map((day) => ({ day, score: scores[day] ?? 0 }));
  const average = Math.round(days.reduce((sum, d) => sum + d.score, 0) / days.length);
  const cursor = new Date(`${today}T12:00:00Z`);
  if ((scores[today] ?? 0) < GOOD_DAY) cursor.setUTCDate(cursor.getUTCDate() - 1);
  const jokers = new Set<string>();
  let streak = 0;
  for (let i = 0; i < 400; i++) {
    const day = cursor.toISOString().slice(0, 10);
    if ((scores[day] ?? 0) >= GOOD_DAY) streak++;
    else if (!jokers.has(mondayOf(day)) && streak > 0) jokers.add(mondayOf(day));
    else break;
    cursor.setUTCDate(cursor.getUTCDate() - 1);
  }
  return { average, days, streak, jokerUsed: jokers.has(mondayOf(today)) };
}

/** The days of the week from Monday up to and including `today`. */
export function weekDaysUntil(today: string): string[] {
  const out: string[] = [];
  const d = new Date(`${mondayOf(today)}T12:00:00Z`);
  while (d.toISOString().slice(0, 10) <= today) {
    out.push(d.toISOString().slice(0, 10));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
}

/** Monday of the Berlin week that contains `day` (YYYY-MM-DD). */
export function mondayOf(day: string): string {
  const d = new Date(`${day}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
}

/** Sections of the coach's file on a person, in this order (contract A.1). */
export const FILE_SECTIONS = ["Ausgangslage", "Werte", "Glaubenssätze", "Stolpersteine und Muster", "Was funktioniert", "Vereinbarungen", "Offene Themen"] as const;
// Small enough to go whole into the voice coach's context (4000-char limit per value).
export const MAX_FILE_CHARS = 3500;
const MAX_OPEN_TOPICS = 5;

/** Model output -> the file in the exact section format: known headings only (markdown "#" and a trailing ":" are
 *  tolerated), fixed order, every entry a "- " line, empty sections dropped, at most five open topics, at most
 *  MAX_FILE_CHARS (cut at a line end). Text before the first heading or under an unknown heading is dropped.
 *  null = no usable entry. */
export function normaliseFile(text: string): string | null {
  const sections = new Map<string, string[]>();
  let current: string[] | null = null;
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    const heading = line.replace(/^#+\s*/, "").replace(/:$/, "").trim();
    if ((FILE_SECTIONS as readonly string[]).includes(heading)) {
      current = sections.get(heading) ?? [];
      sections.set(heading, current);
      continue;
    }
    if (/^#+\s/.test(line)) current = null;
    const entry = line.replace(/^[-*•]\s*/, "").trim();
    if (current && entry) current.push(`- ${entry}`);
  }
  const out = FILE_SECTIONS.flatMap((h) => {
    const entries = (sections.get(h) ?? []).slice(0, h === "Offene Themen" ? MAX_OPEN_TOPICS : undefined);
    return entries.length ? [[h, ...entries].join("\n")] : [];
  }).join("\n\n");
  if (!out) return null;
  return out.length <= MAX_FILE_CHARS ? out : out.slice(0, out.lastIndexOf("\n", MAX_FILE_CHARS));
}
