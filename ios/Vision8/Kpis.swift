import SwiftUI

let goodDay = 70

/// A progress ring with an optional number in the middle.
struct Ring: View {
    let progress: Double
    var size: CGFloat = 64
    var line: CGFloat = 6
    var label: String?

    var body: some View {
        ZStack {
            Circle().stroke(Ink.line, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(progress >= 1 ? Ink.good : Ink.dawn, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label { Text(label).font(.system(size: size * 0.3, weight: .bold, design: .rounded)) }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: progress)
    }
}

/// Top of "Heute": the one day score.
struct DayScoreCard: View {
    @Environment(AppModel.self) private var model

    private var score: Int { model.state?.dayScore ?? 0 }
    private var open: Int { (model.state?.list ?? []).filter { !$0.done }.count }

    var body: some View {
        Card {
            HStack(spacing: 16) {
                Ring(progress: Double(score) / 100, label: "\(score)")
                    .contentTransition(.numericText(value: Double(score)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dein Tag").font(.system(.headline, design: .rounded))
                    Text(subline)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subline: String {
        if score >= 100 { return "Alles geschafft" }
        if score >= goodDay { return open > 0 ? "Guter Tag · noch \(open) offen" : "Guter Tag" }
        if model.state?.list == nil { return "Dein Coach stellt deinen Tag zusammen" }
        return open == 1 ? "Noch 1 Eintrag offen" : "Noch \(open) Einträge offen"
    }
}

/// The KPIs grouped by life area; each area folds open and shut.
struct AreaList: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []
    @State private var didOpenMain = false
    @State private var error: String?
    @State private var entering: Kpi?
    @State private var adding: Area?
    /** The to-do just added that the person wants to talk through with the coach. */
    @State private var talkAbout: TalkTopic?
    @State private var suggesting: String?

    private var kpis: [Kpi] { model.state?.kpis ?? [] }
    private var values: [String: Double] { model.state?.kpiToday ?? [:] }
    private var mainArea: String { model.state?.area ?? "karriere" }

    /// The five life areas shown on Heute (plus the main area, should it be another), the main area first.
    private static let shown = ["karriere", "gesundheit", "finanzen", "beziehungen", "persoenlichkeit"]

    private var areas: [(area: Area, kpis: [Kpi])] {
        let grouped = Dictionary(grouping: kpis) { $0.area ?? mainArea }
        let ids = [mainArea] + Self.shown.filter { $0 != mainArea }
        return ids.compactMap { id in Area.all.first { $0.id == id }.map { ($0, grouped[id] ?? []) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(areas, id: \.area.id) { entry in areaRow(entry.area, entry.kpis) }
            if let error { ErrorNote(text: error) }
        }
        .task { await syncHealth() }
        .onAppear {
            if !didOpenMain {
                expanded.insert(mainArea)
                didOpenMain = true
            }
        }
        .sheet(item: $entering) { kpi in
            KpiEntry(kpi: kpi, value: values[kpi.id]) { value in
                entering = nil
                Task { await log(kpi, value) }
            }
            .presentationDetents([.height(300)])
        }
        .onChange(of: talkAbout?.id) { _, topic in
            if let topic { Task { await model.call.start(model.api, focus: "todo", topic: topic) } }
            talkAbout = nil
        }
        .sheet(item: $adding) { area in
            NewKpi(area: area) { name, talk in
                adding = nil
                Task {
                    await run { try await model.api.addKpi(area: area.id, name: name) }
                    if talk, error == nil { talkAbout = TalkTopic(id: "\(area.title): \(name)") }
                }
            }
            .presentationDetents([.height(340)])
        }
    }

    private struct TalkTopic: Identifiable { let id: String }

    private func areaRow(_ area: Area, _ items: [Kpi]) -> some View {
        let open = expanded.contains(area.id)
        let done = items.filter { values[$0.id].map($0.met) ?? false }.count
        return VStack(spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if open { expanded.remove(area.id) } else { expanded.insert(area.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: area.symbol).foregroundStyle(Ink.muted).frame(width: 22)
                    Text(area.title).font(.system(.body, design: .rounded).weight(.semibold))
                    Spacer()
                        if items.isEmpty {
                        Text("noch leer").font(.caption).foregroundStyle(Ink.muted)
                    } else {
                        Ring(progress: Double(done) / Double(items.count), size: 30, line: 4)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(area.title), \(done) von \(items.count) erreicht")
            .accessibilityHint(open ? "Einklappen" : "Aufklappen")
            if open {
                VStack(spacing: 0) {
                    ForEach(items) { kpi in kpiRow(kpi) }
                    if items.isEmpty {
                        Text("Noch keine To-dos. Lege fest, was du in diesem Bereich jeden Tag tun willst.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Ink.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    if suggesting == area.id {
                        CoachThinking(text: "Der Coach schlägt etwas vor").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        HStack(spacing: 16) {
                            if items.isEmpty {
                                Button("Coach vorschlagen lassen") {
                                    suggesting = area.id
                                    Task {
                                        await run { try await model.api.suggestKpis(area: area.id) }
                                        suggesting = nil
                                    }
                                }
                            }
                            Button { adding = area } label: { Label(items.isEmpty ? "Selbst festlegen" : "To-do hinzufügen", systemImage: "plus") }
                            Spacer()
                        }
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Ink.dawn)
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.line))
    }

    private func kpiRow(_ kpi: Kpi) -> some View {
        let value = values[kpi.id]
        let met = value.map(kpi.met) ?? false
        return SwipeRow(done: { Task { await complete(kpi) } }, delete: { Task { await run { try await model.api.removeKpi(id: kpi.id) } } }) {
          Button { tap(kpi) } label: {
            HStack(spacing: 10) {
                Image(systemName: met ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(met ? Ink.good : Ink.muted)
                Text(kpi.name).font(.system(.subheadline, design: .rounded))
                if kpi.source != "manual" {
                    Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Ink.muted).accessibilityLabel("aus der Health-App")
                }
                Spacer()
                Text(display(kpi, value))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(met ? Ink.good : Ink.muted)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: 1) }
        }
          .buttonStyle(.plain)
          .accessibilityHint(kpi.direction == "check" ? "Antippen zum Abhaken. Nach rechts wischen: erledigt, nach links: löschen." : "Antippen zum Eintragen. Nach rechts wischen: erledigt, nach links: löschen.")
        }
    }

    /// Swipe right: done. A yes/no to-do is ticked; one with a number is set to its daily target.
    private func complete(_ kpi: Kpi) async {
        guard !(values[kpi.id].map(kpi.met) ?? false) else { return }
        await log(kpi, kpi.source == "manual" ? 1 : kpi.target)
    }

    private func run(_ work: () async throws -> Void) async {
        error = nil
        do {
            try await work()
            await model.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// "6.200 / 8.000", "82,4 kg", "erledigt", "offen".
    private func display(_ kpi: Kpi, _ value: Double?) -> String {
        let fmt = { (n: Double) in n.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE"))) }
        if kpi.source == "manual" || kpi.direction == "check" { return (value ?? 0) >= 1 ? "erledigt" : "offen" }
        guard let value else { return "– / \(fmt(kpi.target))" }
        return kpi.direction == "atMost" ? "\(fmt(value)) \(kpi.unit)" : "\(fmt(value)) / \(fmt(kpi.target))"
    }

    private func tap(_ kpi: Kpi) {
        Haptics.tap()
        if kpi.source == "manual" {
            Task { await log(kpi, (values[kpi.id] ?? 0) >= 1 ? 0 : 1) }
        } else {
            entering = kpi
        }
    }

    private func log(_ kpi: Kpi, _ value: Double) async {
        error = nil
        let before = model.state?.dayScore ?? 0
        model.state?.kpiToday?[kpi.id] = value // optimistic
        do {
            try await model.api.logKpi(id: kpi.id, value: value)
            await model.refresh()
            if (model.state?.dayScore ?? 0) > before { Haptics.success() }
        } catch {
            self.error = error.localizedDescription
            await model.refresh()
        }
    }

    /// Health-backed KPIs fill themselves when the screen appears.
    private func syncHealth() async {
        let linked = kpis.filter { $0.source != "manual" }
        guard !linked.isEmpty, await Health.authorize() else { return }
        var changed = false
        for kpi in linked {
            guard let value = await Health.today(kpi.source), value != values[kpi.id] else { continue }
            try? await model.api.logKpi(id: kpi.id, value: value)
            changed = true
        }
        if changed { await model.refresh() }
    }
}

/// A row that can be swiped right (done, green) or left (delete, red), like the system lists.
struct SwipeRow<Content: View>: View {
    var done: () -> Void
    var delete: () -> Void
    @ViewBuilder var content: Content
    @State private var offset: CGFloat = 0
    private let threshold: CGFloat = 90

    var body: some View {
        ZStack {
            HStack {
                Image(systemName: "checkmark").opacity(offset > 20 ? 1 : 0)
                Spacer()
                Image(systemName: "trash").opacity(offset < -20 ? 1 : 0)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Ink.night)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(offset > 0 ? Ink.good : offset < 0 ? Ink.drift : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            content
                .background(Ink.surface)
                .offset(x: offset)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    offset = value.translation.width
                }
                .onEnded { value in
                    let width = value.translation.width
                    if width > threshold {
                        Haptics.success()
                        done()
                    } else if width < -threshold {
                        Haptics.warning()
                        delete()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                }
        )
        .accessibilityAction(named: "Erledigt", done)
        .accessibilityAction(named: "Löschen", delete)
    }
}

/// The person adds a daily to-do to a life area: just what to do.
private struct NewKpi: View {
    let area: Area
    /** name, and whether to talk it through with the coach right away. */
    var save: (String, Bool) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(area.title)
                Text("Neues To-do").font(.display(26))
                TextField("Was willst du jeden Tag tun?", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if !cleaned.isEmpty { save(cleaned, false) } }
                    .font(.system(.body, design: .rounded))
                    .padding(14)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.line))
                Button {
                    save(cleaned, true)
                } label: {
                    Label("Speichern und mit Coach besprechen", systemImage: "waveform")
                }
                .buttonStyle(PressStyle())
                .disabled(cleaned.isEmpty)
                Button("Nur speichern") { save(cleaned, false) }
                    .buttonStyle(PressStyle(filled: false))
                    .disabled(cleaned.isEmpty)
            }
            .padding(24)
        }
        .onAppear { focused = true }
    }
}

struct KpiEntry: View {
    let kpi: Kpi
    let value: Double?
    var save: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow("Heute eintragen")
                Text(kpi.name).font(.display(26))
                HStack {
                    TextField("0", text: $text)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(kpi.unit).font(.system(.title3, design: .rounded)).foregroundStyle(Ink.muted)
                }
                .padding(16)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Speichern") { if let parsed { save(parsed) } }
                    .buttonStyle(PressStyle())
                    .disabled(parsed == nil)
            }
            .padding(24)
        }
        .onAppear {
            if let value { text = value.formatted(.number.grouping(.never).locale(Locale(identifier: "de_DE"))) }
            focused = true
        }
    }
}
