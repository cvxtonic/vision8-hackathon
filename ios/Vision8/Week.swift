import EventKit
import EventKitUI
import SwiftUI

/// The coach's to-dos for this week, folded on Heute. Each can go into the calendar.
struct WeekFold: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var error: String?
    @State private var calendarItem: WeekItem?

    private var plan: WeekPlan? { model.state?.week }
    private var doneCount: Int { plan?.items.filter(\.done).count ?? 0 }

    var body: some View {
        Fold(title: "Diese Woche", subtitle: plan.map { "\(doneCount) von \($0.items.count) erledigt" }) {
            weekContent
        }
        .task { if plan == nil, !busy { await load(fresh: false) } }
        .sheet(item: $calendarItem) { item in
            CalendarSheet(item: item, week: plan?.week).ignoresSafeArea()
        }
        // Done -> success; undone stays silent.
        .sensoryFeedback(trigger: doneCount) { old, new in new > old ? .success : nil }
    }

    @ViewBuilder
    private var weekContent: some View {
        if let plan {
            Card {
                Eyebrow("Worum es diese Woche geht")
                Text(plan.focus).font(.quote).fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(doneCount), total: Double(max(plan.items.count, 1)))
                    .tint(Ink.good)
                    .animation(Motion.smooth, value: doneCount)
            }
            VStack(spacing: 0) {
                ForEach(Array(plan.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Hairline() }
                    WeekRow(item: item, toggle: { Task { await toggle(item) } }, addToCalendar: { calendarItem = item })
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.line))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            if busy {
                CoachThinking(text: "Der Coach plant neu")
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Button("Offene To-dos neu planen") { Task { await load(fresh: true) } }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        } else if busy {
            CoachThinking(text: "Dein Coach plant deine Woche")
            ForEach(0..<3, id: \.self) { _ in Skeleton(height: 72) }
        } else {
            Text("Dein Coach macht aus deinem Zielvertrag konkrete Schritte für diese Woche.")
                .font(.bodyText)
                .foregroundStyle(Ink.muted)
            Button("Woche planen lassen") { Task { await load(fresh: false) } }.buttonStyle(PressStyle())
        }
        if let error { ErrorNote(text: error).transition(.opacity) }
    }

    private func load(fresh: Bool) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let week = try await model.api.week(fresh: fresh)
            Haptics.success()
            withAnimation(Motion.smooth) { model.state?.week = week }
        } catch {
            withAnimation(Motion.smooth) { self.error = error.localizedDescription }
        }
    }

    private func toggle(_ item: WeekItem) async {
        guard let index = plan?.items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(Motion.snappy) { model.state?.week?.items[index].done.toggle() } // optimistic
        do {
            let week = try await model.api.checkWeek(id: item.id, done: !item.done)
            model.state?.week = week
        } catch {
            withAnimation(Motion.snappy) { model.state?.week?.items[index].done = item.done }
            withAnimation(Motion.smooth) { self.error = error.localizedDescription }
        }
    }
}

/// Hairline between list rows, inset to the text (row padding + check button + gap).
private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Ink.line)
            .frame(height: 0.5)
            .padding(.leading, WeekRow.inset + 44 + Space.s)
    }
}

private struct WeekRow: View {
    /// STYLEGUIDE: list rows 14 horizontal, 12 vertical.
    static let inset: CGFloat = 14

    let item: WeekItem
    var toggle: () -> Void
    var addToCalendar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Button(action: toggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.done ? Ink.good : Ink.muted)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 44, minHeight: 44, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Erledigt, antippen zum Zurücksetzen" : "Als erledigt markieren")
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(item.title)
                    .font(.bodyText.weight(.medium))
                    .strikethrough(item.done, color: Ink.muted)
                    .foregroundStyle(item.done ? Ink.muted : Ink.paper)
                Text(item.why)
                    .font(.note)
                    .foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s) {
                    Label("\(item.day) · \(item.minutes) Min.", systemImage: "clock")
                    Spacer()
                    Button(action: addToCalendar) {
                        Label("In Kalender", systemImage: "calendar.badge.plus")
                    }
                    .foregroundStyle(Ink.dawn)
                    .frame(minHeight: 44)
                }
                .font(.label)
                .foregroundStyle(Ink.muted)
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, Space.s)
        .frame(minHeight: 44)
    }
}

