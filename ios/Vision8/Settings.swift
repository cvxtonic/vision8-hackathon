import SwiftUI
import UserNotifications

/// Local reminders at the times the person picks. The times live on the device (UserDefaults).
enum Notifications {
    private static let key = "reminderTimes"
    /** Minutes after midnight; the defaults are morning, midday and evening. */
    static var times: [Int] {
        get { (UserDefaults.standard.array(forKey: key) as? [Int]) ?? [8 * 60, 13 * 60, 20 * 60] }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: key) }
    }

    private static let messages: [(title: String, body: String)] = [
        ("Dein Tag, deine Vision", "Was nimmst du dir heute vor? Lass den Coach prüfen, ob es einzahlt."),
        ("Kurzer Zwischenstand", "Bist du noch an dem dran, was heute zählt?"),
        ("Deine To-dos warten", "Ein kleiner Schritt reicht. Welcher ist es jetzt?"),
        ("Denk an dein Warum", "Du weißt, wofür du das machst. Hak heute etwas davon ab."),
    ]

    /// Asks for permission and schedules one daily reminder per time. False when notifications are off.
    static func schedule(_ times: [Int]) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        cancelAll()
        for (index, minutes) in times.sorted().enumerated() {
            let message = messages[index % messages.count]
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            var time = DateComponents()
            time.hour = minutes / 60
            time.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "reminder-\(minutes)", content: content, trigger: trigger))
        }
        return true
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("reminder-") || ["morning", "midday", "evening"].contains($0) })
        }
    }

    /// Like Duolingo: at 20:30 a nudge if the streak is not saved yet today. Never asks for permission itself.
    static func streak(days: Int, savedToday: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["streak"])
        guard !savedToday, days > 0, await center.notificationSettings().authorizationStatus == .authorized else { return }
        var time = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        time.hour = 20
        time.minute = 30
        guard let fire = Calendar.current.date(from: time), fire > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Dein Streak: \(days) \(days == 1 ? "Tag" : "Tage") 🔥"
        content.body = "Ein Haken auf deiner Liste oder ein kurzes Gespräch mit deinem Coach rettet ihn."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "streak", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: false)))
    }

    static func isEnabled() async -> Bool {
        !(await UNUserNotificationCenter.current().pendingNotificationRequests()).isEmpty
    }
}

/// "08:30" for minutes after midnight.
private func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

private func date(_ minutes: Int) -> Date {
    Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
}

private func minutes(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

/// Grouped settings surface: rows sit edge to edge, separated by hairlines.
private struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.line))
    }
}

