import SwiftUI

/// Row on the Coach tab that opens the file.
struct FileRow: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Deine Akte").font(.system(.headline, design: .rounded))
                        Text(model.state?.fileUpdatedAt.map { "Zuletzt ergänzt am \(germanDate($0))" } ?? "Was dein Coach über dich weiß")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Ink.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { FileView() }
    }
}

/// The coach's file on the person, section by section.
struct FileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private static let headings = ["Ausgangslage", "Werte", "Glaubenssätze", "Stolpersteine und Muster", "Was funktioniert", "Vereinbarungen", "Offene Themen"]

    /// Heading lines start a section; "- " lines are its entries. Text before any heading gets an untitled section.
    static func sections(_ file: String) -> [(title: String, lines: [String])] {
        var result: [(title: String, lines: [String])] = []
        for raw in file.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if headings.contains(line) {
                result.append((line, []))
                continue
            }
            if result.isEmpty { result.append(("", [])) }
            result[result.count - 1].lines.append(line.hasPrefix("- ") ? String(line.dropFirst(2)) : line)
        }
        return result.filter { !$0.lines.isEmpty }
    }

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        Button("Schließen") { dismiss() }
                    }
                    .font(.label)
                    .foregroundStyle(Ink.muted)
                    .frame(minHeight: 44)
                    Eyebrow("Deine Akte")
                    Text("Was dein Coach über dich weiß").font(.display(28))
                    if let file = model.state?.file, !Self.sections(file).isEmpty {
                        if let at = model.state?.fileUpdatedAt {
                            Text("Zuletzt ergänzt am \(germanDate(at))")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Ink.muted)
                        }
                        ForEach(Array(Self.sections(file).enumerated()), id: \.offset) { _, section in
                            Card {
                                if !section.title.isEmpty { Eyebrow(section.title) }
                                ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.body, design: .rounded))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    } else {
                        Text("Dein Coach legt deine Akte gerade an.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Ink.muted)
                    }
                    Text("Das ist, was dein Coach sich von euren Gesprächen merkt und beim nächsten Mal nutzt. „Alle meine Daten löschen“ entfernt auch deine Akte.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Ink.muted)
                }
                .padding(24)
            }
        }
    }
}

/// Realtime follow-up conversation after signing. The coach leads; afterwards it sums up what it took away.
