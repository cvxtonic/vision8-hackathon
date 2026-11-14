import SwiftUI

/// The vision board: the AI picture of the person's vision, the vision in their words, why it matters,
/// their values, the beliefs they rewrote with the coach, and the path from ten years down to this month.
struct VisionView: View {
    @Environment(AppModel.self) private var model
    @State private var painting = false
    @State private var error: String?
    @State private var editing = false

    private var profile: Profile? { model.state?.profile }
    private var goals: [Goal] { model.state?.goals ?? [] }

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    Page {
                        if let profile {
                            Text(profile.vision)
                                .font(.system(size: 21, weight: .regular, design: .serif)) // long text reads lighter than a title
                                .lineSpacing(Space.xs - 2)
                                .fixedSize(horizontal: false, vertical: true)
                                .appear(1)
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Eyebrow("Dein Warum")
                                Text(profile.why).font(.quote).foregroundStyle(Ink.paper.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                            }
                            .appear(2)
                            ValueChips(values: profile.values).appear(3)
                        }
                        if !newBeliefs.isEmpty {
                            VStack(alignment: .leading, spacing: Space.s) {
                                Eyebrow("Was du heute über dich glaubst")
                                ForEach(newBeliefs, id: \.self) { belief in
                                    HStack(alignment: .top, spacing: Space.s) {
                                        Capsule().fill(Ink.dawn).frame(width: 3)
                                        Text(belief).font(.quote).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .appear(4)
                        }
                        if !steps.isEmpty { path.appear(5) }
                        if let error { ErrorNote(text: error).transition(.opacity) }
                        HStack(spacing: Space.page) {
                            Button { Task { await paint(fresh: true) } } label: { Label("Neues Bild", systemImage: "sparkles") }
                                .disabled(painting)
                            Button { editing = true } label: { Label("Ziele ändern", systemImage: "pencil") }
                            Spacer()
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Ink.muted)
                        .frame(minHeight: 44)
                        .appear(6)
                    }
                    .animation(Motion.smooth, value: error)
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await model.refresh() }
        }
        .task { if model.state?.board == nil, !painting { await paint(fresh: false) } }
        .sheet(isPresented: $editing) { GoalsView() }
        // A new picture arrived (not the first load).
        .sensoryFeedback(trigger: model.state?.board?.image) { old, new in old != nil && new != nil && old != new ? .success : nil }
    }

    /// The picture, fading into the page, with the caption on top of its lower edge.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let board = model.state?.board, let url = URL(string: board.image) {
                    AsyncImage(url: url, transaction: Transaction(animation: Motion.gentle)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill().transition(.opacity)
                        case .failure:
                            Ink.surface
                        default:
                            Skeleton(height: 460)
                        }
                    }
                    .id(board.image) // a new picture fades in again
                } else {
                    Skeleton(height: 460)
                        .overlay { if painting { CoachThinking(text: "Dein Vision Board entsteht") } }
                }
            }
            .frame(height: 460)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(LinearGradient(colors: [Ink.night.opacity(0.35), .clear, .clear, Ink.night.opacity(0.75), Ink.night], startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Eyebrow("Deine Vision")
                if let caption = model.state?.board?.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.pageTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.xs)
            .animation(Motion.smooth, value: model.state?.board?.caption)
            .appear(0)
        }
    }

    private var steps: [Goal] {
        ["10y", "3y", "1y", "month"].compactMap { h in goals.first { $0.horizon == h } }
    }

    /// Ten years down to this month, as a line of milestones; this month is the lit one.
    private var path: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Dein Weg dorthin")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, goal in
                    let last = index == steps.count - 1
                    HStack(alignment: .top, spacing: Space.m) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(last ? Ink.dawn : Ink.night)
                                .overlay(Circle().strokeBorder(last ? Ink.dawn : Ink.dawn.opacity(0.6), lineWidth: 1.5))
                                .frame(width: 12, height: 12)
                                .shadow(color: last ? Ink.dawn.opacity(0.6) : .clear, radius: 6)
                                .padding(.top, Space.xxs)
                            if !last {
                                Rectangle().fill(Ink.dawn.opacity(0.25)).frame(width: 1).frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 12)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text("\(goal.horizonLabel) · bis \(germanDate(goal.deadline))")
                                .font(.label)
                                .kerning(0.6)
                                .foregroundStyle(last ? Ink.dawn : Ink.muted)
                            Text(goal.title)
                                .font(.system(.body, design: .serif).weight(.medium))
                                .foregroundStyle(last ? Ink.paper : Ink.paper.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, last ? 0 : Space.page)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Beliefs the person reworded with the coach, from the file ("neu gefasst: „…“").
    private var newBeliefs: [String] {
        guard let file = model.state?.file else { return [] }
        var inBeliefs = false
        var out: [String] = []
        for line in file.split(separator: "\n").map(String.init) {
            if !line.hasPrefix("- ") { inBeliefs = line.trimmingCharacters(in: .whitespaces) == "Glaubenssätze"; continue }
            guard inBeliefs, let range = line.range(of: "neu gefasst:") else { continue }
            let sentence = line[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " )]\"„“"))
            if !sentence.isEmpty { out.append(sentence) }
        }
        return Array(out.prefix(3))
    }

    private func paint(fresh: Bool) async {
        painting = true
        error = nil
        defer { painting = false }
        do {
            let board = try await model.api.board(fresh: fresh)
            withAnimation(Motion.smooth) { model.state?.board = board }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

