import assert from "node:assert/strict";
import { callContext } from "../src/coach.ts";
import type { Kpi, ListItem } from "../src/rules.ts";
import { FILE_SECTIONS, FOCUS_LABEL, MAX_FILE_CHARS, berlinDay, mondayOf, weekDaysUntil, dayScore, weekSummary, kpiMet, listScore, berlinHour, callDue, callableNumber, canConfirm, changeBlocked, coolingOffEnd, normaliseFile, pairTranscript, streak } from "../src/rules.ts";

const now = new Date("2026-11-14T10:00:00Z");
const ago = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();

assert.equal(changeBlocked([], now), null);
assert.match(changeBlocked([{ status: "pending", created_at: ago(1), effective_at: ago(-47) }], now) ?? "", /Bedenkzeit/);
assert.match(changeBlocked([{ status: "applied", created_at: ago(24 * 10), effective_at: ago(24 * 8) }], now) ?? "", /30 Tagen/);
assert.equal(changeBlocked([{ status: "applied", created_at: ago(24 * 40), effective_at: ago(24 * 38) }], now), null);
assert.equal(changeBlocked([{ status: "withdrawn", created_at: ago(2), effective_at: ago(-46) }], now), null);

assert.equal(canConfirm({ status: "pending", created_at: ago(1), effective_at: coolingOffEnd(new Date(ago(1))) }, now), false);
assert.equal(canConfirm({ status: "pending", created_at: ago(49), effective_at: coolingOffEnd(new Date(ago(49))) }, now), true);
assert.equal(canConfirm({ status: "applied", created_at: ago(49), effective_at: ago(1) }, now), false);

assert.equal(berlinDay(new Date("2026-11-14T23:30:00Z")), "2026-11-15");
assert.equal(berlinHour(new Date("2026-11-14T19:05:00Z")), 20);

assert.equal(streak(["2026-11-14", "2026-11-13", "2026-11-12", "2026-11-10"], "2026-11-14"), 3);
assert.equal(streak(["2026-11-13", "2026-11-12"], "2026-11-14"), 2);
assert.equal(streak(["2026-11-11"], "2026-11-14"), 0);

const evening = new Date("2026-11-14T19:05:00Z"); // 20:05 Berlin
const due = { phone: "+4915112345678", nudge_consent: 1, committed_at: ago(48), call_hour: 20, call_minute: 0, call_days: "1234567", called_at: null };
assert.equal(callDue(due, evening), true);
assert.equal(callDue({ ...due, call_hour: 21 }, evening), false);
  assert.equal(callDue({ ...due, call_days: "12345" }, evening), false); // 2026-11-14 is a Saturday
  assert.equal(callDue({ ...due, call_days: "6" }, evening), true);
  assert.equal(callDue({ ...due, call_minute: 15 }, evening), false); // 20:05 is before 20:15
assert.equal(callDue({ ...due, called_at: evening.toISOString() }, evening), false);
assert.equal(callDue({ ...due, nudge_consent: 0 }, evening), false);
assert.equal(callDue({ ...due, committed_at: null }, evening), false);
assert.equal(callDue({ ...due, phone: null }, evening), false);
assert.equal(callDue({ ...due, phone: "+15551234567" }, evening), false);
assert.equal(callableNumber("+41791234567"), true);
assert.equal(callableNumber("+4915112345678"), true);
assert.equal(callableNumber("+33612345678"), false);

const draft = {
  vision: "V".repeat(900),
  why: "Weil ich es will.",
  values: ["Freiheit"],
  goals: [{ horizon: "1y" as const, title: "Drei Kunden", specific: "", measurable: "", achievable: "", relevant: "", deadline: "2027-11-14" }],
};
const ctx = callContext(draft, { tasks: [{ text: "Anrufen", done: true }, { text: "Sport", done: false }], check: { score: 72 } });
assert.equal(ctx.GOALS, "12 Monate: Drei Kunden (bis 2027-11-14)");
assert.equal(ctx.TODAY_PLAN, "erledigt: Anrufen\noffen: Sport\nTageswert: 72 von 100");
assert.match(callContext(draft, null).TODAY_PLAN, /keinen Plan/);
assert.ok(Object.values(callContext({ ...draft, goals: Array(400).fill(draft.goals[0]) }, null, null, "x".repeat(9000))).every((v) => v.length < 4000));
assert.equal(callContext(draft, null).AKTE, "");
assert.equal(callContext(draft, null, null, "y".repeat(5000)).AKTE.length, 3500);

assert.deepEqual(FOCUS_LABEL, { beliefs: "Glaubenssätze", values: "Werte", open: "offen", help: "Hilfe jetzt", todo: "To-do" });

