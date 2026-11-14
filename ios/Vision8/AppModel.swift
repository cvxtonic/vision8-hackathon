import Foundation
import Observation
import UIKit

struct Area: Identifiable, Hashable {
    let id: String
    let title: String
    let hint: String
    let symbol: String

    static let all: [Area] = [
        Area(id: "karriere", title: "Karriere", hint: "Beruf, Aufstieg, eigenes Ding", symbol: "briefcase"),
        Area(id: "finanzen", title: "Finanzen", hint: "Einkommen, Rücklagen, Freiheit", symbol: "chart.line.uptrend.xyaxis"),
        Area(id: "beziehungen", title: "Beziehungen", hint: "Partnerschaft, Familie, Freunde", symbol: "heart"),
        Area(id: "gesundheit", title: "Gesundheit", hint: "Körper, Energie, Schlaf", symbol: "figure.run"),
        Area(id: "privatleben", title: "Privatleben", hint: "Zeit, Hobbys, Wohnen", symbol: "house"),
        Area(id: "persoenlichkeit", title: "Persönlichkeit", hint: "Wer ich sein will", symbol: "sparkles"),
    ]
}

/// Interview progress survives an app kill; the contract itself lives on the server.
struct InterviewProgress: Codable, Equatable {
    var area: String
    var turns: [Turn] = []
    var draft: Draft?
    /** true = spoken conversation, false = tapping/typing, nil = not chosen yet. */
    var voice: Bool?
    /** true = realtime conversation with the coach (LiveInterviewView). */
    var live: Bool?
    /** Tells a late network answer of a discarded interview from the current one. Not persisted. */
    var run = UUID()

    private enum CodingKeys: String, CodingKey { case area, turns, draft, voice, live }
}

@Observable
@MainActor
final class AppModel {
    enum Phase { case loading, onboarding, main }

    var phase: Phase = .loading
    var state: AppState?
    var progress: InterviewProgress? { didSet { persistProgress() } }
    var loadError: String?
    /** First name the coach uses; stored on the device and on the server. */
    var name: String? { didSet { defaults.set(name, forKey: "name") } }

    let api: API
    /** The live talk with the coach, running behind every tab. */
    let call = CoachCall()
    private let defaults = UserDefaults.standard

    init() {
        // ponytail: device id in UserDefaults is the only credential; move to Keychain + real sign-in before a public release.
        let id: String
        if let saved = defaults.string(forKey: "deviceId") {
            id = saved
        } else {
            id = UUID().uuidString
            defaults.set(id, forKey: "deviceId")
        }
        api = API(deviceId: id)
        name = defaults.string(forKey: "name")
        if let data = defaults.data(forKey: "progress") {
            progress = try? JSONDecoder().decode(InterviewProgress.self, from: data)
        }
    }

    private func persistProgress() {
        if let progress, let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: "progress")
        } else {
            defaults.removeObject(forKey: "progress")
        }
    }

    func refresh() async {
        do {
            let fresh = try await api.state()
            state = fresh
            loadError = nil
            phase = fresh.committed ? .main : .onboarding
            if fresh.committed { progress = nil }
            if let streak = fresh.coachStreak { await Notifications.streak(days: streak.days, savedToday: streak.today) }
            if name == nil, let known = fresh.name { name = known }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func reset() async throws {
        try await api.deleteEverything()
        Notifications.cancelAll()
        progress = nil
        name = nil
        state = nil
        phase = .onboarding
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
