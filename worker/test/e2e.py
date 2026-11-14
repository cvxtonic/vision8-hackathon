"""Live smoke test against the deployed worker: interview -> draft -> commit -> day -> change. Deletes its data at the end."""
import json, sys, time, urllib.request, urllib.error, uuid

BASE = sys.argv[1]
KEY = dict(l.strip().split("=", 1) for l in open(".dev.vars"))["APP_KEY"]
DEV = str(uuid.uuid4())

def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"x-v8-key": KEY, "x-device-id": DEV, "content-type": "application/json", "user-agent": "vision8-e2e"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)

ANSWERS = [
    "Ich bin 31, angestellt im Vertrieb bei einem Softwarehaus, 52k brutto. Mich nervt, dass ich seit zwei Jahren von einer eigenen Beratung rede und nichts starte.",
    "Ich habe mal eine Website angefangen und nach drei Wochen aufgehört, weil im Job viel los war.",
    "Freiheit und dass ich stolz auf das bin, was ich aufbaue. Und Zeit für meine Tochter.",
    "In zehn Jahren habe ich eine kleine Vertriebsberatung mit fünf Leuten, arbeite vier Tage, hole meine Tochter mittags von der Schule ab.",
    "9",
    "In zwölf Monaten drei zahlende Kunden nebenberuflich und 2000 Euro Zusatzumsatz im Monat. Ich habe abends etwa sechs Stunden pro Woche.",
    "Ja, das passt so.", "8", "Sechs Stunden pro Woche sind realistisch.", "Ja.", "Ja.", "Ja.",
]
turns = []
for i in range(15):
    t0 = time.time(); s, q = call("POST", "/v1/interview/next", {"area": "karriere", "turns": turns}); assert s == 200, (s, q)
    if q["done"]:
        break
    ans = "9" if q["input"] == "scale" else (q["options"][0] if q["input"] == "choice" and q["options"] else ANSWERS[min(i, len(ANSWERS) - 1)])
    print(f"[{q['phase']}/{q['input']} {time.time()-t0:.1f}s] {q['mirror']} | {q['question']}\n   opts={q['options']} hint={q['hint']!r}\n   -> {ans[:70]}")
    turns.append({"question": q["question"], "answer": ans})
assert q["done"], "interview did not finish"
print("turns:", len(turns))

t0 = time.time(); s, draft = call("POST", "/v1/draft", {"area": "karriere", "turns": turns}); assert s == 200, (s, draft)
print(f"\nDRAFT {time.time()-t0:.1f}s\n", json.dumps(draft, ensure_ascii=False, indent=1))
assert [g["horizon"] for g in draft["goals"]] == ["10y", "3y", "1y", "month"]

assert call("GET", "/v1/state")[1] == {"committed": False}
assert call("POST", "/v1/voice/session", {"kind": "followup"})[0] == 409, "no follow-up conversation before the contract is signed"
assert call("POST", "/v1/voice/debrief", {"turns": [{"question": "Wie geht's?", "answer": "Gut."}]})[0] == 409, "no debrief before the contract is signed"
assert call("POST", "/v1/commit", {"area": "karriere", "draft": draft, "turns": turns})[0] == 200
for _ in range(30):
    s, st = call("GET", "/v1/state")
    if st.get("file"):
        break
    time.sleep(2)
assert st.get("file") and "Ausgangslage" in st["file"].splitlines() and st["fileUpdatedAt"], ("file not written within 60 s", st.get("file"))
print("\nAKTE\n" + st["file"])
assert call("POST", "/v1/commit", {"area": "karriere", "draft": draft})[0] == 409, "second commit must be rejected"
assert call("POST", "/v1/call/now")[0] == 409, "call without consent must be rejected"
assert call("POST", "/v1/voice/session", {"area": "karriere"})[0] == 409, "no realtime interview after the contract is signed"

