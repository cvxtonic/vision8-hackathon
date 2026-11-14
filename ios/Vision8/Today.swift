import SwiftUI

/// STYLEGUIDE: list rows sit 14 pt from the card edge; the check icon column is fixed so separators line up with the text.
private let rowInset: CGFloat = 14
private let iconColumn: CGFloat = 24
private let cardShape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)

/// Heute: one list for the day, sorted by important and urgent. The coach builds it from the vision and your talks;
/// what you add yourself, the coach sorts in.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var building = false
    @State private var adding = false
    @State private var newItem = ""
    @State private var advice: String?
    @State private var lastAdded: String?
    @State private var error: String?
    @FocusState private var typing: Bool
    @State private var showStreak = false
    @State private var milestone: Int?
    @AppStorage("celebratedStreak") private var celebrated = 0

    /// The coach's ranking of the area to-dos for today.
    private var list: [ListItem]? { model.state?.list }
    private var canAdd: Bool { !newItem.trimmingCharacters(in: .whitespaces).isEmpty }

    private let sections: [(key: String, title: String, hint: String)] = [
        ("now", "Zuerst", "Wichtig und dringend"),
        ("next", "Dein Schritt nach vorn", "Wichtig, bringt dich deiner Vision näher"),
        ("later", "Wenn Zeit bleibt", "Dringend, aber nicht wichtig"),
    ]

    var body: some View {
        Screen {
            ScrollView {
                Page {
                    header.appear(0)
                    DayScoreCard().appear(1)
                    if list != nil {
                        AreaList().appear(2)
                    } else if error == nil {
                        loading.transition(.opacity)
                    } else if !building {
                        Button("Erneut versuchen") { Task { await build(fresh: false) } }
                            .font(.note.weight(.semibold))
                            .foregroundStyle(Ink.muted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    if let error { ErrorNote(text: error).transition(.opacity) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
        }
        .task {
            if list == nil, !building { await build(fresh: false) }
            // A list from before the ranking has no points; let the coach rank the to-dos fresh.
            else if let list, !(model.state?.kpis ?? []).isEmpty, !list.contains(where: { $0.points != nil }), !building { await build(fresh: true) }
        }
        .sheet(isPresented: $showStreak) {
            if let streak = model.state?.coachStreak { StreakSheet(streak: streak).presentationDetents([.medium]) }
        }
        .onChange(of: model.state?.coachStreak?.days) { _, days in celebrate(days ?? 0) }
        .onAppear { celebrate(model.state?.coachStreak?.days ?? 0) }
        .overlay {
            if let milestone {
                MilestoneView(days: milestone) { withAnimation(Motion.smooth) { self.milestone = nil } }
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Pieces

    /// Date eyebrow over the greeting; the streak badge sits on the title's baseline.
    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))))
                Text(model.name.map { "Hallo \($0)" } ?? "Heute")
                    .font(.pageTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            if let streak = model.state?.coachStreak {
                Button { showStreak = true } label: { StreakBadge(streak: streak) }
                    .buttonStyle(.plain)
            }
        }
    }

    /// While the coach builds the first list: the shape of what is coming.
    private var loading: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Skeleton(height: 22).frame(width: 140)
            VStack(spacing: Space.xs) {
                ForEach(0..<5, id: \.self) { _ in Skeleton(height: 56) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Dein Coach stellt deinen Tag zusammen")
    }

    private func block(_ title: String, _ hint: String, _ items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionHeader(title: title, hint: hint)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item, separator: item.id != items.last?.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Ink.surface, in: cardShape)
            .clipShape(cardShape)
            .overlay(cardShape.strokeBorder(Ink.line))
        }
    }

    private func row(_ item: ListItem, separator: Bool) -> some View {
        SwipeRow(done: { if !item.done { Task { await check(item, true, haptic: false) } } }, delete: { Task { await remove(item) } }) {
            Button { Task { await check(item, !item.done) } } label: {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.done ? Ink.good : Ink.muted)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: item.done)
                        .frame(width: iconColumn)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(item.title)
                            .font(.bodyText.weight(.medium))
                            .strikethrough(item.done, color: Ink.muted)
                            .foregroundStyle(item.done ? Ink.muted : Ink.paper)
                            .multilineTextAlignment(.leading)
                        if !item.done, !item.why.isEmpty {
                            Text(item.why)
                                .font(.note)
                                .foregroundStyle(Ink.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .transition(.opacity)
                        }
                    }
                    Spacer(minLength: 0)
                    if item.source != "coach" {
                        Text(item.source == "habit" ? "täglich" : "von dir")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, Space.xs)
                            .padding(.vertical, 3)
                            .background(Ink.night, in: Capsule())
                            .foregroundStyle(Ink.muted)
                    }
                }
                .padding(.horizontal, rowInset)
                .padding(.vertical, Space.s)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .overlay(alignment: .bottom) {
                if separator {
                    Rectangle().fill(Ink.line).frame(height: 0.5).padding(.leading, rowInset + iconColumn + Space.s)
                }
            }
            .accessibilityValue(item.done ? "erledigt" : "offen")
            .accessibilityHint("Antippen zum Abhaken. Nach rechts wischen: erledigt, nach links: löschen.")
        }
    }

    /// A composer like Messages: field and send button in one surface.
    private var addRow: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                TextField("Was steht noch an?", text: $newItem)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit { Task { await add() } }
                    .font(.bodyText)
                ZStack {
                    if adding {
                        ProgressView().tint(Ink.dawn)
                    } else {
                        Button { Task { await add() } } label: {
                            Image(systemName: "arrow.up")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(canAdd ? Ink.night : Ink.muted)
                                .frame(width: 34, height: 34)
                                .background(canAdd ? Ink.dawn : Ink.line, in: Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAdd)
                        .accessibilityLabel("Hinzufügen, der Coach sortiert ein")
                    }
                }
                .frame(width: 44, height: 44)
            }
            .padding(.leading, Space.m)
            .padding(.trailing, Space.xxs)
            .frame(minHeight: 52)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(typing ? Ink.dawn.opacity(0.35) : Ink.line)
            )
            .animation(Motion.snappy, value: canAdd)
            .animation(Motion.snappy, value: typing)
            .animation(Motion.snappy, value: adding)

            Text(advice ?? "Der Coach sortiert deinen Eintrag nach wichtig und dringend ein.")
                .font(.note)
                .foregroundStyle(advice == nil ? Ink.muted : Ink.paper)
                .padding(.horizontal, Space.xxs)
                .contentTransition(.opacity)
            if let lastAdded, !model.call.active {
                Button {
                    Task { await model.call.start(model.api, focus: "todo", topic: lastAdded) }
                    withAnimation(Motion.snappy) { self.lastAdded = nil }
                } label: {
                    Label("Mit dem Coach über „\(lastAdded)“ sprechen", systemImage: "waveform")
                        .lineLimit(1)
                }
                .font(.note.weight(.semibold))
                .foregroundStyle(Ink.dawn)
                .frame(minHeight: 44)
                .padding(.horizontal, Space.xxs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var rebuildRow: some View {
        Group {
            if building {
                CoachThinking(text: "Der Coach stellt neu zusammen")
            } else {
                Button("Liste neu zusammenstellen lassen") { Task { await build(fresh: true) } }
                    .font(.note.weight(.semibold))
                    .foregroundStyle(Ink.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .animation(Motion.smooth, value: building)
    }

    // MARK: - Actions

    /// Celebrates 3, 7, 14, 30, 50 and 100 days once each.
    private func celebrate(_ days: Int) {
        guard let reached = [100, 50, 30, 14, 7, 3].first(where: { days >= $0 }), reached > celebrated else { return }
        celebrated = reached
        Haptics.success()
        withAnimation(Motion.smooth) { milestone = reached }
    }

    private func apply(_ items: [ListItem]) {
        withAnimation(Motion.smooth) { model.state?.list = items }
    }

    private func build(fresh: Bool) async {
        building = true
        withAnimation(Motion.smooth) { error = nil }
        defer { building = false }
        do {
            apply(try await model.api.todayList(fresh: fresh).items)
            await model.refresh()
        } catch {
            withAnimation(Motion.smooth) { self.error = error.localizedDescription }
        }
    }

    private func add() async {
        let title = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !adding else { return }
        adding = true
        error = nil
        defer { adding = false }
        do {
            let result = try await model.api.addToday(String(title.prefix(90)))
            withAnimation(Motion.smooth) {
                newItem = ""
                advice = result.advice
                lastAdded = title
            }
            Haptics.success()
            apply(result.items)
            await model.refresh()
        } catch {
            withAnimation(Motion.smooth) { self.error = error.localizedDescription }
        }
    }

    /// `haptic: false` when the swipe already gave its own feedback.
    private func check(_ item: ListItem, _ done: Bool, haptic: Bool = true) async {
        // Index into the stored list (which still holds older habit entries), not the filtered one.
        guard let index = model.state?.list?.firstIndex(where: { $0.id == item.id }) else { return }
        if haptic {
            if done { Haptics.success() } else { Haptics.tap() }
        }
        withAnimation(Motion.snappy) { model.state?.list?[index].done = done } // optimistic
        do {
            apply(try await model.api.checkToday(id: item.id, done: done).items)
            await model.refresh()
        } catch {
            withAnimation(Motion.snappy) { model.state?.list?[index].done = !done }
            withAnimation(Motion.smooth) { self.error = error.localizedDescription }
        }
    }

    private func remove(_ item: ListItem) async {
        do {
            apply(try await model.api.removeToday(id: item.id).items)
            await model.refresh()
        } catch {
            withAnimation(Motion.smooth) { self.error = error.localizedDescription }
        }
    }
}

/// The flame with the number of days, lit when today already counts.
private struct StreakBadge: View {
    let streak: CoachStreak

    var body: some View {
        HStack(spacing: Space.xxs) {
            Image(systemName: "flame.fill")
                .font(.callout)
                .symbolEffect(.bounce, value: streak.today)
            Text("\(streak.days)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .contentTransition(.numericText(value: Double(streak.days)))
        }
        .foregroundStyle(streak.today ? Ink.dawn : Ink.muted)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(Ink.surface, in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .animation(Motion.snappy, value: streak.days)
        .animation(Motion.snappy, value: streak.today)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak: \(streak.days) Tage\(streak.today ? ", heute geschafft" : ", heute noch offen")")
        .accessibilityAddTraits(.isButton)
    }
}

private struct StreakSheet: View {
    let streak: CoachStreak

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.page) {
                HStack(alignment: .lastTextBaseline, spacing: Space.s) {
                    Image(systemName: "flame.fill").font(.system(size: 34)).foregroundStyle(streak.today ? Ink.dawn : Ink.muted)
                    Text("\(streak.days) \(streak.days == 1 ? "Tag" : "Tage")").font(.pageTitle)
                }
                Text(streak.today ? "Heute hast du deinem Coach schon geantwortet. Morgen geht es weiter." : "Heute zählt noch nicht. Ein Haken auf deiner Liste oder ein kurzes Gespräch mit deinem Coach reicht.")
                    .font(.bodyText)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Label("Etwas auf deiner Liste abhaken", systemImage: "checkmark.circle")
                    Label("Mit deinem Coach sprechen", systemImage: "waveform")
                    Label("Den Abend-Anruf annehmen", systemImage: "phone")
                }
                .font(.callout)
                .foregroundStyle(Ink.muted)
                Text(streak.jokerUsed ? "Dein Joker für diese Woche ist verbraucht." : "Ein verpasster Tag pro Woche unterbricht deinen Streak nicht.")
                    .font(.note)
                    .foregroundStyle(Ink.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.section)
        }
    }
}

/// Full-screen moment for a streak milestone: the dim fades in, the flame springs up, then the words rise.
private struct MilestoneView: View {
    let days: Int
    var dismiss: () -> Void
    @State private var flameShown = false
    @State private var textShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Ink.night.opacity(0.92).ignoresSafeArea()
            VStack(spacing: Space.page) {
                ZStack {
                    // Time-driven glow instead of repeatForever, which can block the overlay's removal transition.
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        Circle()
                            .fill(Ink.dawn.opacity(0.22))
                            .frame(width: 200, height: 200)
                            .blur(radius: 30)
                            .scaleEffect(reduceMotion ? 1 : 1.025 + 0.125 * sin(t * 2.6))
                    }
                    Image(systemName: "flame.fill")
                        .font(.system(size: 110))
                        .foregroundStyle(Ink.dawn)
                        .symbolEffect(.bounce, value: flameShown)
                }
                .scaleEffect(flameShown || reduceMotion ? 1 : 0.7)
                .opacity(flameShown ? 1 : 0)
                VStack(spacing: Space.xs) {
                    Text("\(days) Tage am Stück").font(.pageTitle)
                    Text(days >= 30 ? "Das ist keine Phase mehr. Das bist du." : days >= 7 ? "Eine ganze Woche. Genau so entstehen Gewohnheiten." : "Der Anfang ist gemacht. Bleib dran.")
                        .font(.bodyText)
                        .foregroundStyle(Ink.muted)
                }
                .multilineTextAlignment(.center)
                .opacity(textShown ? 1 : 0)
                .offset(y: textShown || reduceMotion ? 0 : 12)
                Button("Weiter", action: dismiss)
                    .buttonStyle(PressStyle())
                    .frame(width: 220)
                    .padding(.top, Space.xs)
                    .opacity(textShown ? 1 : 0)
            }
            .padding(Space.xl)
        }
        .onAppear {
            withAnimation(Motion.gentle) { flameShown = true }
            withAnimation(Motion.gentle.delay(reduceMotion ? 0 : 0.18)) { textShown = true }
        }
        .accessibilityAddTraits(.isModal)
    }
}
