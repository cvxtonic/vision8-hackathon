import SwiftUI

struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @State private var started = false

    var body: some View {
        Group {
            if let progress = model.progress {
                if progress.draft != nil {
                    ContractView()
                } else if progress.live == true {
                    LiveInterviewView()
                } else if progress.voice == nil, progress.turns.isEmpty {
                    ModeChooser()
                } else {
                    InterviewView()
                }
            } else if started, model.name == nil {
                NameStep()
            } else if started {
                AreaPicker()
            } else {
                Welcome { withAnimation(Motion.smooth) { started = true } }
            }
        }
        // Steps rise in a little and fade; the leaving step only fades, so two never collide.
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity))
        // Restarting the interview leads back to the very first screen.
        .onChange(of: model.progress == nil) { _, cleared in
            if cleared { started = false }
        }
    }
}

/// Small secondary text button used under the main actions of a step.
private struct QuietButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    var body: some View {
        Button(title, action: action)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Ink.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// Text field on a surface, with a soft dawn edge while focused.
private struct FieldBackground: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .padding(Space.m)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(focused ? Ink.dawn.opacity(0.55) : Ink.line)
            )
            .animation(Motion.snappy, value: focused)
    }
}

/// "The contract is being written": shared by the typed and the live interview.
private struct WritingNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Ich schreibe deinen Zielvertrag.").font(.display(28))
            Text("Aus unserem Gespräch entstehen deine Vision, dein Warum und deine Ziele – von drei Jahren bis zu diesem Monat. Das dauert etwa eine halbe Minute.")
                .font(.bodyText)
                .foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Welcome: View {
    var start: () -> Void

    private let steps: [(title: String, text: String)] = [
        ("Klare Ziele finden", "Dein Coach führt dich Frage für Frage zu Zielen, die konkret, messbar, machbar und dir wichtig sind – mit festem Datum."),
        ("Jeden Tag dranbleiben", "Er prüft deinen Tagesplan und erinnert dich an dein Warum. Abends legst du Rechenschaft ab, in der App oder am Telefon."),
        ("Hindernisse beseitigen", "Klappt etwas nicht, findet ihr die Ursache und räumt sie gemeinsam aus dem Weg."),
    ]

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: Space.s)
                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow("Vision 8 · Vision Aid")
                    Text("Ziele, die du\nwirklich erreichst.")
                        .font(.display(40))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Ein Coach, der dich an die Hand nimmt – vom ersten Ziel bis zum Tag, an dem du es geschafft hast.")
                        .font(.bodyText)
                        .foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appear(0)
                VStack(alignment: .leading, spacing: Space.page) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: Space.m) {
                            Text("\(index + 1)")
                                .font(.system(.headline, design: .serif))
                                .foregroundStyle(Ink.dawn)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(Ink.dawn.opacity(0.4)))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(step.title).font(.cardTitle)
                                Text(step.text)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Ink.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .appear(index + 1)
                    }
                }
                .padding(.top, Space.xl)
                Spacer(minLength: Space.page)
                VStack(spacing: Space.s) {
                    Button("Erstgespräch starten", action: start).buttonStyle(PressStyle())
                    Text("Etwa 5 Minuten, meist nur antippen. Deine Antworten bleiben in der EU.")
                        .font(.note)
                        .foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .appear(steps.count + 1)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.m)
        }
    }
}

