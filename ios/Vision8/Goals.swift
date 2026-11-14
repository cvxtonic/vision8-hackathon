import SwiftUI

struct GoalsView: View {
    @Environment(AppModel.self) private var model
    @State private var changing: Goal?
    @State private var error: String?

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow("Dein Zielvertrag")
                    if let profile = model.state?.profile {
                        Text(profile.vision).font(.display(22)).lineSpacing(3)
                        ValueChips(values: profile.values)
                    }
                    if let pending = model.state?.pendingChange {
                        PendingCard(pending: pending) { confirm in
                            Task { await resolve(pending, confirm: confirm) }
                        }
                    }
                    if let error { ErrorNote(text: error) }
                    ForEach(model.state?.goals ?? [], id: \.key) { goal in
                        VStack(alignment: .leading, spacing: 6) {
                            GoalCard(goal: goal)
                            if model.state?.pendingChange == nil {
                                Button("Änderung beantragen") { changing = goal }
                                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Ink.muted)
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .refreshable { await model.refresh() }
        }
        .sheet(item: Binding(get: { changing.map(ChangeTarget.init) }, set: { changing = $0?.goal })) { target in
            ChangeSheet(goal: target.goal)
        }
    }

    private func resolve(_ pending: PendingChange, confirm: Bool) async {
        do {
            try await model.api.resolveChange(id: pending.id, confirm: confirm)
            error = nil
            await model.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ChangeTarget: Identifiable {
    let goal: Goal
    var id: String { goal.key }
}

private struct PendingCard: View {
    let pending: PendingChange
    var resolve: (Bool) -> Void

    var body: some View {
        let ready = pending.effectiveDate <= .now
        Card {
            Eyebrow(ready ? "Bedenkzeit vorbei" : "In Bedenkzeit")
            Text("Neuer Wunsch: \(pending.proposed)").font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(pending.coach_reply).font(.system(.subheadline, design: .serif))
            if !ready {
                Text("Bestätigen möglich ab \(pending.effectiveDate.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "de_DE")))).")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Ink.muted)
            }
            HStack(spacing: 10) {
                Button("Beim Ziel bleiben") { resolve(false) }.buttonStyle(PressStyle())
                Button("Ändern") { resolve(true) }.buttonStyle(PressStyle(filled: false)).disabled(!ready)
            }
        }
    }
}

private struct ChangeSheet: View {
    let goal: Goal
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var proposed = ""
    @State private var reason = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ziel ändern").font(.display(26))
                    Text("Dein Ziel ist bewusst fest, damit ein schlechter Tag es nicht kippt. Eine Änderung braucht einen Grund und 48 Stunden Bedenkzeit.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Ink.muted)
                    Card {
                        Eyebrow("Bisher · \(goal.horizonLabel)")
                        Text(goal.title).font(.system(.body, design: .serif))
                    }
                    field("Neues Ziel in einem Satz", text: $proposed)
                    field("Warum willst du es ändern?", text: $reason)
                    if let error { ErrorNote(text: error) }
                    if busy {
                        CoachThinking()
                    } else {
                        Button("Bedenkzeit starten") { Task { await submit() } }
                            .buttonStyle(PressStyle())
                            .disabled(proposed.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                        Button("Abbrechen") { dismiss() }.buttonStyle(PressStyle(filled: false))
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical)
            .lineLimit(2...5)
            .font(.system(.body, design: .rounded))
            .padding(14)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.line))
    }

    private func submit() async {
        guard let id = goal.id else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.api.requestChange(goalId: id, proposed: String(proposed.prefix(160)), reason: String(reason.prefix(800)))
            Haptics.warning()
            await model.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
