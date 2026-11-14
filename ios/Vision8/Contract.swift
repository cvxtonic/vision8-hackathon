import SwiftUI

/// The drafted contract: review, sharpen once more, then sign by holding. Signing locks the goals.
struct ContractView: View {
    @Environment(AppModel.self) private var model
    @State private var feedback = ""
    @State private var showFeedback = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmRestart = false
    /** The live conversation about what does not fit yet. */
    @State private var showTalk = false

    var body: some View {
        Screen {
            if let progress = model.progress, let draft = progress.draft {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ContractBody(draft: draft)
                        if busy {
                            CoachThinking(text: "Der Coach überarbeitet").padding(.vertical, 8)
                        } else {
                            if let error { ErrorNote(text: error) }
                            Text("Mit deiner Unterschrift sind diese Ziele 30 Tage fest. Ändern geht danach nur mit Begründung und 48 Stunden Bedenkzeit.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Ink.muted)
                            HoldToSign { Task { await sign(progress.area, draft) } }
                            Button("Passt noch nicht ganz") { showTalk = true }
                                .buttonStyle(PressStyle(filled: false))
                            Button("Erstgespräch neu beginnen") { confirmRestart = true }
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Ink.muted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .confirmationDialog("Der Entwurf und deine Antworten werden verworfen.", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Neu beginnen", role: .destructive) { withAnimation { model.progress = nil } }
            Button("Abbrechen", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showTalk) {
            if let draft = model.progress?.draft {
                ReviseTalkView(draft: draft) { outcome in
                    showTalk = false
                    switch outcome {
                    case .changes(let said):
                        Task { await revise(said) }
                    case .type:
                        showFeedback = true
                    case .none:
                        break
                    }
                }
            }
        }
        .sheet(isPresented: $showFeedback) {
            Screen {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Was stimmt noch nicht?").font(.display(24))
                    TextField("Zum Beispiel: Das Jahresziel ist zu groß.", text: $feedback, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(14)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button("Überarbeiten lassen") {
                        showFeedback = false
                        let said = feedback
                        feedback = ""
                        Task { await revise(said) }
                    }
                    .buttonStyle(PressStyle())
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
                    Spacer()
                }
                .padding(24)
            }
            .presentationDetents([.medium])
        }
    }

    /// `said`: what the person typed, or the transcript of the talk with the coach about the draft.
    private func revise(_ said: String) async {
        guard let progress = model.progress, let previous = progress.draft else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let draft = try await model.api.draft(area: progress.area, turns: progress.turns, feedback: String(said.prefix(7500)), previous: previous)
            guard model.progress?.run == progress.run else { return }
            Haptics.success()
            withAnimation { model.progress?.draft = draft }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sign(_ area: String, _ draft: Draft) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.api.commit(area: area, draft: draft, turns: model.progress?.turns ?? [])
            Haptics.success()
            await model.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Vision, why, values and goals of a draft: shown for signing and kept in view while talking about it.
struct ContractBody: View {
    let draft: Draft

    var body: some View {
        Eyebrow("Dein Zielvertrag")
        Text(draft.vision).font(.display(24)).lineSpacing(3)
        ValueChips(values: draft.values)
        Card {
            Eyebrow("Dein Warum")
            Text(draft.why).font(.quote)
        }
        ForEach(draft.goals, id: \.horizon) { goal in
            GoalCard(goal: goal, expanded: goal.horizon == "month")
        }
    }
}

/// A live conversation with the coach about what does not fit in the draft. The draft stays on screen
/// the whole time, so the person can point at what they mean.
struct ReviseTalkView: View {
    enum Outcome { case changes(String), type, none }

    let draft: Draft
    var done: (Outcome) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var model
    @State private var live = LiveVoice()
    /** Turns of this conversation, across reconnects. */
    @State private var turns: [Turn] = []
    @State private var error: String?
    @State private var crisis = false
    @State private var closed = false

    private var failure: String? {
        if let error { return error }
        if case .failed(let message) = live.state { return message }
        return nil
    }

    private var status: String {
        switch live.state {
        case .live: return Date().timeIntervalSince(live.lastAgentAudio) < 0.6 ? "Der Coach spricht" : "Der Coach hört zu"
        case .finished: return "Gespräch beendet"
        default: return "Verbinde …"
        }
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                // The conversation: a compact strip at the top.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .foregroundStyle(live.state == .live ? Ink.dawn : Ink.muted)
                            .symbolEffect(.variableColor.iterative, isActive: live.state == .live)
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            Text(status).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(Ink.muted)
                        }
                        Spacer()
                        Button("Abbrechen") { close(.none) }
                            .font(.label)
                            .foregroundStyle(Ink.muted)
                            .frame(minHeight: 44)
                    }
                    .accessibilityElement(children: .contain)
                    if crisis {
                        Text("Dein Coach hat das Gespräch beendet. Die Telefonseelsorge erreichst du kostenlos und rund um die Uhr unter 0800 111 0 111, im Notfall die 112.")
                            .font(.system(.body, design: .rounded))
                    } else {
                        Text(live.agentText.isEmpty ? "Sag deinem Coach, was noch nicht passt. Der Vertrag bleibt unten sichtbar." : live.agentText)
                            .font(.display(20))
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(live.agentText)
                            .transition(.opacity)
                        if !live.callerText.isEmpty {
                            Text(live.callerText)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Ink.muted)
                                .lineLimit(2)
                        }
                    }
                    if let failure {
                        ErrorNote(text: failure)
                        Button("Noch einmal verbinden") {
                            bank()
                            Task { await start() }
                        }
                        .buttonStyle(PressStyle(filled: false))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
                .animation(.easeOut(duration: 0.3), value: live.agentText)
                Divider().overlay(Ink.line)
                // The contract being talked about.
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { ContractBody(draft: draft) }
                        .padding(24)
                }
                Divider().overlay(Ink.line)
                VStack(spacing: 8) {
                    Button("Fertig, Vertrag anpassen") { finish() }
                        .buttonStyle(PressStyle())
                        .disabled(turns.isEmpty && LiveVoice.pair(live.entries).isEmpty)
                    Button("Lieber tippen") { close(.type) }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .padding(.vertical, 12)
        }
        .task { await start() }
        .onDisappear { live.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { live.interrupt("Das Gespräch wurde unterbrochen, weil du die App verlassen hast.") }
        }
        .onChange(of: live.state) { _, state in
            if state == .finished { finish() }
            if case .failed = state { bank() }
        }
    }

    private func start() async {
        error = nil
        guard await LiveVoice.authorize() else {
            error = "Das Mikrofon ist für Vision 8 nicht freigegeben. Du kannst deine Änderungen tippen."
            return
        }
        do {
            let session = try await model.api.reviseSession(draft: draft)
            guard !Task.isCancelled, !closed, !crisis else { return }
            live.connect(url: session.url, token: session.token, callSid: session.callSid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stops the stream and keeps what was said so far.
    private func bank() {
        live.stop()
        turns = Array((turns + live.takeTurns()).suffix(60))
    }

    /// The coach ended the talk, or the person tapped "Fertig": hand what was said to the contract screen.
    private func finish() {
        guard !closed, !crisis else { return }
        let crisisLine = live.entries.suffix(4).contains { $0.speaker == "agent" && $0.text.localizedCaseInsensitiveContains("Telefonseelsorge") }
        bank()
        if crisisLine {
            withAnimation { crisis = true }
            return
        }
        guard !turns.isEmpty else { return close(.none) }
        close(.changes(turns.map { "Coach: \($0.question)\nPerson: \($0.answer)" }.joined(separator: "\n")))
    }

    private func close(_ outcome: Outcome) {
        guard !closed else { return }
        closed = true
        live.stop()
        done(outcome)
    }
}

struct ValueChips: View {
    let values: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Ink.dawn.opacity(0.16), in: Capsule())
                        .foregroundStyle(Ink.dawn)
                }
            }
        }
    }
}

struct GoalCard: View {
    let goal: Goal
    @State var expanded = false

    var body: some View {
        Card {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Eyebrow(goal.horizonLabel)
                        Spacer()
                        if goal.lockedUntil != nil {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(Ink.muted)
                        }
                        Text("bis \(germanDate(goal.deadline))").font(.label).foregroundStyle(Ink.muted)
                    }
                    Text(goal.title)
                        .font(.system(.body, design: .serif).weight(.medium))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Details einklappen" : "Details anzeigen")
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    detail("Konkret", goal.specific)
                    detail("Messbar", goal.measurable)
                    detail("Machbar", goal.achievable)
                    detail("Warum es zählt", goal.relevant)
                }
                .transition(.opacity)
            }
        }
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.label).foregroundStyle(Ink.muted)
            Text(text).font(.system(.subheadline, design: .rounded))
        }
    }
}

/// Press and hold for 1.5 s; releasing early cancels. The deliberate gesture is part of the commitment.
struct HoldToSign: View {
    var action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    private let duration = 1.5

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.dawn.opacity(0.25))
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Ink.dawn)
                    .frame(width: geo.size.width * progress)
            }
            Label(holding ? "Weiter halten …" : "Halten, um zu unterschreiben", systemImage: "signature")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Ink.night)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(holding ? 0.98 : 1)
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 60) {
            holding = false
            progress = 1
            action()
        } onPressingChanged: { pressing in
            holding = pressing
            if pressing {
                Haptics.tap()
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else if progress < 1 || !pressing {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zielvertrag unterschreiben")
        .accessibilityHint("Doppeltippen und halten")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