/// The coach asks for a first name before anything else, so every later sentence is personal.
private struct NameStep: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        guard let first = cleaned.first, first.isLetter, cleaned.count <= 40 else { return false }
        return cleaned.allSatisfy { $0.isLetter || " '’-".contains($0) }
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow("Dein Coach")
                    Text("Schön, dass du da bist. Wie darf ich dich nennen?")
                        .font(.display(30))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appear(0)
                VStack(alignment: .leading, spacing: Space.s) {
                    TextField("Dein Vorname", text: $name)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .font(.system(.title3, design: .rounded))
                        .modifier(FieldBackground(focused: focused))
                        .onSubmit { if valid { Task { await save() } } }
                    if let error { ErrorNote(text: error).transition(.opacity) }
                }
                .padding(.top, Space.section)
                .appear(1)
                Spacer()
                Group {
                    if busy {
                        CoachThinking(text: "Einen Moment")
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    } else {
                        Button("Weiter") { Task { await save() } }
                            .buttonStyle(PressStyle())
                            .disabled(!valid)
                    }
                }
                .transition(.opacity)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.m)
            .animation(Motion.smooth, value: busy)
            .animation(Motion.smooth, value: error)
            .animation(Motion.snappy, value: valid)
        }
        .onAppear { focused = true }
    }

    private func save() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.api.saveName(cleaned)
            Haptics.tap()
            withAnimation(Motion.smooth) { model.name = cleaned }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AreaPicker: View {
    @Environment(AppModel.self) private var model
    /** The tapped area lights up briefly before the next step comes in. */
    @State private var selected: String?

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("Schritt 1")
                        Text(model.name.map { "\($0), was ist dir in deiner jetzigen Lage am wichtigsten?" } ?? "Was ist dir in deiner jetzigen Lage am wichtigsten?")
                            .font(.display(30))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Wir starten dort. Weitere Bereiche kannst du später dazunehmen.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Ink.muted)
                    }
                    .appear(0)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible())], spacing: Space.s) {
                        ForEach(Array(Area.all.enumerated()), id: \.element.id) { index, area in
                            Button { pick(area) } label: { card(area, on: selected == area.id) }
                                .buttonStyle(AreaPress())
                                .disabled(selected != nil && selected != area.id)
                                .accessibilityAddTraits(selected == area.id ? .isSelected : [])
                                .appear(index + 1)
                        }
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.m)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func card(_ area: Area, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Image(systemName: area.symbol)
                .font(.title2)
                .foregroundStyle(on ? Ink.night : Ink.dawn)
                .frame(width: 44, height: 44)
                .background(on ? Ink.dawn : Ink.dawn.opacity(0.12), in: Circle())
                .padding(.bottom, Space.xxs)
            Text(area.title).font(.cardTitle)
            Text(area.hint)
                .font(.note)
                .foregroundStyle(Ink.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(Space.m)
        .background(on ? Ink.dawn.opacity(0.10) : Ink.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(on ? Ink.dawn.opacity(0.7) : Ink.line, lineWidth: on ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func pick(_ area: Area) {
        guard selected == nil else { return }
        Haptics.tap()
        withAnimation(Motion.snappy) { selected = area.id }
        Task {
            // A short beat so the selection is seen before the step changes.
            try? await Task.sleep(for: .milliseconds(260))
            withAnimation(Motion.smooth) { model.progress = InterviewProgress(area: area.id) }
        }
    }
}

/// Area cards sink a little while pressed.
private struct AreaPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Speak with the coach or tap through: asked once, right after the life area.
private struct ModeChooser: View {
    @Environment(AppModel.self) private var model
    @State private var denied = false

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow("Schritt 2")
                    Text("Wie möchtest du mit deinem Coach sprechen?")
                        .font(.display(30))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Im Gespräch lernt dich dein Coach in etwa zehn Minuten kennen: Er fragt, du erzählst, er hört zu. Du kannst jederzeit zum Tippen wechseln.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if denied {
                        ErrorNote(text: "Das Mikrofon ist für Vision 8 nicht freigegeben. Du kannst das in den iOS-Einstellungen ändern oder jetzt tippen.")
                            .padding(.top, Space.xs)
                            .transition(.opacity)
                    }
                }
                .appear(0)
                Spacer()
                VStack(spacing: Space.s) {
                    Button {
                        Task {
                            if await LiveVoice.authorize() {
                                Haptics.tap()
                                withAnimation(Motion.smooth) { model.progress?.live = true }
                            } else {
                                withAnimation(Motion.smooth) { denied = true }
                            }
                        }
                    } label: {
                        Label("Im Gespräch", systemImage: "waveform")
                    }
                    .buttonStyle(PressStyle())
                    Button("Lieber antippen und tippen") {
                        withAnimation(Motion.smooth) { model.progress?.voice = false }
                    }
                    .buttonStyle(PressStyle(filled: false))
                    QuietButton("Zurück") { withAnimation(Motion.smooth) { model.progress = nil } }
                }
                .appear(1)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.m)
        }
    }
}

