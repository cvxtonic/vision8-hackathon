import Foundation

struct Turn: Codable, Equatable {
    var question: String
    var answer: String
}

struct Question: Codable, Equatable {
    var done: Bool
    var phase: String
    var mirror: String
    var question: String
    var input: String
    var options: [String]
    var hint: String?
}

struct Goal: Codable, Identifiable, Equatable {
    var id: String?
    var horizon: String
    var title: String
    var specific: String
    var measurable: String
    var achievable: String
    var relevant: String
    var deadline: String
    var lockedUntil: String?

    var key: String { id ?? horizon }

    var horizonLabel: String {
        switch horizon {
        case "10y": return "10 Jahre"
        case "3y": return "3 Jahre"
        case "1y": return "12 Monate"
        default: return "Dieser Monat"
        }
    }
}

struct Draft: Codable, Equatable {
    var vision: String
    var why: String
    var values: [String]
    var goals: [Goal]
}

struct Profile: Codable, Equatable {
    var vision: String
    var why: String
    var values: [String]
}

struct PlanItem: Codable, Equatable {
    var task: String
    var verdict: String
    var goal: String
    var note: String
}

struct PlanCheck: Codable, Equatable {
    var items: [PlanItem]
    var score: Int
    var reminder: String
    var question: String
    var suggestion: String?
}

struct DayTask: Codable, Equatable {
    var text: String
    var done: Bool
}

struct DayPlan: Codable, Equatable {
    var tasks: [DayTask]
    var check: PlanCheck
}

struct Reflection: Codable, Equatable {
    var text: String
    var reply: String
    var via: String? // "call" when it came from the evening phone call
    var cause: String?
    var fix: String?
}

struct Today: Codable, Equatable {
    var day: String
    var plan: DayPlan?
    var reflection: Reflection?
}

struct PendingChange: Codable, Equatable {
    var id: String
    var goal_id: String
    var proposed: String
    var coach_reply: String
    var effective_at: String

    var effectiveDate: Date { ISO8601DateFormatter.fractional.date(from: effective_at) ?? .distantFuture }
}

struct Contact: Codable, Equatable {
    var phone: String?
    var consent: Bool
    var callHour: Int
    var callMinute: Int?
    /** ISO weekdays, 1 = Monday ... 7 = Sunday. */
    var days: [Int]?
}

struct AppState: Codable, Equatable {
    var committed: Bool
    var profile: Profile?
    var goals: [Goal]?
    var today: Today?
    var streak: Int?
    var carry: String?
    var name: String?
    var pendingChange: PendingChange?
    var contact: Contact?
    /** The coach's file on the person (plain text, fixed section headings); nil until it is written. */
    var file: String?
    var fileUpdatedAt: String?
    var lastTalk: LastTalk?
    var week: WeekPlan?
    var kpis: [Kpi]?
    var kpiToday: [String: Double]?
    var area: String?
    var dayScore: Int?
    var list: [ListItem]?
    var coachStreak: CoachStreak?
    var board: Board?
    var weekScore: WeekSummary?
}

struct Kpi: Codable, Equatable, Identifiable {
    var id: String
    /** Life area the KPI belongs to (Area ids); older KPIs have none and belong to the main area. */
    var area: String?
    var name: String
    var unit: String
    var target: Double
    /** "atLeast", "atMost" or "check" (done yes/no). */
    var direction: String
    /** "manual", "steps" or "weight" (the last two come from the Health app). */
    var source: String

    func met(_ value: Double) -> Bool {
        switch direction {
        case "check": return value >= 1
        case "atMost": return value <= target
        default: return value >= target
        }
    }
}

struct Stats: Decodable, Equatable {
    struct Day: Decodable, Equatable { var day: String; var score: Int }
    var since: String
    var daysWith: Int
    var goodDays: Int
    var streak: Int
    var trend: [Day]
    var todosDone: Int
    var perArea: [String: Int]
    var weekTodosDone: Int
    var weekTodosTotal: Int
    var plans: Int
    var evenings: Int
    var talks: Int
    var requests: Int
}

/** One entry of the day's list. quadrant: "now" (important and urgent), "next" (important), "later" (urgent). source: "coach", "habit", "own". */
struct ListItem: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var why: String
    var quadrant: String
    var source: String
    var done: Bool
    /** For area to-dos: the to-do it ranks, and its score points for today (set by the coach). */
    var kpiId: String?
    var points: Int?
}

/** Days in a row the person answered the coach; `today`: already counted today. */
struct CoachStreak: Codable, Equatable {
    var days: Int
    var today: Bool
    var jokerUsed: Bool
}

struct DayList: Decodable { var items: [ListItem]; var advice: String? }

struct Board: Codable, Equatable {
    var image: String
    var caption: String
}

