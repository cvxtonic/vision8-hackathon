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

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow("Profil")
                    Text("Was dein Coach über dich weiß.").font(.display(28))

                    FileRow()

                    Card {
                        Toggle(isOn: $reminders) {
                            Text("Erinnerungen am Tag").font(.system(.headline, design: .rounded))
                        }
                        .onChange(of: reminders) { _, on in
                            Task {
                                if on {
                                    if !(await Notifications.schedule(times)) {
                                        reminders = false
                                        error = "Mitteilungen sind in den iOS-Einstellungen für Vision 8 ausgeschaltet."
                                    }
                                } else {
                                    Notifications.cancelAll()
                                }
                            }
                        }
                        if reminders {
                            ForEach(Array(times.enumerated()), id: \.offset) { index, value in
                                HStack {
                                    DatePicker("Erinnerung \(index + 1)", selection: Binding(get: { date(value) }, set: { setTime(index, minutes($0)) }), displayedComponents: .hourAndMinute)
                                        .font(.system(.subheadline, design: .rounded))
                                    Button {
                                        removeTime(index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill").foregroundStyle(Ink.drift)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Erinnerung um \(clock(value)) entfernen")
                                }
                            }
                            if times.count < 8 {
                                Button { addTime() } label: { Label("Erinnerung hinzufügen", systemImage: "plus") }
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Ink.dawn)
                                    .frame(minHeight: 44)
                            }
                        }
                    }

                    Card {
                        Text("Abend-Anruf").font(.system(.headline, design: .rounded))
                        Text("Dein Coach ruft dich zur gewählten Zeit an und fragt nach, wie dein Tag lief. Es spricht eine KI. Ohne Nummer gibt es keinen Anruf.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Ink.muted)
                        TextField("+49 170 1234567", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .font(.system(.body, design: .rounded))
                            .padding(14)
                            .background(Ink.night, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityLabel("Telefonnummer mit Ländervorwahl")
                        DatePicker("Uhrzeit", selection: Binding(get: { date(callTime) }, set: { callTime = quarter(minutes($0)) }), displayedComponents: .hourAndMinute)
                            .font(.system(.subheadline, design: .rounded))
                        HStack(spacing: 6) {
                            ForEach(Array(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"].enumerated()), id: \.offset) { index, name in
                                let day = index + 1
                                let on = days.contains(day)
                                Button(name) {
                                    Haptics.tap()
                                    if on { days.remove(day) } else { days.insert(day) }
                                }
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(on ? Ink.dawn : Ink.night, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(on ? Ink.night : Ink.muted)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        Button(saved ? "Gespeichert" : "Speichern") { Task { await saveContact() } }
                            .buttonStyle(PressStyle(filled: false))
                            .disabled(!phone.isEmpty && normalizedPhone == nil)
                        if let contact = model.state?.contact, contact.phone != nil {
                            if calling {
                                CoachThinking(text: "Der Coach wählt")
                            } else {
                                Button("Jetzt anrufen lassen") { Task { await callNow() } }
                                    .buttonStyle(PressStyle())
                            }
                            if let callNote {
                                Text(callNote)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(Ink.good)
                            }
                        }
                    }

                    if let error { ErrorNote(text: error) }

                    Button("Alle meine Daten löschen", role: .destructive) { confirmDelete = true }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Ink.drift)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(24)
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
                Task {
                    do { try await model.reset() } catch { self.error = error.localizedDescription }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
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
        times.append(min((times.max() ?? 12 * 60) + 60, 22 * 60))
        persistTimes()
    }

    private func removeTime(_ index: Int) {
        times.remove(at: index)
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
            saved = true
            await model.refresh()
            try? await Task.sleep(for: .seconds(2))
            saved = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
