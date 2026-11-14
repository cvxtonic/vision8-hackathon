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
                    VStack(alignment: .leading, spacing: 22) {
                        if let profile {
                            Text(profile.vision)
                                .font(.display(26))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow("Dein Warum")
                                Text(profile.why).font(.quote).fixedSize(horizontal: false, vertical: true)
                            }
                            ValueChips(values: profile.values)
                        }
                        if !newBeliefs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow("Was du heute über dich glaubst")
                                ForEach(newBeliefs, id: \.self) { belief in
                                    HStack(alignment: .top, spacing: 12) {
                                        Capsule().fill(Ink.dawn).frame(width: 3)
                                        Text(belief).font(.quote).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        path
                        if let error { ErrorNote(text: error) }
                        HStack(spacing: 18) {
                            Button { Task { await paint(fresh: true) } } label: { Label("Neues Bild", systemImage: "sparkles") }
                                .disabled(painting)
                            Button { editing = true } label: { Label("Ziele ändern", systemImage: "pencil") }
                            Spacer()
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Ink.muted)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await model.refresh() }
        }
        .task { if model.state?.board == nil, !painting { await paint(fresh: false) } }
        .sheet(isPresented: $editing) { GoalsView() }
    }

    /// The picture, fading into the page, with the caption on top of its lower edge.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let board = model.state?.board, let url = URL(string: board.image) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.6))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Ink.surface
                        }
                    }
                } else {
                    ZStack {
                        Ink.surface
                        if painting { CoachThinking(text: "Dein Vision Board entsteht") }
                    }
                }
            }
            .frame(height: 460)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(LinearGradient(colors: [.clear, .clear, Ink.night.opacity(0.75), Ink.night], startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Deine Vision")
                if let caption = model.state?.board?.caption, !caption.isEmpty {
                    Text(caption).font(.display(22)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
    }

    /// Ten years down to this month, as a line of milestones.
    private var path: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Dein Weg dorthin").padding(.bottom, 12)
            let order = ["10y", "3y", "1y", "month"]
            let steps = order.compactMap { h in goals.first { $0.horizon == h } }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, goal in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == steps.count - 1 ? Ink.dawn : Ink.surface)
                            .overlay(Circle().strokeBorder(Ink.dawn, lineWidth: 2))
                            .frame(width: 14, height: 14)
                            .padding(.top, 3)
                        if index < steps.count - 1 {
                            Rectangle().fill(Ink.dawn.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(goal.horizonLabel) · bis \(germanDate(goal.deadline))")
                            .font(.label)
                            .foregroundStyle(Ink.muted)
                        Text(goal.title)
                            .font(.system(.body, design: .serif).weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 18)
                }
                .accessibilityElement(children: .combine)
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
            withAnimation { model.state?.board = board }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