struct WeekSummary: Codable, Equatable {
    struct Day: Codable, Equatable { var day: String; var score: Int }
    var average: Int
    var days: [Day]
    /** Good days (70+) in a row; one missed day per week is forgiven. */
    var streak: Int
    var jokerUsed: Bool
}

struct WeekItem: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var why: String
    var goal: String
    var minutes: Int
    var day: String
    var done: Bool
}

struct WeekPlan: Codable, Equatable {
    var week: String
    var focus: String
    var items: [WeekItem]
}

/// What the coach took away from the last follow-up conversation.
struct LastTalk: Codable, Equatable {
    var summary: String
    var insight: String?
    var at: String?
}

/// The coach's summary right after a follow-up conversation.
struct Debrief: Decodable, Equatable {
    var summary: String
    var insight: String
}

/// A realtime interview opened by the worker; the app connects to `url` itself.
struct VoiceSession: Decodable {
    var url: URL
    var token: String
    var callSid: String
}

struct APIError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

struct API {
    static let base = URL(string: Secrets.apiBase)!
    let deviceId: String

    private struct Empty: Codable {}
    private struct Failure: Codable { var error: String }

    private func send<Body: Encodable, Out: Decodable>(_ method: String, _ path: String, _ body: Body?) async throws -> Out {
        var req = URLRequest(url: API.base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 120 // the contract draft takes up to ~40 s
        req.setValue(Secrets.appKey, forHTTPHeaderField: "x-v8-key")
        req.setValue(deviceId, forHTTPHeaderField: "x-device-id")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: "Keine Verbindung. Prüf dein Internet und versuch es noch einmal.")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw APIError(message: message ?? "Etwas ist schiefgelaufen. Versuch es gleich noch einmal.")
        }
        return try JSONDecoder().decode(Out.self, from: data)
    }

    private struct InterviewBody: Encodable { var area: String; var turns: [Turn]; var feedback: String?; var voice: Bool?; var previous: Draft? }
    private struct ReviseSessionBody: Encodable { var kind = "revise"; var draft: Draft }
    /** kind nil = "intake" (area and turns required); "followup" uses focus instead. */
    private struct VoiceSessionBody: Encodable { var kind: String?; var area: String?; var turns: [Turn]?; var focus: String?; var topic: String? }
    private struct CommitBody: Encodable { var area: String; var draft: Draft; var turns: [Turn] }
    private struct TurnsBody: Encodable { var turns: [Turn] }
    private struct PlanBody: Encodable { var tasks: [String] }
    private struct CheckBody: Encodable { var index: Int; var done: Bool }
    private struct ChangeBody: Encodable { var goalId: String; var proposed: String; var reason: String }
    private struct IdBody: Encodable { var id: String }
    private struct ContactBody: Encodable { var phone: String?; var callHour: Int; var callMinute: Int; var days: [Int] }
    private struct OK: Decodable { var ok: Bool }

    func state() async throws -> AppState { try await send("GET", "v1/state", Empty?.none) }

    func nextQuestion(area: String, turns: [Turn], voice: Bool) async throws -> Question {
        try await send("POST", "v1/interview/next", InterviewBody(area: area, turns: turns, voice: voice))
    }

    /// `previous` + `feedback` revise an existing draft: only what the person wants changed is changed.
    func draft(area: String, turns: [Turn], feedback: String?, previous: Draft? = nil) async throws -> Draft {
        try await send("POST", "v1/draft", InterviewBody(area: area, turns: turns, feedback: feedback, previous: previous))
    }

    /// A short live conversation about the drafted contract, before it is signed.
    func reviseSession(draft: Draft) async throws -> VoiceSession {
        try await send("POST", "v1/voice/session", ReviseSessionBody(draft: draft))
    }

    /// `turns`: the conversation so far, so the coach continues from there.
    private struct NameBody: Encodable { var name: String }

    func saveName(_ name: String) async throws {
        let _: OK = try await send("POST", "v1/name", NameBody(name: name))
    }

    func voiceSession(area: String, turns: [Turn]) async throws -> VoiceSession {
        try await send("POST", "v1/voice/session", VoiceSessionBody(area: area, turns: turns))
    }

    /// A follow-up conversation after signing. `focus`: "beliefs", "values" or "open".
    /// `topic`: the to-do to talk about, with focus "todo".
    func followupSession(focus: String, topic: String? = nil) async throws -> VoiceSession {
        try await send("POST", "v1/voice/session", VoiceSessionBody(kind: "followup", focus: focus, topic: topic))
    }

    /// `turns` (the interview transcript) start the coach's file on the person.
    func commit(area: String, draft: Draft, turns: [Turn]) async throws {
        let _: OK = try await send("POST", "v1/commit", CommitBody(area: area, draft: draft, turns: Array(turns.suffix(60))))
    }

    private struct FreshBody: Encodable { var fresh: Bool }
    private struct KpiLogBody: Encodable { var id: String; var value: Double }
    private struct KpiSet: Decodable { var kpis: [Kpi] }

    private struct TitleBody: Encodable { var title: String }
    private struct CheckItemBody: Encodable { var id: String; var done: Bool }

    func todayList(fresh: Bool = false) async throws -> DayList { try await send("POST", "v1/today/list", FreshBody(fresh: fresh)) }
    func addToday(_ title: String) async throws -> DayList { try await send("POST", "v1/today/add", TitleBody(title: title)) }
    func checkToday(id: String, done: Bool) async throws -> DayList { try await send("POST", "v1/today/check", CheckItemBody(id: id, done: done)) }
    func removeToday(id: String) async throws -> DayList { try await send("POST", "v1/today/remove", IdOnly(id: id)) }

    func stats() async throws -> Stats { try await send("GET", "v1/stats", Empty?.none) }

    /// The vision board image; `fresh` paints a new one.
    func board(fresh: Bool = false) async throws -> Board {
        var req = try await send("POST", "v1/vision/board", FreshBody(fresh: fresh)) as Board
        req.caption = req.caption.trimmingCharacters(in: .whitespaces)
        return req
    }

    func setupKpis(fresh: Bool = false) async throws -> [Kpi] {
        let result: KpiSet = try await send("POST", "v1/kpis/setup", FreshBody(fresh: fresh))
        return result.kpis
    }

    private struct AddKpiBody: Encodable { var area: String?; var name: String }
    private struct AddedKpi: Decodable { var area: String }
    private struct AreaBody: Encodable { var area: String }
    private struct IdOnly: Encodable { var id: String }

    /// Without an area, the coach files the to-do; returns the area it landed in.
    @discardableResult
    func addKpi(area: String?, name: String) async throws -> String {
        let added: AddedKpi = try await send("POST", "v1/kpis/add", AddKpiBody(area: area, name: name))
        return added.area
    }

    func suggestKpis(area: String) async throws {
        let _: KpiSet = try await send("POST", "v1/kpis/suggest", AreaBody(area: area))
    }

    func removeKpi(id: String) async throws {
        let _: KpiSet = try await send("POST", "v1/kpis/remove", IdOnly(id: id))
    }

    func logKpi(id: String, value: Double) async throws {
        let _: OK = try await send("POST", "v1/kpis/log", KpiLogBody(id: id, value: value))
    }
    private struct WeekCheckBody: Encodable { var id: String; var done: Bool }

    /// This week's to-dos; `fresh` replaces the open ones with a new set.
    func week(fresh: Bool = false) async throws -> WeekPlan {
        try await send("POST", "v1/week/plan", FreshBody(fresh: fresh))
    }

    func checkWeek(id: String, done: Bool) async throws -> WeekPlan {
        try await send("POST", "v1/week/check", WeekCheckBody(id: id, done: done))
    }

    func debrief(turns: [Turn]) async throws -> Debrief {
        try await send("POST", "v1/voice/debrief", TurnsBody(turns: Array(turns.suffix(60))))
    }

    func plan(tasks: [String]) async throws -> DayPlan { try await send("POST", "v1/day/plan", PlanBody(tasks: tasks)) }

    func check(index: Int, done: Bool) async throws -> DayPlan { try await send("POST", "v1/day/check", CheckBody(index: index, done: done)) }

    struct CauseEntry: Encodable { var index: Int; var cause: String }
    private struct ReflectBody: Encodable { var text: String; var causes: [CauseEntry] }

    func reflect(text: String, causes: [CauseEntry]) async throws -> Reflection {
        try await send("POST", "v1/day/reflect", ReflectBody(text: text, causes: causes))
    }

    func requestChange(goalId: String, proposed: String, reason: String) async throws {
        let _: PendingReply = try await send("POST", "v1/goals/change", ChangeBody(goalId: goalId, proposed: proposed, reason: reason))
    }

    private struct PendingReply: Decodable { var id: String }

    func resolveChange(id: String, confirm: Bool) async throws {
        let _: OK = try await send("POST", "v1/goals/change/\(confirm ? "confirm" : "withdraw")", IdBody(id: id))
    }

    func saveContact(phone: String?, callHour: Int, callMinute: Int, days: [Int]) async throws {
        let _: OK = try await send("POST", "v1/contact", ContactBody(phone: phone, callHour: callHour, callMinute: callMinute, days: days))
    }

    func callNow() async throws {
        let _: OK = try await send("POST", "v1/call/now", Empty?.none)
    }

    func deleteEverything() async throws {
        let _: OK = try await send("DELETE", "v1/me", Empty?.none)
    }
}