/// The system "new event" dialog, prefilled. The person picks the calendar there (e.g. their Google calendar);
/// since iOS 17 this dialog needs no calendar permission because it runs outside the app.
private struct CalendarSheet: UIViewControllerRepresentable {
    let item: WeekItem
    let week: String?

    private static let store = EKEventStore()

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let event = EKEvent(eventStore: Self.store)
        event.title = item.title
        event.notes = "\(item.why)\n\nAus deinem Wochenplan in Vision 8."
        let start = startDate()
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(item.minutes * 60))
        let controller = EKEventEditViewController()
        controller.eventStore = Self.store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
        }
    }

    /// 18:00 on the suggested weekday of this week; if that has passed, the next full hour today.
    private func startDate() -> Date {
        let days = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = berlin
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = berlin
        let monday = week.flatMap { parser.date(from: $0) } ?? cal.startOfDay(for: .now)
        let offset = days.firstIndex(of: item.day) ?? 0
        let day = cal.date(byAdding: .day, value: offset, to: monday) ?? .now
        let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        if evening > .now { return evening }
        let next = cal.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return cal.date(bySetting: .minute, value: 0, of: next) ?? next
    }
}

/// Tab for a live talk with the coach at any time: one orb, tap it and talk.
struct TalkView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let active = model.call.active
        Screen {
            VStack(spacing: Space.section) {
                Spacer()
                Button {
                    Haptics.tap()
                    Task { await model.call.start(model.api, focus: "help") }
                } label: {
                    CoachOrb(active: active)
                }
                .buttonStyle(OrbPress())
                .accessibilityLabel("Mit Clara sprechen, deinem KI-Coach")
                .appear(0)
                Text("Clara · dein KI-Coach")
                    .font(.note.weight(.semibold))
                    .foregroundStyle(Ink.dawn)
                Text(active ? "Clara hört zu. Du kannst die App weiter nutzen." : "Antippen und mit Clara reden")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.center)
                    .id(active)
                    .transition(.opacity)
                    .appear(1)
                Spacer()
                Spacer() // sits the orb a little above centre, clear of the coach bar
            }
            .padding(.horizontal, Space.page)
            .frame(maxWidth: .infinity)
            .animation(Motion.smooth, value: active)
        }
    }
}

/// A section of the planning tab that folds open and shut.
struct Fold<Content: View>: View {
    let title: String
    var subtitle: String?
    @State var open = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { open.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(title).font(.sectionTitle)
                        if let subtitle {
                            Text(subtitle)
                                .font(.note)
                                .foregroundStyle(Ink.muted)
                                .contentTransition(.numericText())
                                .animation(Motion.smooth, value: subtitle)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(open ? "Einklappen" : "Aufklappen")
            if open {
                VStack(alignment: .leading, spacing: Space.s) { content }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// A slowly breathing, turning orb in the app's dawn colours. While a talk runs it grows a little
/// and soft rings ripple outwards.
private struct CoachOrb: View {
    var active = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let breath = 1 + 0.035 * sin(t * 1.3)
            ZStack {
                // Soft halo.
                Circle()
                    .fill(Ink.dawn.opacity(0.18))
                    .frame(width: 260, height: 260)
                    .scaleEffect(1 + 0.06 * sin(t * 1.3 + 0.8))
                    .blur(radius: 30)
                // Ripples while talking: two rings, half a period apart.
                ForEach(0..<2, id: \.self) { i in
                    let p = (t / 2.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(Ink.dawn.opacity(0.45 * (1 - p)), lineWidth: 1.5)
                        .frame(width: 200, height: 200)
                        .scaleEffect(1 + 0.32 * p)
                }
                .opacity(active ? 1 : 0)
                // Body: a turning angular gradient, softened.
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [Ink.dawn, Color(red: 0.98, green: 0.55, blue: 0.30), Color(red: 0.80, green: 0.38, blue: 0.55), Ink.dawn],
                            center: .center,
                            angle: .radians(t * 0.35)
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 6)
                // Inner light drifting around the centre.
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 90, height: 90)
                    .offset(x: 26 * cos(t * 0.7), y: 20 * sin(t * 0.9))
                    .blur(radius: 26)
                    .blendMode(.plusLighter)
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    .frame(width: 200, height: 200)
            }
            .scaleEffect(breath)
            .compositingGroup()
        }
        .scaleEffect(active ? 1.05 : 1)
        .animation(Motion.gentle, value: active)
        .frame(width: 280, height: 280)
    }
}

private struct OrbPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}
