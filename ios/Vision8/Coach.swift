import SwiftUI

/// Row that opens the coach's file.
struct FileRow: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Deine Akte").font(.cardTitle)
                    Text(model.state?.fileUpdatedAt.map { "Zuletzt ergänzt am \(germanDate($0))" } ?? "Was dein Coach über dich weiß")
                        .font(.note)
                        .foregroundStyle(Ink.muted)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.note.weight(.semibold))
                    .foregroundStyle(Ink.muted)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .background(Ink.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.line))
        .animation(Motion.smooth, value: model.state?.fileUpdatedAt)
        .sheet(isPresented: $open) { FileView() }
    }
}

/// The coach's file on the person, section by section, typeset like a quiet document.
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
        let sections = model.state?.file.map(Self.sections) ?? []
        Screen {
            ScrollView {
                Page {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack {
                            Eyebrow("Deine Akte")
                            Spacer()
                            Button("Schließen") { dismiss() }
                                .font(.label)
                                .foregroundStyle(Ink.muted)
                                .frame(minHeight: 44)
                        }
                        Text("Was dein Coach über dich weiß")
                            .font(.pageTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if !sections.isEmpty, let at = model.state?.fileUpdatedAt {
                            Text("Zuletzt ergänzt am \(germanDate(at))")
                                .font(.note)
                                .foregroundStyle(Ink.muted)
                        }
                    }
                    .appear(0)

                    if sections.isEmpty {
                        CoachThinking(text: "Dein Coach legt deine Akte gerade an")
                            .appear(1)
                    } else {
                        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                            FileSection(title: section.title, lines: section.lines)
                                .appear(index + 1)
                        }
                    }

                    Text("Das ist, was dein Coach sich von euren Gesprächen merkt und beim nächsten Mal nutzt. „Alle meine Daten löschen“ entfernt auch deine Akte.")
                        .font(.note)
                        .foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.m)
                        .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: 0.5) }
                        .appear(sections.count + 1)
                }
                .animation(Motion.smooth, value: model.state?.file)
            }
        }
    }
}

/// One chapter of the file: serif heading, then entries as hanging-indent paragraphs.
private struct FileSection: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if !title.isEmpty {
                Text(title)
                    .font(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Circle()
                            .fill(Ink.muted)
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
                            .accessibilityHidden(true)
                        Text(line)
                            .font(.bodyText)
                            .lineSpacing(Space.xxs)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Realtime follow-up conversation after signing. The coach leads; afterwards it sums up what it took away.
