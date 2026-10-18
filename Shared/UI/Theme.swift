import SwiftUI

enum Theme {
    /// Coffee brown from the asset catalog: espresso in light mode, caramel in dark mode.
    static let accent = Color("AccentColor")
    static let low = Color.orange
    static let overtime = Color.red

    static func color(for level: BudgetLevel) -> Color {
        switch level {
        case .plenty: accent
        case .low: low
        case .overtime: overtime
        }
    }

    static let cardCornerRadius: CGFloat = 28
}

extension View {
    /// Liquid Glass on iOS 26+. Before that, the system's grouped card color (like list rows),
    /// which stands out from the grouped background in both light and dark.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = Theme.cardCornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        }
    }

    /// The prominent action button: glass on iOS 26+, bordered prominent before.
    @ViewBuilder
    func prominentActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Secondary buttons: glass on iOS 26+, bordered before.
    @ViewBuilder
    func secondaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Text for remaining time: "12:34" or "+03:15" in overtime.
enum RemainingText {
    static func clock(_ status: DayStatus) -> String {
        (status.isOvertime ? "+" : "") + DurationFormat.clock(remaining: status.remaining)
    }

    /// Spoken form for VoiceOver, e.g. "12 Minuten, 34 Sekunden übrig".
    static func accessibilityValue(_ status: DayStatus) -> String {
        let seconds = DurationFormat.remainingSeconds(status.remaining)
        let duration = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return status.isOvertime
            ? String(localized: "\(duration) über dem Budget")
            : String(localized: "\(duration) übrig")
    }
}