struct InterviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var question: Question?
    @State private var answer = ""
    @State private var busy = false
    /** On a choice question the person tapped "Etwas anderes" and types instead. */
    @State private var ownAnswer = false
    @State private var drafting = false
    @State private var error: String?
    @State private var confirmRestart = false
    @State private var voice = VoiceCoach()
    /** The running speak-then-listen round for the current question. */
    @State private var round: Task<Void, Never>?
    @State private var heardNothing = false
    @FocusState private var focused: Bool

    private var voiceOn: Bool { model.progress?.voice == true }

    private let phases = ["situation", "werte", "vision", "warum", "ziel"]
    private let phaseNames = ["Lage", "Werte", "Vision", "Warum", "Ziel"]

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                header.appear(0)
                if drafting {
                    Spacer()
                    VStack(alignment: .leading, spacing: Space.page) {
                        WritingNote()
                        CoachThinking(text: "Der Coach formuliert")
                    }
                    .transition(.opacity)
                    Spacer()
                } else if let question {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.m) {
                            if !question.mirror.isEmpty {
                                Text(question.mirror).font(.quote).foregroundStyle(Ink.muted)
                            }
                            Text(question.question)
                                .font(.display(26))
                                .fixedSize(horizontal: false, vertical: true)
                            if question.input == "text" || ownAnswer, let hint = question.hint, !hint.isEmpty {
                                Text(hint)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Ink.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Space.section)
                        .padding(.bottom, Space.m)
                        .id(question.question)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)), removal: .opacity))
                    }
                    .scrollDismissesKeyboard(.interactively)
                    Group {
                        if voiceOn {
                            voiceControls(for: question)
                        } else {
                            input(for: question)
                        }
                    }
                    .padding(.top, Space.xs)
                } else {
                    Spacer()
                    CoachThinking()
                    Spacer()
                }
                if let error {
                    VStack(spacing: Space.s) {
                        ErrorNote(text: error)
                        Button("Noch einmal versuchen") { Task { await next() } }
                            .buttonStyle(PressStyle(filled: false))
                    }
                    .padding(.top, Space.s)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.m)
            .animation(Motion.smooth, value: busy)
            .animation(Motion.smooth, value: ownAnswer)
            .animation(Motion.smooth, value: error)
        }
        .task { if question == nil { await next() } }
        .onDisappear {
            round?.cancel()
            voice.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app ends the round; the person continues with "Antwort sprechen".
            if phase != .active {
                round?.cancel()
                voice.stop()
            }
        }
        .confirmationDialog("Das Gespräch beginnt von vorn. Deine bisherigen Antworten gehen verloren.", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Von vorn beginnen", role: .destructive) {
                round?.cancel()
                voice.stop()
                withAnimation(Motion.smooth) { model.progress = nil }
            }
            Button("Weitermachen", role: .cancel) {}
        }
    }

    /// Speaks the question, listens, and submits what was understood.
    private func converse(_ q: Question, speakFirst: Bool = true) {
        round?.cancel()
        heardNothing = false
        guard voice.available else {
            // Permission withdrawn or recogniser offline: typing always works.
            voice.stop()
            error = "Die Spracherkennung ist gerade nicht verfügbar. Du kannst deine Antworten tippen."
            model.progress?.voice = false
            return
        }
        round = Task {
            if speakFirst {
                await voice.speak([q.mirror, q.question].filter { !$0.isEmpty }.joined(separator: " "))
            }
            guard !Task.isCancelled, voiceOn, question == q else { return }
            let heard = await voice.listen().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Task.isCancelled, voiceOn, question == q else { return }
            if heard.isEmpty {
                heardNothing = true
            } else {
                submit(heard)
            }
        }
    }

    @ViewBuilder
    private func voiceControls(for question: Question) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if busy {
                CoachThinking().frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                HStack(spacing: Space.xs) {
                    Image(systemName: voice.state == .listening ? "mic.fill" : voice.state == .speaking ? "speaker.wave.2.fill" : "mic.slash")
                        .font(.title3)
                        .foregroundStyle(voice.state == .idle ? Ink.muted : Ink.dawn)
                        .symbolEffect(.pulse, isActive: voice.state == .listening)
                        .contentTransition(.symbolEffect(.replace))
                    Text(voice.state == .listening ? "Ich höre zu …" : voice.state == .speaking ? "Clara spricht" : heardNothing ? "Ich habe nichts gehört." : "Bereit")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Ink.muted)
                }
                .accessibilityElement(children: .combine)
                .animation(Motion.smooth, value: voice.state)
                if !voice.transcript.isEmpty, voice.state == .listening {
                    Text(voice.transcript)
                        .font(.bodyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.m)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .transition(.opacity)
                }
                if voice.state == .listening {
                    Button("Fertig, weiter") { voice.finishListening() }.buttonStyle(PressStyle())
                } else if voice.state == .idle {
                    Button {
                        converse(question, speakFirst: false)
                    } label: {
                        Label("Antwort sprechen", systemImage: "mic")
                    }
                    .buttonStyle(PressStyle())
                }
                HStack {
                    Button("Frage wiederholen") { converse(question) }
                    Spacer()
                    Button("Lieber tippen") {
                        round?.cancel()
                        voice.stop()
                        withAnimation(Motion.smooth) { model.progress?.voice = false }
                    }
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Ink.muted)
                .frame(minHeight: 44)
            }
        }
    }

    private var header: some View {
        let current = phases.firstIndex(of: question?.phase ?? "situation") ?? 0
        return VStack(alignment: .trailing, spacing: Space.xxs) {
            HStack {
                if !voiceOn, !drafting {
                    Button {
                        Task {
                            guard await LiveVoice.authorize() else {
                                error = "Das Mikrofon ist für Vision 8 nicht freigegeben."
                                return
                            }
                            focused = false
                            round?.cancel()
                            voice.stop()
                            // The realtime coach continues from the turns so far.
                            withAnimation(Motion.smooth) { model.progress?.live = true }
                        }
                    } label: {
                        Label("Im Gespräch weiter", systemImage: "waveform")
                    }
                }
                Spacer()
                Button("Von vorn beginnen") { confirmRestart = true }
            }
            .font(.label)
            .foregroundStyle(Ink.muted)
            .frame(minHeight: 44)
            phaseBar(current)
        }
    }

    private func phaseBar(_ current: Int) -> some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(phaseNames.enumerated()), id: \.offset) { index, name in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Capsule().fill(index <= current ? Ink.dawn : Ink.line).frame(height: 4)
                    Text(name)
                        .font(.label)
                        .foregroundStyle(index == current ? Ink.paper : Ink.muted)
                }
            }
        }
        .animation(Motion.smooth, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Abschnitt \(phaseNames[current]), \(current + 1) von \(phaseNames.count)")
    }

    @ViewBuilder
    private func input(for question: Question) -> some View {
        if busy {
            CoachThinking().frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        } else if question.input == "scale" {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: 6) {
                    ForEach(1...10, id: \.self) { value in
                        Button("\(value)") { submit("\(value)") }
                            .buttonStyle(ScalePress())
                    }
                }
                HStack {
                    Text("kaum spürbar")
                    Spacer()
                    Text("Gänsehaut")
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Ink.muted)
            }
        } else if question.input == "choice", !question.options.isEmpty, !ownAnswer {
            VStack(spacing: Space.xs) {
                ForEach(question.options, id: \.self) { option in
                    Button(option) { submit(option) }
                        .buttonStyle(PressStyle(filled: false))
                        .accessibilityIdentifier("choice-\(question.options.firstIndex(of: option) ?? 0)")
                }
                QuietButton("Etwas anderes …") { withAnimation(Motion.smooth) { ownAnswer = true } }
            }
        } else {
            if ownAnswer {
                QuietButton("Zurück zur Auswahl") {
                    answer = ""
                    focused = false
                    withAnimation(Motion.smooth) { ownAnswer = false }
                }
            }
            HStack(alignment: .bottom, spacing: Space.xs) {
                TextField("Deine Antwort", text: $answer, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .accessibilityIdentifier("answer-field")
                    .font(.bodyText)
                    .modifier(FieldBackground(focused: focused))
                Button {
                    submit(answer)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Ink.night)
                        .frame(width: 52, height: 52)
                        .background(Ink.dawn, in: Circle())
                        .opacity(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                        .animation(Motion.snappy, value: answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .buttonStyle(AreaPress())
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Antwort senden")
            }
            .onAppear { focused = true }
        }
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let question, !trimmed.isEmpty, !busy else { return }
        Haptics.tap()
        let turn = Turn(question: question.question, answer: String(trimmed.prefix(2000)))
        // Answering again after a failed request replaces the answer instead of adding a second one.
        if model.progress?.turns.last?.question == turn.question {
            model.progress?.turns.removeLast()
        }
        model.progress?.turns.append(turn)
        answer = ""
        ownAnswer = false
        Task { await next() }
    }

    private func next() async {
        guard let progress = model.progress else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let q = try await model.api.nextQuestion(area: progress.area, turns: progress.turns, voice: progress.voice == true)
            guard model.progress?.run == progress.run else { return } // the interview was restarted meanwhile
            if q.done {
                focused = false
                round?.cancel()
                voice.stop()
                withAnimation(Motion.smooth) { drafting = true }
                let draft = try await model.api.draft(area: progress.area, turns: progress.turns, feedback: nil)
                guard model.progress?.run == progress.run else { return }
                Haptics.success()
                withAnimation(Motion.smooth) { model.progress?.draft = draft }
            } else {
                withAnimation(Motion.smooth) { question = q }
                if voiceOn { converse(q) }
            }
        } catch {
            drafting = false
            self.error = error.localizedDescription
        }
    }
}

