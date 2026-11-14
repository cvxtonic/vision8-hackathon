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
                Welcome { withAnimation { started = true } }
            }
        }
        .transition(.opacity)
        // Restarting the interview leads back to the very first screen.
        .onChange(of: model.progress == nil) { _, cleared in
            if cleared { started = false }
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
                Spacer(minLength: 12)
                Eyebrow("Vision 8 · Vision Aid")
                Text("Ziele, die du\nwirklich erreichst.")
                    .font(.display(38))
                    .padding(.top, 12)
                Text("Ein Coach, der dich an die Hand nimmt – vom ersten Ziel bis zum Tag, an dem du es geschafft hast.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Ink.muted)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .font(.system(.headline, design: .serif))
                                .foregroundStyle(Ink.night)
                                .frame(width: 30, height: 30)
                                .background(Ink.dawn, in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title).font(.system(.headline, design: .rounded))
                                Text(step.text)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Ink.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 32)
                Spacer(minLength: 20)
                Button("Erstgespräch starten", action: start).buttonStyle(PressStyle())
                Text("Etwa 5 Minuten, meist nur antippen. Deine Antworten bleiben in der EU.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .padding(28)
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
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                Eyebrow("Dein Coach")
                Text("Schön, dass du da bist. Wie darf ich dich nennen?").font(.display(30))
                TextField("Dein Vorname", text: $name)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .font(.system(.title3, design: .rounded))
                    .padding(16)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.line))
                    .onSubmit { if valid { Task { await save() } } }
                if let error { ErrorNote(text: error) }
                Spacer()
                if busy {
                    CoachThinking(text: "Einen Moment")
                } else {
                    Button("Weiter") { Task { await save() } }
                        .buttonStyle(PressStyle())
                        .disabled(!valid)
                }
            }
            .padding(28)
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
            withAnimation { model.name = cleaned }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AreaPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow("Schritt 1")
                    Text(model.name.map { "\($0), was ist dir in deiner jetzigen Lage am wichtigsten?" } ?? "Was ist dir in deiner jetzigen Lage am wichtigsten?").font(.display(30))
                    Text("Wir starten dort. Weitere Bereiche kannst du später dazunehmen.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Ink.muted)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(Area.all) { area in
                            Button {
                                Haptics.tap()
                                withAnimation { model.progress = InterviewProgress(area: area.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: area.symbol).font(.title2).foregroundStyle(Ink.dawn)
                                    Text(area.title).font(.system(.headline, design: .rounded))
                                    Text(area.hint)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Ink.muted)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                                .padding(16)
                                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Ink.line))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(28)
            }
        }
    }
}