s, plan = call("POST", "/v1/day/plan", {"tasks": ["Drei Wunschkunden auf LinkedIn anschreiben", "Wäsche waschen", "Zwei Stunden Netflix"]}); assert s == 200, (s, plan)
print("\nPLAN", json.dumps(plan["check"], ensure_ascii=False, indent=1))
assert plan["check"]["items"][0]["verdict"] == "zahlt_ein" and plan["check"]["items"][2]["verdict"] == "lenkt_ab"
s, p = call("POST", "/v1/day/check", {"index": 0, "done": True}); assert p["tasks"][0]["done"]
assert call("POST", "/v1/day/reflect", {})[0] == 400, "open tasks need a reason"
s, r = call("POST", "/v1/day/reflect", {"causes": [{"index": 1, "cause": "Keine Zeit"}, {"index": 2, "cause": "Aufgeschoben"}], "text": "Netflix wurden dann doch drei Stunden."}); assert s == 200, (s, r)
assert r["cause"] and r["fix"] and len(r["causes"]) == 2, r
print("\nREFLECT", r["reply"], "\nURSACHE", r["cause"], "\nFIX", r["fix"])

talk = [
    {"question": "Was hält dich gerade davon ab, deine Website online zu stellen?", "answer": "Ich glaube, ich muss erst perfekt sein, bevor ich etwas zeige."},
    {"question": "Habe ich dich richtig verstanden: Halbfertig zeigen fühlt sich für dich wie Versagen an? Seit wann denkst du so?", "answer": "Ja. Seit der Schule, da wurde nur das Ergebnis gelobt, nie der Versuch."},
    {"question": "Was wäre ein kleiner Schritt, den du trotzdem zeigen könntest – eine Seite, ein Post oder ein Gespräch?", "answer": "Eine Seite mit meinem Angebot, auch wenn sie noch nicht schön ist."},
]
s, d = call("POST", "/v1/voice/debrief", {"turns": talk}); assert s == 200 and d["summary"].strip(), (s, d)
print("\nDEBRIEF", d["summary"], "\nINSIGHT", d["insight"])
s, st = call("GET", "/v1/state"); assert st["lastTalk"] and st["lastTalk"]["summary"] == d["summary"], st.get("lastTalk")

s, st = call("GET", "/v1/state"); assert st["committed"] and st["streak"] == 1 and len(st["goals"]) == 4
gid = st["goals"][2]["id"]
s, ch = call("POST", "/v1/goals/change", {"goalId": gid, "proposed": "Ich gewinne einen zahlenden Kunden in 12 Monaten.", "reason": "Drei Kunden fühlen sich gerade zu viel an, der Job frisst mich auf."}); assert s == 200, (s, ch)
print("\nCHANGE", ch["coach_reply"])
assert call("POST", "/v1/goals/change/confirm", {"id": ch["id"]})[0] == 409, "confirm must wait for cooling-off"
assert call("POST", "/v1/goals/change", {"goalId": gid, "proposed": "Noch ein anderer Wunsch.", "reason": "Ich will schon wieder wechseln, einfach so."})[0] == 409
assert call("POST", "/v1/contact", {"phone": "+4915112345678", "consent": True, "callHour": 20})[0] == 200
MINE = DEV; DEV = str(uuid.uuid4())
assert call("POST", "/v1/contact", {"phone": "+4915112345678", "consent": True, "callHour": 20})[0] == 409, "a bound number must not be claimable by another device"
call("DELETE", "/v1/me"); DEV = MINE
assert call("DELETE", "/v1/me")[0] == 200 and call("GET", "/v1/state")[1] == {"committed": False}
bad = urllib.request.Request(BASE + "/v1/state", headers={"x-v8-key": "nope", "x-device-id": DEV, "user-agent": "vision8-e2e"})
try: urllib.request.urlopen(bad); raise SystemExit("unauthorized request passed")
except urllib.error.HTTPError as e: assert e.code == 401
hook = urllib.request.Request(BASE + "/internal/call-result", method="POST", data=json.dumps({"phone": "+4915112345678", "summary": "x", "reply": "y"}).encode(),
    headers={"authorization": "Bearer nope", "content-type": "application/json", "user-agent": "vision8-e2e"})
try: urllib.request.urlopen(hook); raise SystemExit("call-result with wrong key passed")
except urllib.error.HTTPError as e: assert e.code == 401
call("DELETE", "/v1/me")
print("\nE2E OK")