/// One row in a `SettingsGroup`: at least 44 pt, hairline above inset to the text.
private struct SettingsRow<Content: View>: View {
    var separator = true
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: Space.s) { content }
            .font(.bodyText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xxs)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if separator {
                    Rectangle().fill(Ink.line).frame(height: 0.5).padding(.leading, Space.m)
                }
            }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var reminders = false
    @State private var phone = ""
    @State private var times = Notifications.times
    /** Minutes after midnight, in quarter hours (the call service checks every 15 minutes). */
    @State private var callTime = 20 * 60
    @State private var days: Set<Int> = Set(1...7)
    @State private var saved = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var calling = false
    @State private var callNote: String?

    private static let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    private static let rowTransition = AnyTransition.opacity.combined(with: .move(edge: .top))

    var body: some View {
        Screen {
            ScrollView {
                Page {
                    Text("Profil").font(.pageTitle)
                        .accessibilityAddTraits(.isHeader)
                        .appear(0)

                    FileRow().appear(1)

                    remindersSection.appear(2)

                    callSection.appear(3)

                    if let error {
                        ErrorNote(text: error).transition(Self.rowTransition)
                    }

                    Button("Alle meine Daten löschen", role: .destructive) { confirmDelete = true }
                        .font(.callout)
                        .foregroundStyle(Ink.drift.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, Space.s)
                        .appear(4)
                }
                .animation(Motion.smooth, value: error)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task {
            reminders = await Notifications.isEnabled()
            if let contact = model.state?.contact {
                phone = contact.phone ?? ""
                callTime = contact.callHour * 60 + (contact.callMinute ?? 0)
                days = Set(contact.days ?? Array(1...7))
            }
        }
        .confirmationDialog("Vision, Ziele und alle Tage werden endgültig gelöscht.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) {
                Haptics.warning()
                Task {
                    do { try await model.reset() } catch { self.error = error.localizedDescription }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "Erinnerungen")
            SettingsGroup {
                SettingsRow(separator: false) {
                    Toggle(isOn: $reminders.animation(Motion.smooth)) {
                        Text("Erinnerungen am Tag")
                    }
                    .tint(Ink.dawn)
                }
                .onChange(of: reminders) { _, on in
                    Task {
                        if on {
                            if !(await Notifications.schedule(times)) {
                                withAnimation(Motion.smooth) {
                                    reminders = false
                                    error = "Mitteilungen sind in den iOS-Einstellungen für Vision 8 ausgeschaltet."
                                }
                            }
                        } else {
                            Notifications.cancelAll()
                        }
                    }
                }
                if reminders {
                    ForEach(Array(times.enumerated()), id: \.offset) { index, value in
                        SettingsRow {
                            DatePicker("Erinnerung \(index + 1)", selection: Binding(get: { date(value) }, set: { setTime(index, minutes($0)) }), displayedComponents: .hourAndMinute)
                            Button {
                                removeTime(index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Ink.drift)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Erinnerung um \(clock(value)) entfernen")
                        }
                        .transition(Self.rowTransition)
                    }
                    if times.count < 8 {
                        Button { addTime() } label: {
                            SettingsRow {
                                Label("Erinnerung hinzufügen", systemImage: "plus")
                                    .foregroundStyle(Ink.dawn)
                            }
                        }
                        .buttonStyle(RowPress())
                        .transition(Self.rowTransition)
                    }
                }
            }
        }
    }

    private var callSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "Abend-Anruf", hint: "Dein Coach ruft dich zur gewählten Zeit an und fragt, wie dein Tag lief. Es spricht eine KI. Ohne Nummer gibt es keinen Anruf.")
            SettingsGroup {
                SettingsRow(separator: false) {
                    Text("Nummer")
                    TextField("+49 170 1234567", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Telefonnummer mit Ländervorwahl")
                }
                SettingsRow {
                    DatePicker("Uhrzeit", selection: Binding(get: { date(callTime) }, set: { callTime = quarter(minutes($0)) }), displayedComponents: .hourAndMinute)
                }
                SettingsRow {
                    HStack(spacing: Space.xs) {
                        ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { index, name in
                            let day = index + 1
                            let on = days.contains(day)
                            Button {
                                Haptics.tap()
                                withAnimation(Motion.snappy) {
                                    if on { days.remove(day) } else { days.insert(day) }
                                }
                            } label: {
                                Text(name)
                                    .font(.note.weight(.semibold))
                                    .foregroundStyle(on ? Ink.dawn : Ink.muted)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(on ? Ink.dawn.opacity(0.16) : Ink.night.opacity(0.6), in: Capsule())
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Space.xxs)
                }
            }

            Button(saved ? "Gespeichert" : "Speichern") { Task { await saveContact() } }
                .buttonStyle(PressStyle(filled: false))
                .disabled(!phone.isEmpty && normalizedPhone == nil)
                .padding(.top, Space.xxs)

            if let contact = model.state?.contact, contact.phone != nil {
                Group {
                    if calling {
                        CoachThinking(text: "Der Coach wählt")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    } else {
                        Button("Jetzt anrufen lassen") { Task { await callNow() } }
                            .buttonStyle(PressStyle())
                    }
                }
                .transition(.opacity)
                if let callNote {
                    Text(callNote)
                        .font(.note)
                        .foregroundStyle(Ink.good)
                        .frame(maxWidth: .infinity)
                        .transition(Self.rowTransition)
                }
            }
        }
        .animation(Motion.smooth, value: calling)
        .animation(Motion.smooth, value: callNote)
    }

    /// E.164, accepting spaces and a leading 0 for German numbers.
    private var normalizedPhone: String? {
        var digits = phone.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("00") { digits = "+" + digits.dropFirst(2) }
        if digits.hasPrefix("0") { digits = "+49" + digits.dropFirst() }
        guard digits.hasPrefix("+"), (9...16).contains(digits.count), !digits.dropFirst().contains("+") else { return nil }
        return digits
    }

    private func quarter(_ minutes: Int) -> Int { (minutes / 15) * 15 }

    private func setTime(_ index: Int, _ value: Int) {
        times[index] = value
        persistTimes()
    }

    private func addTime() {
        withAnimation(Motion.smooth) { times.append(min((times.max() ?? 12 * 60) + 60, 22 * 60)) }
        persistTimes()
    }

    private func removeTime(_ index: Int) {
        _ = withAnimation(Motion.smooth) { times.remove(at: index) }
        persistTimes()
    }

    /// Saves the reminder times and reschedules them right away.
    private func persistTimes() {
        Notifications.times = times
        Task { _ = await Notifications.schedule(times) }
    }

    private func callNow() async {
        calling = true
        callNote = nil
        defer { calling = false }
        do {
            try await model.api.callNow()
            error = nil
            Haptics.success()
            callNote = "Der Coach ruft dich gleich an."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveContact() async {
        do {
            let time = min(max(callTime, 8 * 60), 21 * 60 + 45) // the coach only calls between 8 and 22 o'clock
            try await model.api.saveContact(phone: phone.isEmpty ? nil : normalizedPhone, callHour: time / 60, callMinute: time % 60, days: days.sorted())
            error = nil
            Haptics.success()
            withAnimation(Motion.snappy) { saved = true }
            await model.refresh()
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Motion.snappy) { saved = false }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
