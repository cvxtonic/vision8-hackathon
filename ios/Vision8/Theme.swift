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

// MARK: - Design tokens (see STYLEGUIDE.md). Use these instead of raw numbers.

/// Spacing scale. Page margin is `page`; space between sections is `section`; inside a card `m`.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let page: CGFloat = 20
    static let section: CGFloat = 28
    static let xl: CGFloat = 40
}

/// Corner radii, always with `.continuous` corners.
enum Radius {
    static let card: CGFloat = 22
    static let control: CGFloat = 16
    static let row: CGFloat = 14
}

/// Motion: three curves only. `snappy` for taps and toggles, `smooth` for content changes, `gentle` for entrances.
enum Motion {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let smooth = Animation.easeInOut(duration: 0.32)
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.9)
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static let quote = Font.system(.title3, design: .serif).italic()
    static let label = Font.system(.caption, design: .rounded).weight(.semibold)

    // Type scale (Dynamic Type aware where it matters).
    static let pageTitle = Font.system(size: 34, weight: .semibold, design: .serif)
    static let sectionTitle = Font.system(size: 22, weight: .semibold, design: .serif)
    static let cardTitle = Font.system(.headline, design: .rounded)
    static let bodyText = Font.system(.body, design: .rounded)
    static let callout = Font.system(.subheadline, design: .rounded)
    static let note = Font.system(.footnote, design: .rounded)
}

/// Page layout: the one vertical rhythm for every tab.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) { content }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xl + 60) // room for the tab bar and the coach bar
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Title and optional hint above a group of content.
struct SectionHeader: View {
    let title: String
    var hint: String?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).font(.sectionTitle)
            if let hint { Text(hint).font(.note).foregroundStyle(Ink.muted) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Entrance: fade and rise a little, staggered by `index`. Respects Reduce Motion.
private struct Appear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                withAnimation(Motion.gentle.delay(reduceMotion ? 0 : Double(min(index, 8)) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func appear(_ index: Int = 0) -> some View { modifier(Appear(index: index)) }
}

/// Placeholder block that shimmers while content loads (instead of a spinner).
struct Skeleton: View {
    var height: CGFloat = 52
    @State private var phase: CGFloat = -1
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            .fill(Ink.surface)
            .overlay(
                LinearGradient(colors: [.clear, Color.white.opacity(0.06), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: phase * 260)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            )
            .frame(height: height)
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.4 } }
            .accessibilityHidden(true)
    }
}

/// List rows: a soft highlight while pressed, no scaling (rows sit edge to edge).
struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.05 : 0))
            .animation(Motion.snappy, value: configuration.isPressed)
    }
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
        VStack(alignment: .leading, spacing: Space.s) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.page)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.line))
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
            .background(filled ? Ink.dawn : Ink.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(filled ? .clear : Ink.line))
            .brightness(configuration.isPressed ? -0.04 : 0)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
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
