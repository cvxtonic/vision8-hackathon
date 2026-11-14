import SwiftUI

/// A live talk with the coach that runs in the background of the app: it lives in the app model, so the person
/// can switch tabs, read their list or vision and change things while talking.
@MainActor
@Observable
final class CoachCall {
    let live = LiveVoice()
    private(set) var active = false
    private(set) var focus = "help"
    private(set) var topic: String?
    /** Turns of this talk, across reconnects. */
    private(set) var turns: [Turn] = []
    var error: String?
    /** The talk is over and the coach sums it up (shown in a sheet). */
    var ending = false
    var debrief: Debrief?
    /** The coach ended with the crisis line: no summary on top of that. */
    var crisis = false
    /** The expanded view of the running talk. */
    var expanded = false

    private let minTurns = 3

    var failure: String? {
        if let error { return error }
        if case .failed(let message) = live.state { return message }
        return nil
    }

    var status: String {
        switch live.state {
        case .live: return Date().timeIntervalSince(live.lastAgentAudio) < 0.6 ? "Der Coach spricht" : "Der Coach hört zu"
        case .finished: return "Gespräch beendet"
        case .failed: return "Verbindung unterbrochen"
        default: return "Verbinde …"
        }
    }

    /// Starts a talk; a running one is ended first.
    func start(_ api: API, focus: String, topic: String? = nil) async {
        if active { stopQuietly() }
        self.focus = focus
        self.topic = topic
        turns = []
        error = nil
        debrief = nil
        crisis = false
        ending = false
        active = true
        await connect(api)
    }

    func connect(_ api: API) async {
        error = nil
        guard await LiveVoice.authorize() else {
            error = "Das Mikrofon ist für Vision 8 nicht freigegeben. Du kannst das in den iOS-Einstellungen ändern."
            return
        }
        do {
            let session = try await api.followupSession(focus: focus, topic: topic)
            guard active, !ending, !crisis else { return }
            live.connect(url: session.url, token: session.token, callSid: session.callSid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stops the stream and keeps what was said so far.
    func bank() {
        live.stop()
        turns = Array((turns + live.takeTurns()).suffix(60))
    }

    /// The server closed the talk, or the person ended it: sum it up when there is enough to sum up.
    func end(_ api: API, refresh: @escaping () async -> Void) {
        guard active, !ending, !crisis else { return }
        let crisisLine = live.entries.suffix(4).contains { $0.speaker == "agent" && $0.text.localizedCaseInsensitiveContains("Telefonseelsorge") }
        bank()
        expanded = false
        if crisisLine {
            crisis = true
            return
        }
        guard turns.count >= minTurns else {
            active = false
            return
        }
        ending = true
        Task {
            await summarize(api)
            await refresh() // the worker updates the file and the last talk afterwards
        }
    }

    func summarize(_ api: API) async {
        error = nil
        do {
            let result = try await api.debrief(turns: turns)
            Haptics.success()
            debrief = result
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Closes the summary or the crisis note.
    func close() {
        active = false
        ending = false
        crisis = false
        debrief = nil
        error = nil
    }

    private func stopQuietly() {
        live.stop()
        close()
    }
}

/// The running talk as a bar above the tab bar. Tap to open the full captions.
struct CoachBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let call = model.call
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(call.live.state == .live ? Ink.dawn : Ink.muted)
                .symbolEffect(.variableColor.iterative, isActive: call.live.state == .live)
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(call.failure == nil ? call.status : "Verbindung unterbrochen")
                        .font(.label)
                        .foregroundStyle(Ink.muted)
                }
                Text(call.live.agentText.isEmpty ? "Dein Coach ist gleich da." : call.live.agentText)
                    .font(.system(.subheadline, design: .rounded))
                    .lineLimit(2)
                    .foregroundStyle(Ink.paper)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Haptics.tap()
                call.end(model.api) { await model.refresh() }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.headline)
                    .foregroundStyle(Ink.night)
                    .frame(width: 44, height: 44)
                    .background(Ink.drift, in: Circle())
            }
            .accessibilityLabel("Gespräch beenden")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Ink.dawn.opacity(0.4)))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .contentShape(Rectangle())
        .onTapGesture { call.expanded = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Öffnet das Gespräch")
    }
}

/// The expanded talk: captions in a sheet the app stays usable behind.
struct CoachSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let call = model.call
        Screen {
            VStack(alignment: .leading, spacing: 12) {
                LiveCaptions(live: call.live)
                if let failure = call.failure {
                    ErrorNote(text: failure)
                    Button("Noch einmal verbinden") {
                        call.bank()
                        Task { await call.connect(model.api) }
                    }
                    .buttonStyle(PressStyle(filled: false))
                }
                Button("Gespräch beenden") { call.end(model.api) { await model.refresh() } }
                    .buttonStyle(PressStyle())
            }
            .padding(24)
        }
    }
}

/// After the talk: what the coach takes away, or the crisis note.
struct CoachSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let call = model.call
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                if call.crisis {
                    Text("Danke, dass du so offen warst.").font(.display(26))
                    Text("Dein Coach hat das Gespräch beendet. Die Telefonseelsorge erreichst du kostenlos und rund um die Uhr unter 0800 111 0 111, im Notfall die 112.")
                        .font(.system(.body, design: .rounded))
                    if let tel = URL(string: "tel:08001110111") {
                        Link("Telefonseelsorge anrufen", destination: tel).buttonStyle(PressStyle())
                    }
                } else if let debrief = call.debrief {
                    Eyebrow("Aus eurem Gespräch")
                    Text(debrief.summary).font(.display(22)).fixedSize(horizontal: false, vertical: true)
                    if !debrief.insight.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Capsule().fill(Ink.dawn).frame(width: 3)
                            Text(debrief.insight).font(.quote).fixedSize(horizontal: false, vertical: true)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let error = call.error {
                    Text("Danke für das Gespräch.").font(.display(26))
                    ErrorNote(text: error)
                    Button("Noch einmal versuchen") { Task { await call.summarize(model.api) } }.buttonStyle(PressStyle(filled: false))
                } else {
                    Text("Danke für das Gespräch.").font(.display(26))
                    CoachThinking(text: "Dein Coach hält das Wichtigste fest.")
                }
                Button(call.debrief == nil && !call.crisis && call.error == nil ? "Im Hintergrund weiter" : "Fertig") { call.close() }
                    .buttonStyle(PressStyle(filled: call.debrief != nil || call.crisis))
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}
