import SwiftUI

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

    private var list: [ListItem]? { model.state?.list }

    private let sections: [(key: String, title: String, hint: String)] = [
        ("now", "Zuerst", "Wichtig und dringend"),
        ("next", "Dein Schritt nach vorn", "Wichtig, bringt dich deiner Vision näher"),
        ("later", "Wenn Zeit bleibt", "Dringend, aber nicht wichtig"),
    ]

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    DayScoreCard()
                    if let list {
                        ForEach(sections, id: \.key) { section in
                            let items = list.filter { $0.quadrant == section.key }
                            if !items.isEmpty { block(section.title, section.hint, items) }
                        }
                        addRow
                        if building {
                            CoachThinking(text: "Der Coach stellt neu zusammen")
                        } else {
                            Button("Liste neu zusammenstellen lassen") { Task { await build(fresh: true) } }
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                                .foregroundStyle(Ink.muted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    } else {
                        CoachThinking(text: "Dein Coach stellt deinen Tag zusammen").padding(.top, 12)
                    }
                    if let error { ErrorNote(text: error) }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
        }
        .task { if list == nil, !building { await build(fresh: false) } }
        .sheet(isPresented: $showStreak) {
            if let streak = model.state?.coachStreak { StreakSheet(streak: streak).presentationDetents([.medium]) }
        }
        .onChange(of: model.state?.coachStreak?.days) { _, days in celebrate(days ?? 0) }
        .onAppear { celebrate(model.state?.coachStreak?.days ?? 0) }
        .overlay {
            if let milestone {
                MilestoneView(days: milestone) { withAnimation { self.milestone = nil } }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))))
                Text(model.name.map { "Hallo \($0)" } ?? "Heute").font(.display(34))
            }
            Spacer()
            if let streak = model.state?.coachStreak {
                Button { showStreak = true } label: { StreakBadge(streak: streak) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func block(_ title: String, _ hint: String, _ items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.display(22))
                Text(hint).font(.system(.caption, design: .rounded)).foregroundStyle(Ink.muted)
            }
            VStack(spacing: 0) {
                ForEach(items) { item in row(item) }
            }
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.line))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func row(_ item: ListItem) -> some View {
        SwipeRow(done: { if !item.done { Task { await check(item, true) } } }, delete: { Task { await remove(item) } }) {
            Button { Task { await check(item, !item.done) } } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.done ? Ink.good : Ink.muted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .strikethrough(item.done, color: Ink.muted)
                            .foregroundStyle(item.done ? Ink.muted : Ink.paper)
                            .multilineTextAlignment(.leading)
                        if !item.done, !item.why.isEmpty {
                            Text(item.why)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Ink.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    if item.source != "coach" {
                        Text(item.source == "habit" ? "täglich" : "von dir")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Ink.night, in: Capsule())
                            .foregroundStyle(Ink.muted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityValue(item.done ? "erledigt" : "offen")
            .accessibilityHint("Antippen zum Abhaken. Nach rechts wischen: erledigt, nach links: löschen.")
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Was steht noch an?", text: $newItem)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { Task { await add() } }
                    .font(.system(.body, design: .rounded))
                    .padding(14)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.line))
                if adding {
                    ProgressView().tint(Ink.dawn).frame(width: 44, height: 44)
                } else {
                    Button { Task { await add() } } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Ink.night)
                            .frame(width: 44, height: 44)
                            .background(Ink.dawn, in: Circle())
                    }
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Hinzufügen, der Coach sortiert ein")
                }
            }
            Text(advice ?? "Der Coach sortiert deinen Eintrag nach wichtig und dringend ein.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(advice == nil ? Ink.muted : Ink.dawn)
            if let lastAdded, !model.call.active {
                Button {
                    Task { await model.call.start(model.api, focus: "todo", topic: lastAdded) }
                    self.lastAdded = nil
                } label: {
                    Label("Mit dem Coach über „\(lastAdded)“ sprechen", systemImage: "waveform")
                        .lineLimit(1)
                }
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Ink.dawn)
                .frame(minHeight: 44)
            }
        }
    }

    /// Celebrates 3, 7, 14, 30, 50 and 100 days once each.
    private func celebrate(_ days: Int) {
        guard let reached = [100, 50, 30, 14, 7, 3].first(where: { days >= $0 }), reached > celebrated else { return }
        celebrated = reached
        Haptics.success()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { milestone = reached }
    }

    private func apply(_ items: [ListItem]) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.state?.list = items }
    }

    private func build(fresh: Bool) async {
        building = true
        error = nil
        defer { building = false }
        do {
            apply(try await model.api.todayList(fresh: fresh).items)
            await model.refresh()
        } catch {
            self.error = error.localizedDescription
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
            newItem = ""
            advice = result.advice
            lastAdded = title
            Haptics.success()
            apply(result.items)
            await model.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func check(_ item: ListItem, _ done: Bool) async {
        Haptics.tap()
        guard let index = list?.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation { model.state?.list?[index].done = done } // optimistic
        do {
            apply(try await model.api.checkToday(id: item.id, done: done).items)
            await model.refresh()
            if done { Haptics.success() }
        } catch {
            withAnimation { model.state?.list?[index].done = !done }
            self.error = error.localizedDescription
        }
    }

    private func remove(_ item: ListItem) async {
        do {
            apply(try await model.api.removeToday(id: item.id).items)
            await model.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The flame with the number of days, lit when today already counts.
private struct StreakBadge: View {
    let streak: CoachStreak

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(streak.today ? Ink.dawn : Ink.muted)
                .symbolEffect(.bounce, value: streak.today)
            Text("\(streak.days)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(streak.today ? Ink.dawn : Ink.muted)
                .contentTransition(.numericText(value: Double(streak.days)))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Ink.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(streak.today ? Ink.dawn.opacity(0.5) : Ink.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak: \(streak.days) Tage\(streak.today ? ", heute geschafft" : ", heute noch offen")")
    }
}

private struct StreakSheet: View {
    let streak: CoachStreak

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill").font(.system(size: 40)).foregroundStyle(streak.today ? Ink.dawn : Ink.muted)
                    Text("\(streak.days) \(streak.days == 1 ? "Tag" : "Tage")").font(.display(34))
                }
                Text(streak.today ? "Heute hast du deinem Coach schon geantwortet. Morgen geht es weiter." : "Heute zählt noch nicht. Ein Haken auf deiner Liste oder ein kurzes Gespräch mit deinem Coach reicht.")
                    .font(.system(.body, design: .rounded))
                VStack(alignment: .leading, spacing: 6) {
                    Label("Etwas auf deiner Liste abhaken", systemImage: "checkmark.circle")
                    Label("Mit deinem Coach sprechen", systemImage: "waveform")
                    Label("Den Abend-Anruf annehmen", systemImage: "phone")
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Ink.muted)
                Text(streak.jokerUsed ? "Dein Joker für diese Woche ist verbraucht." : "Ein verpasster Tag pro Woche unterbricht deinen Streak nicht.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Ink.muted)
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}

/// Full-screen moment for a streak milestone.
private struct MilestoneView: View {
    let days: Int
    var dismiss: () -> Void
    @State private var glow = false

    var body: some View {
        ZStack {
            Ink.night.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Ink.dawn.opacity(0.22)).frame(width: 200, height: 200).blur(radius: 30).scaleEffect(glow ? 1.15 : 0.9)
                    Image(systemName: "flame.fill").font(.system(size: 110)).foregroundStyle(Ink.dawn).symbolEffect(.bounce, value: glow)
                }
                Text("\(days) Tage am Stück").font(.display(34))
                Text(days >= 30 ? "Das ist keine Phase mehr. Das bist du." : days >= 7 ? "Eine ganze Woche. Genau so entstehen Gewohnheiten." : "Der Anfang ist gemacht. Bleib dran.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.center)
                Button("Weiter", action: dismiss).buttonStyle(PressStyle()).frame(width: 220)
            }
            .padding(32)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true } }
        .accessibilityAddTraits(.isModal)
    }
}
