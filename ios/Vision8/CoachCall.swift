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
        case .live: return Date().timeIntervalSince(live.lastAgentAudio) < 0.6 ? "Clara spricht" : "Clara hört zu"
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
        HStack(spacing: Space.s) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(call.live.state == .live ? Ink.dawn : Ink.muted)
                .symbolEffect(.variableColor.iterative, isActive: call.live.state == .live)
                .frame(width: 28)
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
                    .contentTransition(.opacity)
                    .animation(Motion.smooth, value: call.live.agentText)
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
            .buttonStyle(OrbButtonPress())
            .accessibilityLabel("Gespräch beenden")
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .padding(.vertical, Space.xs)
        .modifier(BarSurface())
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture { call.expanded = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Öffnet das Gespräch")
    }
}

/// Liquid Glass on iOS 26, the solid surface card before.
private struct BarSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        } else {
            content
                .background(Ink.surface, in: shape)
                .overlay(shape.strokeBorder(Ink.line))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
    }
}

/// Round control: scales down while pressed.
private struct OrbButtonPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// The expanded talk: captions in a sheet the app stays usable behind.
struct CoachSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let call = model.call
        Screen {
            VStack(alignment: .leading, spacing: Space.s) {
                LiveCaptions(live: call.live)
                if let failure = call.failure {
                    Group {
                        ErrorNote(text: failure)
                        Button("Noch einmal verbinden") {
                            call.bank()
                            Task { await call.connect(model.api) }
                        }
                        .buttonStyle(PressStyle(filled: false))
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Button("Gespräch beenden") { call.end(model.api) { await model.refresh() } }
                    .buttonStyle(PressStyle())
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.page)
            .animation(Motion.smooth, value: call.failure)
        }
        .presentationDragIndicator(.visible)
    }
}

/// After the talk: what the coach takes away, or the crisis note.
struct CoachSummary: View {
    @Environment(AppModel.self) private var model

    /// Which of the four states is showing, so the change between them can be animated.
    private var stage: Int {
        let call = model.call
        if call.crisis { return 0 }
        if call.debrief != nil { return 1 }
        if call.error != nil { return 2 }
        return 3
    }

    var body: some View {
        let call = model.call
        Screen {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.s) {
                    if call.crisis {
                        Text("Danke, dass du so offen warst.").font(.pageTitle).fixedSize(horizontal: false, vertical: true)
                        Text("Dein Coach hat das Gespräch beendet. Die Telefonseelsorge erreichst du kostenlos und rund um die Uhr unter 0800 111 0 111, im Notfall die 112.")
                            .font(.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let debrief = call.debrief {
                        Eyebrow("Aus eurem Gespräch")
                        Text(debrief.summary).font(.sectionTitle).fixedSize(horizontal: false, vertical: true)
                        if !debrief.insight.isEmpty {
                            HStack(alignment: .top, spacing: Space.s) {
                                Capsule().fill(Ink.dawn).frame(width: 3)
                                Text(debrief.insight).font(.quote).fixedSize(horizontal: false, vertical: true)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Space.xs)
                        }
                    } else if let error = call.error {
                        Text("Danke für das Gespräch.").font(.pageTitle)
                        ErrorNote(text: error)
                    } else {
                        Text("Danke für das Gespräch.").font(.pageTitle)
                        CoachThinking(text: "Dein Coach hält das Wichtigste fest.")
                    }
                }
                .id(stage)
                .transition(.opacity)
                Spacer(minLength: 0)
                VStack(spacing: Space.s) {
                    if call.crisis, let tel = URL(string: "tel:08001110111") {
                        Link("Telefonseelsorge anrufen", destination: tel).buttonStyle(PressStyle())
                    }
                    if !call.crisis, call.debrief == nil, call.error != nil {
                        Button("Noch einmal versuchen") { Task { await call.summarize(model.api) } }.buttonStyle(PressStyle(filled: false))
                    }
                    // The crisis line is the one filled button there; "Fertig" stays quiet next to it.
                    Button(call.debrief == nil && !call.crisis && call.error == nil ? "Im Hintergrund weiter" : "Fertig") { call.close() }
                        .buttonStyle(PressStyle(filled: call.debrief != nil))
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.section)
            .padding(.bottom, Space.page)
            .animation(Motion.smooth, value: stage)
        }
        .presentationDragIndicator(.visible)
    }
}
