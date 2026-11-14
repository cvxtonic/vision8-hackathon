import SwiftUI

let goodDay = 70

/// STYLEGUIDE: list rows sit 14 pt from the card edge.
private let rowInset: CGFloat = 14
private let cardShape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)

/// A progress ring with an optional number in the middle.
struct Ring: View {
    let progress: Double
    var size: CGFloat = 64
    var line: CGFloat = 6
    var label: String?
    /** Fill colour; nil = dawn while running, good when full. */
    var tint: Color? = nil

    var body: some View {
        ZStack {
            Circle().stroke(tint.map { $0.opacity(0.2) } ?? Ink.line, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint ?? (progress >= 1 ? Ink.good : Ink.dawn), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label {
                Text(label)
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: progress))
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.smooth, value: progress)
    }
}

/// The day score as one ring made of coloured parts: the priorities (dawn) and each life area in its own colour.
/// Each part's length is its weight in the score; its filled share is what is done.
struct SegmentedRing: View {
    struct Part: Identifiable {
        let id: String
        let color: Color
        let total: Double
        let done: Double
    }

    let parts: [Part]
    var size: CGFloat = 64
    var line: CGFloat = 6
    var label: String

    var body: some View {
        let sum = parts.reduce(0) { $0 + $1.total }
        let gap = parts.count > 1 ? 0.012 : 0
        ZStack {
            if sum == 0 {
                Circle().stroke(Ink.line, lineWidth: line)
            }
            ForEach(Array(spans(sum: sum).enumerated()), id: \.offset) { _, span in
                let from = span.start + gap / 2
                let to = max(from, span.end - gap / 2)
                Circle()
                    .trim(from: from, to: to)
                    .stroke(span.part.color.opacity(0.2), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: from, to: from + (to - from) * min(span.part.done / max(span.part.total, 0.001), 1))
                    .stroke(span.part.color, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Text(label)
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .animation(Motion.smooth, value: parts.map(\.done))
    }

    private func spans(sum: Double) -> [(part: Part, start: Double, end: Double)] {
        guard sum > 0 else { return [] }
        var start = 0.0
        return parts.map { part in
            let end = start + part.total / sum
            defer { start = end }
            return (part, start, end)
        }
    }
}

/// Top of "Heute": the one day score.
struct DayScoreCard: View {
    @Environment(AppModel.self) private var model

    private var score: Int { model.state?.dayScore ?? 0 }
    /// Same weights as the server's score: each to-do counts its points for today.
    private var parts: [SegmentedRing.Part] {
        let values = model.state?.kpiToday ?? [:]
        let main = model.state?.area ?? "karriere"
        let points = Dictionary((model.state?.list ?? []).compactMap { i in i.kpiId.map { ($0, Double(i.points ?? 4)) } }, uniquingKeysWith: { a, _ in a })
        let grouped = Dictionary(grouping: model.state?.kpis ?? []) { $0.area ?? main }
        return Area.all.compactMap { area in
            guard let items = grouped[area.id], !items.isEmpty else { return nil }
            let total = items.reduce(0) { $0 + (points[$1.id] ?? 4) }
            let done = items.filter { kpi in values[kpi.id].map(kpi.met) ?? false }.reduce(0) { $0 + (points[$1.id] ?? 4) }
            return .init(id: area.id, color: area.color, total: total, done: done)
        }
    }

    /// Open priorities plus open area habits.
    private var open: Int {
        let values = model.state?.kpiToday ?? [:]
        return (model.state?.kpis ?? []).filter { kpi in !(values[kpi.id].map(kpi.met) ?? false) }.count
    }

    var body: some View {
        Card {
            HStack(spacing: Space.m) {
                SegmentedRing(parts: parts, size: 60, line: 6, label: "\(score)")
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Dein Tag").font(.cardTitle)
                    Text(subline)
                        .font(.callout)
                        .foregroundStyle(Ink.muted)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                        .animation(Motion.smooth, value: subline)
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
    @State private var addingFree = false
    @State private var filed: String?
    /** The to-do just added that the person wants to talk through with the coach. */
    @State private var talkAbout: TalkTopic?
    @State private var suggesting: String?

    private var kpis: [Kpi] { model.state?.kpis ?? [] }
    private var values: [String: Double] { model.state?.kpiToday ?? [:] }
    private var ranks: [String: ListItem] {
        Dictionary((model.state?.list ?? []).compactMap { i in i.kpiId.map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
    }
    private func points(_ kpi: Kpi) -> Int { ranks[kpi.id]?.points ?? 4 }
    private func isTop(_ kpi: Kpi) -> Bool { ranks[kpi.id]?.quadrant == "now" }
    private var mainArea: String { model.state?.area ?? "karriere" }

    /// The five life areas shown on Heute (plus the main area, should it be another), the main area first.
    private static let shown = ["karriere", "gesundheit", "finanzen", "beziehungen", "persoenlichkeit"]

    private var areas: [(area: Area, kpis: [Kpi])] {
        let grouped = Dictionary(grouping: kpis.sorted { points($0) > points($1) }) { $0.area ?? mainArea }
        let ids = [mainArea] + Self.shown.filter { $0 != mainArea }
        return ids.compactMap { id in Area.all.first { $0.id == id }.map { ($0, grouped[id] ?? []) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(areas, id: \.area.id) { entry in areaRow(entry.area, entry.kpis) }
            Button { addingFree = true } label: {
                Label("Eigenes To-do – Clara sortiert es ein", systemImage: "wand.and.stars")
            }
            .buttonStyle(PressStyle(filled: false))
            .padding(.top, Space.xs)
            if let filed { Text(filed).font(.note).foregroundStyle(Ink.muted).transition(.opacity) }
            if let error { ErrorNote(text: error) }
        }
        .task { await syncHealth() }
        .onAppear {
            if !didOpenMain {
                expanded = Set(areas.map(\.area.id)) // every area starts open
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
        .sheet(isPresented: $addingFree) {
            NewKpi(area: nil) { name, talk in
                addingFree = false
                Task {
                    var landed: Area?
                    await run {
                        let id = try await model.api.addKpi(area: nil, name: name)
                        landed = Area.all.first { $0.id == id }
                    }
                    guard let landed, error == nil else { return }
                    expanded.insert(landed.id)
                    withAnimation(Motion.smooth) { filed = "Clara hat „\(name)“ in \(landed.title) einsortiert." }
                    if talk { talkAbout = TalkTopic(id: "\(landed.title): \(name)") }
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
                withAnimation(Motion.snappy) {
                    if open { expanded.remove(area.id) } else { expanded.insert(area.id) }
                }
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: area.symbol).foregroundStyle(area.color).frame(width: 22)
                    Text(area.title).font(.bodyText.weight(.semibold))
                    Spacer()
                    if items.isEmpty {
                        Text("noch leer").font(.note).foregroundStyle(Ink.muted)
                    } else {
                        Ring(progress: Double(done) / Double(items.count), size: 30, line: 4, tint: area.color)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, rowInset)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityLabel("\(area.title), \(done) von \(items.count) erreicht")
            .accessibilityHint(open ? "Einklappen" : "Aufklappen")
            if open {
                VStack(spacing: 0) {
                    ForEach(items) { kpi in kpiRow(kpi) }
                    if items.isEmpty {
                        Text("Noch keine To-dos. Lege fest, was du in diesem Bereich jeden Tag tun willst.")
                            .font(.note)
                            .foregroundStyle(Ink.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Space.xs)
                    }
                    if suggesting == area.id {
                        CoachThinking(text: "Der Coach schlägt etwas vor").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        HStack(spacing: Space.m) {
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
                        .font(.note.weight(.semibold))
                        .foregroundStyle(Ink.dawn)
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, rowInset)
                .padding(.bottom, Space.xxs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Ink.surface, in: cardShape)
        .clipShape(cardShape)
        .overlay(cardShape.strokeBorder(Ink.line))
    }

    private func kpiRow(_ kpi: Kpi) -> some View {
        let value = values[kpi.id]
        let met = value.map(kpi.met) ?? false
        let top = isTop(kpi) && !met
        return SwipeRow(done: { Task { await complete(kpi) } }, delete: { Task { await run { try await model.api.removeKpi(id: kpi.id) } } }) {
          Button { tap(kpi) } label: {
            HStack(spacing: Space.s) {
                Image(systemName: met ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(met ? Ink.good : Ink.muted)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: met)
                VStack(alignment: .leading, spacing: 2) {
                    if isTop(kpi) {
                        Label("Wichtigstes heute", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(met ? Ink.good : Ink.drift)
                    }
                    Text(kpi.name).font(isTop(kpi) ? .callout.weight(.semibold) : .callout)
                }
                if kpi.source != "manual" {
                    Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Ink.muted).accessibilityLabel("aus der Health-App")
                }
                Spacer()
                Text("+\(points(kpi))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(met ? Ink.good : (top ? Ink.drift : Ink.muted))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((met ? Ink.good : (top ? Ink.drift : Ink.muted)).opacity(0.14), in: Capsule())
                    .accessibilityLabel("\(points(kpi)) Punkte")
                Text(display(kpi, value))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(met ? Ink.good : Ink.muted)
                    .contentTransition(.numericText())
            }
            .frame(minHeight: top ? 56 : 44)
            .padding(.horizontal, top ? Space.xs : 0)
            .background(top ? Ink.drift.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(top ? Ink.drift : .clear, lineWidth: 2))
            .padding(.vertical, top ? Space.xxs : 0)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { if !top { Rectangle().fill(Ink.line).frame(height: 0.5) } }
            .animation(Motion.snappy, value: met)
            .animation(Motion.smooth, value: value)
        }
          .buttonStyle(RowPress())
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
            .padding(.horizontal, Space.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Rectangle: the surrounding card clips the corners.
            .background(offset > 0 ? Ink.good : offset < 0 ? Ink.drift : .clear)
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
                    withAnimation(Motion.snappy) { offset = 0 }
                }
        )
        .accessibilityAction(named: "Erledigt", done)
        .accessibilityAction(named: "Löschen", delete)
    }
}

/// The person adds a daily to-do to a life area: just what to do.
private struct NewKpi: View {
    /** nil: the coach picks the area. */
    let area: Area?
    /** name, and whether to talk it through with the coach right away. */
    var save: (String, Bool) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(area?.title ?? "Clara sortiert es ein")
                Text("Neues To-do").font(.sectionTitle).padding(.bottom, Space.xs)
                TextField("Was willst du jeden Tag tun?", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if !cleaned.isEmpty { save(cleaned, false) } }
                    .font(.bodyText)
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 52)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.line))
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
            .padding(.horizontal, Space.page)
            .padding(.top, Space.section)
            .frame(maxHeight: .infinity, alignment: .top)
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
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow("Heute eintragen")
                Text(kpi.name).font(.sectionTitle).padding(.bottom, Space.xs)
                HStack(alignment: .firstTextBaseline) {
                    TextField("0", text: $text)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(kpi.unit).font(.system(.title3, design: .rounded)).foregroundStyle(Ink.muted)
                }
                .padding(Space.m)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.line))
                Button("Speichern") { if let parsed { save(parsed) } }
                    .buttonStyle(PressStyle())
                    .disabled(parsed == nil)
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.section)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            if let value { text = value.formatted(.number.grouping(.never).locale(Locale(identifier: "de_DE"))) }
            focused = true
        }
    }
}