assert.equal(normaliseFile(""), null);
assert.equal(normaliseFile("Ausgangslage\nWerte\n- "), null);
assert.equal(
  normaliseFile("Vorrede, die weg muss\n## Werte:\n* Freiheit\nZeit für die Tochter\nAusgangslage\n- Vertrieb, 31\n# Fremd\n- weg\nWerte\n- Stolz"),
  "Ausgangslage\n- Vertrieb, 31\n\nWerte\n- Freiheit\n- Zeit für die Tochter\n- Stolz",
);
const topics = normaliseFile(`Offene Themen\n${Array.from({ length: 8 }, (_, i) => `- T${i}`).join("\n")}`) ?? "";
assert.equal(topics, "Offene Themen\n- T0\n- T1\n- T2\n- T3\n- T4");
const full = normaliseFile(FILE_SECTIONS.map((h) => `${h}\n${"- eintrag\n".repeat(200)}`).join("\n")) ?? "";
assert.ok(full.length <= MAX_FILE_CHARS && full.startsWith("Ausgangslage\n- eintrag") && full.endsWith("- eintrag"));

const agent = (text: string) => ({ speaker: "agent" as const, text });
const caller = (text: string) => ({ speaker: "caller" as const, text });
assert.deepEqual(pairTranscript([]), []);
assert.deepEqual(pairTranscript([agent("Hallo."), agent("Was stört dich?"), caller("Mein Job."), caller(" Und das Geld. "), agent("Seit wann?"), caller("Zwei Jahre."), agent("Danke, bis bald.")]), [
  { question: "Hallo. Was stört dich?", answer: "Mein Job." },
  { question: "", answer: "Und das Geld." },
  { question: "Seit wann?", answer: "Zwei Jahre." },
]);
assert.deepEqual(pairTranscript([agent("  "), caller(""), agent("Frage?"), caller("Ja.")]), [{ question: "Frage?", answer: "Ja." }]);
const long = pairTranscript([agent("F".repeat(700)), caller("A".repeat(2500))])[0];
assert.equal(long?.question.length, 600);
assert.equal(long?.answer.length, 2000);
const many = pairTranscript(Array.from({ length: 70 }, (_, i) => [agent(`F${i}`), caller(`A${i}`)]).flat());
assert.equal(many.length, 60);
assert.deepEqual(many[0], { question: "F10", answer: "A10" });
assert.deepEqual(many.at(-1), { question: "F69", answer: "A69" });

assert.equal(mondayOf("2026-11-14"), "2026-11-09"); // Saturday
assert.equal(mondayOf("2026-11-09"), "2026-11-09"); // Monday
assert.equal(mondayOf("2026-11-15"), "2026-11-09"); // Sunday
{
  const kpis: Kpi[] = [
    { id: "a", name: "Schritte", unit: "Schritte", target: 8000, direction: "atLeast", source: "steps" },
    { id: "b", name: "Gewicht", unit: "kg", target: 82, direction: "atMost", source: "weight" },
  ];
  assert.deepEqual(weekDaysUntil("2026-11-11"), ["2026-11-09", "2026-11-10", "2026-11-11"]);
  assert.equal(dayScore(kpis, { a: 9000, b: 83 }, true, false), 83); // 3 of 4 parts -> 52.5, + 30 for the plan
  assert.equal(dayScore(kpis, {}, false, false), 0);
  assert.equal(dayScore(kpis, { a: 9000, b: 80 }, true, true), 100);
  assert.equal(dayScore([], {}, true, false), 100);
  assert.equal(dayScore([], {}, false, true), 0);
  // Thu 12th good, Wed 11th missed (joker), Tue 10th and Mon 9th good, Sun 8th missed again -> streak 3
  const w = weekSummary("2026-11-12", { "2026-11-12": 90, "2026-11-11": 20, "2026-11-10": 75, "2026-11-09": 80, "2026-11-08": 10 });
  assert.equal(w.streak, 3);
  assert.equal(w.jokerUsed, true);
  assert.equal(w.average, Math.round((80 + 75 + 20 + 90) / 4));
  assert.equal(weekSummary("2026-11-12", { "2026-11-12": 90 }, "2026-11-12").average, 90);
  assert.equal(kpiMet({ ...kpis[0]!, direction: "check", target: 1 }, 1), true);
}
{
  const item = (quadrant: ListItem["quadrant"], done: boolean): ListItem => ({ id: quadrant, title: "", why: "", quadrant, source: "coach", done });
  assert.equal(listScore([]), 0);
  assert.equal(listScore([item("now", true), item("next", true), item("later", false)]), 88); // 7 of 8
  assert.equal(listScore([item("now", false), item("next", false), item("later", true)]), 13);
}
console.log("rules ok");
