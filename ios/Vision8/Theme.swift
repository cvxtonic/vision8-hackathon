import SwiftUI

enum Ink {
    static let night = Color(red: 0.055, green: 0.07, blue: 0.125)
    static let surface = Color(red: 0.10, green: 0.125, blue: 0.20)
    static let line = Color.white.opacity(0.10)
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let muted = Color(red: 0.96, green: 0.94, blue: 0.89).opacity(0.62)
    static let dawn = Color(red: 0.95, green: 0.71, blue: 0.27)
    static let good = Color(red: 0.49, green: 0.80, blue: 0.62)
    static let drift = Color(red: 0.93, green: 0.48, blue: 0.42)
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static let quote = Font.system(.title3, design: .serif).italic()
    static let label = Font.system(.caption, design: .rounded).weight(.semibold)
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.label)
            .kerning(1.4)
            .foregroundStyle(Ink.dawn)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ink.line))
    }
}

/// Scales down while pressed and springs back; cancels when the finger leaves.
struct PressStyle: ButtonStyle {
    var filled = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(filled ? Ink.night : Ink.paper)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(filled ? Ink.dawn : Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(filled ? .clear : Ink.line))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CoachThinking: View {
    var text = "Der Coach denkt nach"
    var body: some View {
        HStack(spacing: 10) {
            // Time-driven instead of repeatForever: a never-ending implicit animation kept the
            // interview view from finishing its removal transition (it stayed on top, half faded).
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Ink.dawn)
                            .frame(width: 7, height: 7)
                            .opacity(0.25 + 0.75 * (0.5 + 0.5 * sin(t * 4 - Double(i) * 0.9)))
                    }
                }
            }
            Text(text).font(.system(.subheadline, design: .rounded)).foregroundStyle(Ink.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ErrorNote: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Ink.drift)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Ink.night.ignoresSafeArea()
            content
        }
        .foregroundStyle(Ink.paper)
    }
}

func germanDate(_ iso: String) -> String {
    let date = ISO8601DateFormatter.fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        return f.date(from: iso)
    }()
    guard let date else { return iso }
    return date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "de_DE")))
}
