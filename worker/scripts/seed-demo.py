"""Resets one device to the product-demo persona "Mia" (signed SMART contract, daily to-dos per life area,
vision board, today's list). Usage: python3 scripts/seed-demo.py <api-base> <device-id>   (reads APP_KEY from .dev.vars)"""
import json, sys, time, urllib.error, urllib.request

BASE, DEVICE = sys.argv[1].rstrip("/"), sys.argv[2]
KEY = dict(l.strip().split("=", 1) for l in open(".dev.vars") if "=" in l)["APP_KEY"]


def call(method, path, body=None, timeout=180):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"x-v8-key": KEY, "x-device-id": DEVICE, "content-type": "application/json", "user-agent": "vision8-seed"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def goal(horizon, title, specific, measurable, achievable, relevant, deadline):
    return dict(horizon=horizon, title=title, specific=specific, measurable=measurable, achievable=achievable, relevant=relevant, deadline=deadline)


DRAFT = {
    "vision": "Es ist ein Mittwochmorgen. Ich bringe Lina entspannt zur Schule und fahre danach ins Büro, wo ich als Teamleiterin ein Team von acht Menschen führe, das gern mit mir arbeitet. Zweimal die Woche laufe ich an der Elbe, ich habe ein Polster, das mich ruhig schlafen lässt, und meine Abende gehören meiner Familie und mir.",
    "why": "Ich will nicht mehr nur funktionieren, sondern mein Leben selbst gestalten. Lina soll eine Mutter erleben, die Zeit für sie hat und an sich glaubt.",
    "values": ["Selbstbestimmung", "Familie", "Gesundheit", "Wachstum"],
    "goals": [
        goal("10y", "Bis 14.11.2036 leite ich einen Bereich mit 20 Mitarbeitenden in einer Vier-Tage-Woche.",
             "Bereichsleitung mit Personalverantwortung für rund 20 Menschen, 32 Stunden an vier Tagen.",
             "Bereichsleitung mit mindestens 20 Mitarbeitenden im Vertrag, Vier-Tage-Woche schriftlich vereinbart.",
             "Zehn Jahre reichen für zwei Schritte: erst Teamleitung, dann Bereichsleitung, mit der Führungserfahrung der nächsten drei Jahre als Grundlage.",
             "Verbindet Gestaltungsfreiheit im Beruf mit der Zeit für meine Familie.", "2036-11-14"),
        goal("3y", "Bis 14.11.2029 bin ich Teamleiterin mit Verantwortung für mindestens 8 Menschen.",
             "Feste Teamleitung mit disziplinarischer Verantwortung in meinem Unternehmen.",
             "Teamleitung im Vertrag, mindestens 8 direkte Mitarbeitende.",
             "Mein Unternehmen besetzt jedes Jahr mehrere Teamleitungen intern; mit Führungsprogramm und meiner Projekterfahrung bin ich eine realistische Kandidatin.",
             "Der erste große Schritt zu dem Mittwochmorgen aus meiner Vision.", "2029-11-14"),
        goal("1y", "Bis 14.11.2027 habe ich das interne Führungskräfteprogramm mit Zertifikat abgeschlossen.",
             "Alle 6 Module des Programms besucht und die Abschlussarbeit bestanden.",
             "Zertifikat über den Abschluss liegt vor.",
             "Das Programm läuft 9 Monate mit etwa 4 Stunden pro Woche; das passt zu meinen 5 freien Stunden pro Woche.",
             "Ohne das Programm wird intern niemand Teamleitung.", "2027-11-14"),
        goal("month", "Bis 30.11.2026 habe ich meine Bewerbung für das Führungskräfteprogramm eingereicht.",
             "Anschreiben fertig und das Gespräch mit meiner Vorgesetzten geführt, Bewerbung abgeschickt.",
             "Bewerbung ist abgeschickt, Eingangsbestätigung liegt vor.",
             "Die Frist ist der 30.11.; ich brauche etwa 4 Stunden, verteilt auf zwei Abende.",
             "Der erste konkrete Schritt, statt zu warten, bis ich mich bereit fühle.", "2026-11-30"),
    ],
}

TURNS = [
    {"question": "Was stört dich in deinem Beruf gerade am meisten?", "answer": "Ich bin seit sechs Jahren Projektmanagerin und trete auf der Stelle. Ich würde gern ein Team führen, aber ich bewerbe mich nie."},
    {"question": "Woran ist es bisher gescheitert?", "answer": "Ich warte immer, bis ich mich wirklich bereit fühle. Ich glaube, ich muss erst alles können, bevor ich mich bewerben darf."},
    {"question": "Was ist dir dabei am wichtigsten?", "answer": "Selbstbestimmung, und dass ich Zeit für meine Tochter Lina habe. Gesund bleiben will ich auch, ich bewege mich zu wenig."},
    {"question": "Wo stehst du in drei Jahren?", "answer": "Ich bin Teamleiterin, laufe zweimal die Woche an der Elbe, habe ein Polster von sechs Monatsgehältern und abends wirklich Zeit für Lina."},
    {"question": "Wie stark spürst du das, von eins bis zehn?", "answer": "Neun."},
    {"question": "Wie viel Zeit hast du pro Woche dafür?", "answer": "Etwa fünf Stunden abends, wenn Lina schläft."},
    {"question": "Was ist der erste Schritt diesen Monat?", "answer": "Die Bewerbung für das Führungskräfteprogramm, die Frist ist Ende November."},
]

TODOS = {
    "karriere": ["Einen Absatz der Bewerbung schreiben", "Ein Kapitel im Führungsbuch lesen"],
    "gesundheit": ["Eine Runde laufen oder spazieren gehen", "Bis 23 Uhr im Bett sein"],
    "finanzen": ["Ausgaben des Tages notieren", "Keine Spontankäufe über 30 €"],
    "beziehungen": ["Handyfreie Zeit mit Lina", "Einer Freundin eine Nachricht schreiben"],
    "persoenlichkeit": ["Drei Dinge notieren, die heute gut liefen", "Zehn Seiten im Roman lesen"],
}

print("reset", call("DELETE", "/v1/me")[0])
print("name", call("POST", "/v1/name", {"name": "Mia"})[0])
s, r = call("POST", "/v1/commit", {"area": "karriere", "draft": DRAFT, "turns": TURNS})
assert s == 200, (s, r)
# The commit lets the coach propose to-dos in the background; wait for them, then replace them with the demo set.
for _ in range(30):
    kpis = call("GET", "/v1/state")[1].get("kpis") or []
    if kpis:
        break
    time.sleep(2)
for k in kpis:
    call("POST", "/v1/kpis/remove", {"id": k["id"]})
for area, names in TODOS.items():
    for name in names:
        s, r = call("POST", "/v1/kpis/add", {"area": area, "name": name})
        assert s == 200, (s, r)
s, board = call("POST", "/v1/vision/board", {"fresh": True})
print("board", s, board.get("caption"))
s, today = call("POST", "/v1/today/list", {"fresh": True})
print("list", s)
for i in today.get("items", []):
    print(f"  [{i['quadrant']}] {i['title']}")
state = call("GET", "/v1/state")[1]
for k in state.get("kpis", []):
    print(f"  {k.get('area')}: {k['name']}")
