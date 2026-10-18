import AppIntents
import SwiftUI
import WidgetKit

extension Theme {
    /// Warm espresso black / cream, matching the coffee accent. Also used by the Live Activity.
    static func widgetBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.118, green: 0.098, blue: 0.082) : Color(red: 0.984, green: 0.969, blue: 0.949)
    }
}

/// Applies the app's appearance setting (dark by default) to a Home Screen widget:
/// its own background and color scheme, instead of following the system.
struct WidgetAppearance<Content: View>: View {
    let appearance: AppAppearance
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let scheme = appearance.colorScheme ?? systemScheme
        content
            .environment(\.colorScheme, scheme)
            .containerBackground(for: .widget) { Theme.widgetBackground(scheme) }
    }
}

enum WidgetText {
    /// Remaining time as Text: a live countdown while a break runs, a live "+mm:ss" count-up
    /// in overtime, a fixed value otherwise.
    static func remaining(_ status: DayStatus) -> Text {
        if let anchor = status.liveAnchor, let end = status.exhaustedAt {
            if status.isOvertime || end <= anchor {
                return Text("+\(Text(end, style: .timer))")
            }
            return Text(timerInterval: anchor...end, countsDown: true)
        }
        let seconds = TimeInterval(DurationFormat.remainingSeconds(status.remaining))
        return Text((status.isOvertime ? "+" : "") + short(seconds))
    }

    /// Usage today: counts up live while a break runs.
    static func used(_ status: DayStatus) -> Text {
        if let anchor = status.liveAnchor {
            return Text(anchor, style: .timer)
        }
        return Text(short(status.used))
    }

    /// "8:05" / "1:02:05": same style as the system's live timer text, so fixed and live values match.
    static func short(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    static func caption(_ status: DayStatus) -> Text {
        status.isOvertime ? Text("über") : Text("übrig")
    }
}

/// The ring of budget used. While a break runs below budget it fills live via
/// `ProgressView(timerInterval:)`; otherwise it is drawn from the entry's status.
struct WidgetRing: View {
    let status: DayStatus
    var lineWidth: CGFloat = 8

    var body: some View {
        let tint = Theme.color(for: status.level)
        if let anchor = status.liveAnchor, let end = status.exhaustedAt, !status.isOvertime, end > anchor {
            ProgressView(timerInterval: anchor...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(tint)
            .widgetAccentable()
        } else {
            BudgetRing(progress: status.progress, tint: tint, lineWidth: lineWidth)
                .widgetAccentable()
        }
    }
}

/// Start/end button that runs the App Intent without opening the app.
struct BreakActionButton: View {
    let isRunning: Bool
    var source: BreakSource = .widget

    var body: some View {
        if isRunning {
            Button(intent: EndBreakIntent(source: source)) {
                label("Beenden", systemImage: "stop.fill", tint: Color(uiColor: .systemGray))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause beenden")
        } else {
            Button(intent: StartBreakIntent(source: source)) {
                label("Starten", systemImage: "cup.and.saucer.fill", tint: Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause starten")
        }
    }

    private func label(_ title: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(tint, in: Capsule())
            .widgetAccentable()
    }
}

/// Shown while nobody is signed in to the app.
struct SignedOutWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .widgetAccentable()
            Text("Melde dich in BreakTimer an.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