/// Speak with the coach or tap through: asked once, right after the life area.
private struct ModeChooser: View {
    @Environment(AppModel.self) private var model
    @State private var denied = false

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                Eyebrow("Schritt 2")
                Text("Wie möchtest du mit deinem Coach sprechen?").font(.display(30))
                Text("Im Gespräch lernt dich dein Coach in etwa zehn Minuten kennen: Er fragt, du erzählst, er hört zu. Du kannst jederzeit zum Tippen wechseln.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Ink.muted)
                if denied {
                    ErrorNote(text: "Das Mikrofon ist für Vision 8 nicht freigegeben. Du kannst das in den iOS-Einstellungen ändern oder jetzt tippen.")
                }
                Spacer()
                Button {
                    Task {
                        if await LiveVoice.authorize() {
                            Haptics.tap()
                            withAnimation { model.progress?.live = true }
                        } else {
                            denied = true
                        }
                    }
                } label: {
                    Label("Im Gespräch", systemImage: "waveform")
                }
                .buttonStyle(PressStyle())
                Button("Lieber antippen und tippen") {
                    withAnimation { model.progress?.voice = false }
                }
                .buttonStyle(PressStyle(filled: false))
                Button("Zurück") { withAnimation { model.progress = nil } }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(28)
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
                header
                if drafting {
                    Spacer()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ich schreibe deinen Zielvertrag.").font(.display(28))
                        Text("Aus unserem Gespräch entstehen deine Vision, dein Warum und deine Ziele – von drei Jahren bis zu diesem Monat. Das dauert etwa eine halbe Minute.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Ink.muted)
                        CoachThinking(text: "Der Coach formuliert")
                    }
                    Spacer()
                } else if let question {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !question.mirror.isEmpty {
                                Text(question.mirror).font(.quote).foregroundStyle(Ink.muted)
                            }
                            Text(question.question).font(.display(26))
                            if question.input == "text" || ownAnswer, let hint = question.hint, !hint.isEmpty {
                                Text(hint)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Ink.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 28)
                        .id(question.question)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .scrollDismissesKeyboard(.interactively)
                    if voiceOn {
                        voiceControls(for: question)
                    } else {
                        input(for: question)
                    }
                } else {
                    Spacer()
                    CoachThinking()
                    Spacer()
                }
                if let error {
                    ErrorNote(text: error).padding(.top, 10)
                    Button("Noch einmal versuchen") { Task { await next() } }
                        .buttonStyle(PressStyle(filled: false))
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
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
                withAnimation { model.progress = nil }
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
        VStack(alignment: .leading, spacing: 12) {
            if busy {
                CoachThinking().frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: voice.state == .listening ? "mic.fill" : voice.state == .speaking ? "speaker.wave.2.fill" : "mic.slash")
                        .font(.title3)
                        .foregroundStyle(voice.state == .idle ? Ink.muted : Ink.dawn)
                        .symbolEffect(.pulse, isActive: voice.state == .listening)
                    Text(voice.state == .listening ? "Ich höre zu …" : voice.state == .speaking ? "Der Coach spricht" : heardNothing ? "Ich habe nichts gehört." : "Bereit")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Ink.muted)
                }
                .accessibilityElement(children: .combine)
                if !voice.transcript.isEmpty, voice.state == .listening {
                    Text(voice.transcript)
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        withAnimation { model.progress?.voice = false }
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
        return VStack(alignment: .trailing, spacing: 4) {
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
                            withAnimation { model.progress?.live = true }
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
        HStack(spacing: 6) {
            ForEach(Array(phaseNames.enumerated()), id: \.offset) { index, name in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(index <= current ? Ink.dawn : Ink.line).frame(height: 4)
                    Text(name)
                        .font(.label)
                        .foregroundStyle(index == current ? Ink.paper : Ink.muted)
                }
            }
        }
        .animation(.easeInOut, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Abschnitt \(phaseNames[current]), \(current + 1) von \(phaseNames.count)")
    }

    @ViewBuilder
    private func input(for question: Question) -> some View {
        if busy {
            CoachThinking().frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        } else if question.input == "scale" {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(1...10, id: \.self) { value in
                        Button("\(value)") { submit("\(value)") }
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.line))
                            .foregroundStyle(Ink.paper)
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
            VStack(spacing: 8) {
                ForEach(question.options, id: \.self) { option in
                    Button(option) { submit(option) }
                        .buttonStyle(PressStyle(filled: false))
                        .accessibilityIdentifier("choice-\(question.options.firstIndex(of: option) ?? 0)")
                }
                Button("Etwas anderes …") { withAnimation { ownAnswer = true } }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        } else {
            if ownAnswer {
                Button("Zurück zur Auswahl") {
                    answer = ""
                    focused = false
                    withAnimation { ownAnswer = false }
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Ink.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Deine Antwort", text: $answer, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .accessibilityIdentifier("answer-field")
                    .font(.system(.body, design: .rounded))
                    .padding(14)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.line))
                Button {
                    submit(answer)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Ink.night)
                        .frame(width: 50, height: 50)
                        .background(Ink.dawn, in: Circle())
                }
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
                withAnimation { drafting = true }
                let draft = try await model.api.draft(area: progress.area, turns: progress.turns, feedback: nil)
                guard model.progress?.run == progress.run else { return }
                Haptics.success()
                withAnimation { model.progress?.draft = draft }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { question = q }
                if voiceOn { converse(q) }
            }
        } catch {
            drafting = false
            self.error = error.localizedDescription
        }
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
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ich schreibe deinen Zielvertrag.").font(.display(28))
                        Text("Aus unserem Gespräch entstehen deine Vision, dein Warum und deine Ziele – von drei Jahren bis zu diesem Monat. Das dauert etwa eine halbe Minute.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Ink.muted)
                        if let error {
                            ErrorNote(text: error)
                            Button("Noch einmal versuchen") { Task { await writeDraft() } }
                                .buttonStyle(PressStyle(filled: false))
                        } else {
                            CoachThinking(text: "Der Coach formuliert")
                        }
                    }
                    Spacer()
                } else {
                    conversation
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
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
                withAnimation { model.progress = nil }
            }
            Button("Weitermachen", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var conversation: some View {
        LiveCaptions(live: live)
        VStack(spacing: 10) {
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
            Button("Lieber tippen") { leave(voice: false) }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Ink.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
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
        withAnimation {
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
        withAnimation { writing = true }
        Task { await writeDraft() }
    }

    private func writeDraft() async {
        guard let progress = model.progress else { return }
        error = nil
        do {
            let draft = try await model.api.draft(area: progress.area, turns: progress.turns, feedback: nil)
            guard model.progress?.run == progress.run else { return } // the interview was restarted meanwhile
            Haptics.success()
            withAnimation { model.progress?.draft = draft }
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
        case .live: return Date().timeIntervalSince(live.lastAgentAudio) < 0.6 ? "Der Coach spricht" : "Der Coach hört zu"
        case .finished: return "Gespräch beendet"
        default: return "Verbinde …"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(live.state == .live ? Ink.dawn : Ink.muted)
                .symbolEffect(.variableColor.iterative, isActive: live.state == .live)
            // Re-evaluated twice a second so the line falls back to "hört zu" when the coach stops.
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(status)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Ink.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.top, 20)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(live.agentText.isEmpty ? "Dein Coach begrüßt dich. Dreh den Ton auf." : live.agentText)
                    .font(.display(28))
                    .id(live.agentText)
                    .transition(.opacity)
                if !live.callerText.isEmpty {
                    Text(live.callerText)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Ink.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
            .animation(.easeOut(duration: 0.3), value: live.agentText)
        }
    }
}
