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
                    Page {
                        ContractBody(draft: draft)
                            .id(draft.vision) // a revised draft enters like a fresh page
                            .transition(.opacity)
                        signing(progress.area, draft).appear(5)
                    }
                    .animation(Motion.smooth, value: busy)
                    .animation(Motion.smooth, value: draft.vision)
                }
                .scrollIndicators(.hidden)
            }
        }
        .confirmationDialog("Der Entwurf und deine Antworten werden verworfen.", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Neu beginnen", role: .destructive) { withAnimation(Motion.smooth) { model.progress = nil } }
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
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Was stimmt noch nicht?").font(.sectionTitle)
                    TextField("Zum Beispiel: Das Jahresziel ist zu groß.", text: $feedback, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.bodyText)
                        .padding(Space.m)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.line))
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
                .padding(.horizontal, Space.page)
                .padding(.top, Space.section)
            }
            .presentationDetents([.medium])
            .presentationCornerRadius(Radius.card + 6)
        }
    }

    /// Signature block: the commitment note, the hold gesture and the quieter ways out.
    @ViewBuilder
    private func signing(_ area: String, _ draft: Draft) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if busy {
                CoachThinking(text: "Der Coach überarbeitet")
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow("Unterschrift")
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.name ?? "")
                            .font(.quote)
                        Spacer()
                        Text(Date.now.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "de_DE"))))
                            .font(.label)
                            .foregroundStyle(Ink.muted)
                    }
                    Rectangle().fill(Ink.line).frame(height: 1)
                    Text("Mit deiner Unterschrift sind diese Ziele 30 Tage fest. Ändern geht danach nur mit Begründung und 48 Stunden Bedenkzeit.")
                        .font(.note)
                        .foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, Space.xs)
                if let error { ErrorNote(text: error).transition(.opacity) }
                HoldToSign { Task { await sign(area, draft) } }
                Button("Passt noch nicht ganz") { showTalk = true }
                    .buttonStyle(PressStyle(filled: false))
                Button("Erstgespräch neu beginnen") { confirmRestart = true }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
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
            withAnimation(Motion.smooth) { model.progress?.draft = draft }
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
        VStack(alignment: .leading, spacing: Space.section) {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow("Dein Zielvertrag")
                Text(draft.vision)
                    .font(.display(26))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                ValueChips(values: draft.values).padding(.top, Space.xxs)
            }
            .appear(0)
            VStack(alignment: .leading, spacing: Space.xs) {
                Eyebrow("Dein Warum")
                HStack(alignment: .top, spacing: Space.m) {
                    Capsule().fill(Ink.dawn.opacity(0.6)).frame(width: 2)
                    Text(draft.why)
                        .font(.quote)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .appear(1)
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Deine Ziele").font(.sectionTitle)
                ForEach(Array(draft.goals.enumerated()), id: \.element.horizon) { index, goal in
                    GoalCard(goal: goal, expanded: goal.horizon == "month").appear(index + 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .live: return Date().timeIntervalSince(live.lastAgentAudio) < 0.6 ? "Clara spricht" : "Clara hört zu"
        case .finished: return "Gespräch beendet"
        default: return "Verbinde …"
        }
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                // The conversation: a compact strip at the top.
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "waveform")
                            .foregroundStyle(live.state == .live ? Ink.dawn : Ink.muted)
                            .symbolEffect(.variableColor.iterative, isActive: live.state == .live)
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            Text(status)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Ink.muted)
                                .contentTransition(.opacity)
                                .animation(Motion.smooth, value: status)
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
                            .font(.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    } else {
                        Text(live.agentText.isEmpty ? "Sag deinem Coach, was noch nicht passt. Der Vertrag bleibt unten sichtbar." : live.agentText)
                            .font(.display(20))
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(live.agentText)
                            .transition(.opacity)
                        if !live.callerText.isEmpty {
                            Text(live.callerText)
                                .font(.note)
                                .foregroundStyle(Ink.muted)
                                .lineLimit(2)
                                .transition(.opacity)
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
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.m)
                .animation(Motion.smooth, value: live.agentText)
                .animation(Motion.smooth, value: failure)
                Rectangle().fill(Ink.line).frame(height: 1)
                // The contract being talked about.
                ScrollView {
                    ContractBody(draft: draft)
                        .padding(.horizontal, Space.page)
                        .padding(.vertical, Space.section)
                }
                .scrollIndicators(.hidden)
                Rectangle().fill(Ink.line).frame(height: 1)
                VStack(spacing: Space.xs) {
                    Button("Fertig, Vertrag anpassen") { finish() }
                        .buttonStyle(PressStyle())
                        .disabled(turns.isEmpty && LiveVoice.pair(live.entries).isEmpty)
                    Button("Lieber tippen") { close(.type) }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, Space.page)
                .padding(.top, Space.s)
            }
            .padding(.vertical, Space.s)
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
            withAnimation(Motion.smooth) { crisis = true }
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
            HStack(spacing: Space.xs) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.label)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Ink.dawn.opacity(0.45)))
                        .foregroundStyle(Ink.dawn)
                }
            }
        }
        .scrollClipDisabled()
    }
}

struct GoalCard: View {
    let goal: Goal
    @State var expanded = false

    var body: some View {
        Card {
            Button {
                withAnimation(Motion.snappy) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Eyebrow(goal.horizonLabel)
                        Spacer()
                        if goal.lockedUntil != nil {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(Ink.muted)
                        }
                        Text("bis \(germanDate(goal.deadline))").font(.label).foregroundStyle(Ink.muted)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.muted)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    Text(goal.title)
                        .font(.system(.body, design: .serif).weight(.medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Details einklappen" : "Details anzeigen")
            if expanded {
                VStack(alignment: .leading, spacing: Space.s) {
                    Rectangle().fill(Ink.line).frame(height: 1)
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
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).font(.label).foregroundStyle(Ink.muted)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Press and hold for 1.5 s; releasing early cancels. The deliberate gesture is part of the commitment.
struct HoldToSign: View {
    var action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    /** The hold completed: the bar stays full and shows a check. */
    @State private var signed = false
    private let duration = 1.5
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.control, style: .continuous) }

    var body: some View {
        ZStack {
            shape.fill(Ink.surface)
            // Paper label on the empty track, night label on the dawn fill; the fill reveals one over the other.
            label.foregroundStyle(Ink.paper)
            ZStack {
                shape.fill(Ink.dawn)
                label.foregroundStyle(Ink.night)
            }
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * progress)
                }
            }
        }
        .frame(height: 58)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.dawn.opacity(signed ? 0 : 0.5)))
        .scaleEffect(signed ? 1 : holding ? 0.98 : 1)
        .animation(Motion.snappy, value: holding)
        .animation(Motion.snappy, value: signed)
        .sensoryFeedback(.impact(weight: .medium), trigger: signed) { _, now in now }
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 60) {
            holding = false
            withAnimation(Motion.snappy) { progress = 1 }
            signed = true
            action()
        } onPressingChanged: { pressing in
            holding = pressing
            if pressing {
                signed = false
                Haptics.tap()
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else if !signed {
                withAnimation(Motion.smooth) { progress = 0 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zielvertrag unterschreiben")
        .accessibilityHint("Doppeltippen und halten")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var label: some View {
        Label(signed ? "Unterschrieben" : holding ? "Weiter halten …" : "Halten, um zu unterschreiben",
              systemImage: signed ? "checkmark" : "signature")
            .font(.system(.headline, design: .rounded))
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity)
    }
}
