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

    var body: some View {
        Fold(title: "Diese Woche", subtitle: plan.map { "\($0.items.filter(\.done).count) von \($0.items.count) erledigt" }) {
            weekContent
        }
        .task { if plan == nil, !busy { await load(fresh: false) } }
        .sheet(item: $calendarItem) { item in
            CalendarSheet(item: item, week: plan?.week).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var weekContent: some View {
                                if let plan {
                        Card {
                            Eyebrow("Worum es diese Woche geht")
                            Text(plan.focus).font(.quote)
                            ProgressView(value: Double(plan.items.filter(\.done).count), total: Double(max(plan.items.count, 1)))
                                .tint(Ink.good)
                        }
                        ForEach(plan.items) { item in
                            WeekRow(item: item, toggle: { Task { await toggle(item) } }, addToCalendar: { calendarItem = item })
                        }
                        if busy {
                            CoachThinking(text: "Der Coach plant neu")
                        } else {
                            Button("Offene To-dos neu planen lassen") { Task { await load(fresh: true) } }
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Ink.muted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    } else if busy {
                        CoachThinking(text: "Dein Coach plant deine Woche")
                            .padding(.top, 24)
                    } else {
                        Text("Dein Coach macht aus deinem Zielvertrag konkrete Schritte für diese Woche.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Ink.muted)
                        Button("Woche planen lassen") { Task { await load(fresh: false) } }.buttonStyle(PressStyle())
                    }
                    if let error { ErrorNote(text: error) }
    }

    private var weekLabel: String {
        let cal = Calendar(identifier: .iso8601)
        return "Kalenderwoche \(cal.component(.weekOfYear, from: .now))"
    }

    private func load(fresh: Bool) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let week = try await model.api.week(fresh: fresh)
            Haptics.success()
            withAnimation { model.state?.week = week }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggle(_ item: WeekItem) async {
        Haptics.tap()
        guard let index = plan?.items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation { model.state?.week?.items[index].done.toggle() } // optimistic
        do {
            let week = try await model.api.checkWeek(id: item.id, done: !item.done)
            model.state?.week = week
        } catch {
            withAnimation { model.state?.week?.items[index].done = item.done }
            self.error = error.localizedDescription
        }
    }
}

private struct WeekRow: View {
    let item: WeekItem
    var toggle: () -> Void
    var addToCalendar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.done ? Ink.good : Ink.muted)
                    .frame(minWidth: 44, minHeight: 44, alignment: .top)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Erledigt, antippen zum Zurücksetzen" : "Als erledigt markieren")
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .strikethrough(item.done, color: Ink.muted)
                Text(item.why)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Ink.muted)
                HStack(spacing: 10) {
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
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.line))
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
        Screen {
            VStack(spacing: 28) {
                Spacer()
                Button {
                    Haptics.tap()
                    Task { await model.call.start(model.api, focus: "help") }
                } label: {
                    CoachOrb()
                }
                .buttonStyle(OrbPress())
                .accessibilityLabel("Mit deinem Coach sprechen")
                Text(model.call.active ? "Dein Coach hört zu. Du kannst die App weiter nutzen." : "Antippen und losreden")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Ink.muted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { open.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.display(22))
                        if let subtitle {
                            Text(subtitle).font(.system(.footnote, design: .rounded)).foregroundStyle(Ink.muted)
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
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Einklappen" : "Aufklappen")
            if open {
                VStack(alignment: .leading, spacing: 12) { content }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Ink.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Ink.line))
    }
}

/// A slowly breathing, turning orb in the app's dawn colours.
private struct CoachOrb: View {
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
        .frame(width: 280, height: 280)
    }
}

private struct OrbPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