/// One step of the 1-10 scale: a compact surface key that sinks while pressed.
private struct ScalePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(configuration.isPressed ? Ink.night : Ink.paper)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? Ink.dawn : Ink.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Ink.line))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Realtime conversation with the coach. The coach leads and ends it; the transcript becomes the interview turns.
struct LiveInterviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var live = LiveVoice()
    /** The conversation is over and the contract is being written. */
    @State private var writing = false
    @State private var error: String?
    @State private var confirmRestart = false

    /** Fewer turns are not enough for a contract. */
    private let minTurns = 6
    /** The typed and the read-aloud interview take at most this many turns. */
    private let typedTurns = 14

    private var turnCount: Int { (model.progress?.turns.count ?? 0) + LiveVoice.pair(live.entries).count }

    private var failure: String? {
        if let error { return error }
        if case .failed(let message) = live.state { return message }
        return nil
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button("Von vorn beginnen") { confirmRestart = true }
                }
                .font(.label)
                .foregroundStyle(Ink.muted)
                .frame(minHeight: 44)
                if writing {
                    Spacer()
                    VStack(alignment: .leading, spacing: Space.page) {
                        WritingNote()
                        if let error {
                            ErrorNote(text: error)
                            Button("Noch einmal versuchen") { Task { await writeDraft() } }
                                .buttonStyle(PressStyle(filled: false))
                        } else {
                            CoachThinking(text: "Der Coach formuliert")
                        }
                    }
                    .transition(.opacity)
                    Spacer()
                } else {
                    conversation
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.m)
            .animation(Motion.smooth, value: failure)
        }
        .task { await start() }
        .onDisappear { live.stop() }
        .onChange(of: scenePhase) { _, phase in
            // Only a real exit ends the talk; a notification banner or the app switcher (.inactive) does not.
            if phase == .background { live.interrupt("Das Gespräch wurde unterbrochen, weil du die App verlassen hast.") }
        }
        .onChange(of: live.state) { _, state in
            if state == .finished { finish() }
            // Keep what was said even if the app is closed before the person decides how to go on.
            if case .failed = state { bank() }
        }
        .confirmationDialog("Das Gespräch beginnt von vorn. Deine bisherigen Antworten gehen verloren.", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Von vorn beginnen", role: .destructive) {
                live.stop()
                withAnimation(Motion.smooth) { model.progress = nil }
            }
            Button("Weitermachen", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var conversation: some View {
        LiveCaptions(live: live)
        VStack(spacing: Space.s) {
            if let failure {
                ErrorNote(text: failure)
                Button("Noch einmal verbinden") {
                    bank()
                    Task { await start() }
                }
                .buttonStyle(PressStyle())
                Button("Vorlese-Modus") {
                    Task {
                        if await VoiceCoach.authorize() {
                            leave(voice: true)
                        } else {
                            error = "Die Spracherkennung ist für Vision 8 nicht freigegeben. Du kannst tippen."
                        }
                    }
                }
                .buttonStyle(PressStyle(filled: false))
            } else {
                Button("Gespräch beenden und Vertrag schreiben") { finish() }
                    .buttonStyle(PressStyle())
                    .disabled(turnCount < minTurns)
            }
            QuietButton("Lieber tippen") { leave(voice: false) }
        }
        .padding(.top, Space.xs)
    }

    /// Asks the worker for a session and connects; the coach continues from the turns so far.
    private func start() async {
        guard let progress = model.progress else { return }
        error = nil
        do {
            let session = try await model.api.voiceSession(area: progress.area, turns: progress.turns)
            // The person may have left or restarted while the request was running.
            guard !Task.isCancelled, model.progress?.run == progress.run, model.progress?.live == true else { return }
            live.connect(url: session.url, token: session.token, callSid: session.callSid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stops the stream and moves this session's turns into the stored interview.
    private func bank() {
        live.stop()
        let turns = live.takeTurns()
        guard let progress = model.progress, !turns.isEmpty else { return }
        model.progress?.turns = Array((progress.turns + turns).suffix(60))
    }

    /// Continues with the typed (voice false) or the read-aloud (voice true) interview from the turns so far.
    private func leave(voice: Bool) {
        bank()
        guard let progress = model.progress else { return }
        withAnimation(Motion.smooth) {
            model.progress?.turns = Array(progress.turns.suffix(typedTurns))
            model.progress?.voice = voice
            model.progress?.live = false
        }
    }

    private func finish() {
        guard !writing else { return }
        // The coach ended the talk with the crisis line: no goal contract on top of that.
        let crisis = live.entries.suffix(4).contains { $0.speaker == "agent" && $0.text.localizedCaseInsensitiveContains("Telefonseelsorge") }
        bank()
        if crisis {
            error = "Dein Coach hat das Gespräch beendet. Die Telefonseelsorge erreichst du kostenlos und rund um die Uhr unter 0800 111 0 111, im Notfall die 112. Wenn du magst, machen wir später weiter."
            return
        }
        guard (model.progress?.turns.count ?? 0) >= minTurns else {
            error = "Das Gespräch war zu kurz für einen Zielvertrag. Verbinde dich noch einmal und erzähl dem Coach mehr."
            return
        }
        withAnimation(Motion.smooth) { writing = true }
        Task { await writeDraft() }
    }

    private func writeDraft() async {
        guard let progress = model.progress else { return }
        error = nil
        do {
            let draft = try await model.api.draft(area: progress.area, turns: progress.turns, feedback: nil)
            guard model.progress?.run == progress.run else { return } // the interview was restarted meanwhile
            Haptics.success()
            withAnimation(Motion.smooth) { model.progress?.draft = draft }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Status line and captions of a realtime conversation; shared by the intake and the follow-up conversations.
struct LiveCaptions: View {
    let live: LiveVoice

    private var status: String {
        switch live.state {
        case .live: return Date().timeIntervalSince(live.lastAgentAudio) < 0.6 ? "Clara spricht" : "Clara hört zu"
        case .finished: return "Gespräch beendet"
        default: return "Verbinde …"
        }
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(live.state == .live ? Ink.dawn : Ink.muted)
                .symbolEffect(.variableColor.iterative, isActive: live.state == .live)
            // Re-evaluated twice a second so the line falls back to "hört zu" when the coach stops.
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(status)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Ink.muted)
                    .contentTransition(.opacity)
                    .animation(Motion.smooth, value: status)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.top, Space.page)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(live.agentText.isEmpty ? "Dein Coach begrüßt dich. Dreh den Ton auf." : live.agentText)
                    .font(.display(28))
                    .fixedSize(horizontal: false, vertical: true)
                    .id(live.agentText)
                    .transition(.opacity)
                if !live.callerText.isEmpty {
                    Text(live.callerText)
                        .font(.bodyText)
                        .foregroundStyle(Ink.muted)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.section)
            .animation(Motion.smooth, value: live.agentText)
        }
        .scrollIndicators(.hidden)
    }
}
