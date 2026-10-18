import SwiftUI
import WidgetKit

/// Lock Screen accessory widgets. iOS tints these itself, so they don't apply the app's appearance.
struct BreakTimerLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.lockScreen, provider: BreakTimelineProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "breaktimer://today"))
        }
        .configurationDisplayName("Pausenbudget")
        .description("Verbleibende Pausenzeit auf dem Sperrbildschirm.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenWidgetView: View {
    let entry: BreakEntry
    @Environment(\.widgetFamily) private var family

    private var status: DayStatus { entry.status }

    var body: some View {
        if !entry.isSignedIn {
            signedOut
        } else {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            default: inline
            }
        }
    }

    @ViewBuilder
    private var signedOut: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "cup.and.saucer.fill")
                .font(.title3)
                .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("BreakTimer", systemImage: "cup.and.saucer.fill").font(.headline)
                Text("Nicht angemeldet").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text("BreakTimer · Nicht angemeldet")
        }
    }

    /// Ring of budget used, filling live while a break runs.
    @ViewBuilder
    private var circular: some View {
        Group {
            if let anchor = status.liveAnchor, let end = status.exhaustedAt, !status.isOvertime, end > anchor {
                ProgressView(timerInterval: anchor...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "cup.and.saucer.fill")
                }
                .progressViewStyle(.circular)
            } else {
                Gauge(value: min(max(status.progress, 0), 1)) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: status.isOvertime ? "exclamationmark" : "cup.and.saucer.fill")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }
        }
        .widgetAccentable()
        .accessibilityLabel("Pausenbudget")
        .accessibilityValue(RemainingText.accessibilityValue(status))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "cup.and.saucer.fill")
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                WidgetText.remaining(status)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .frame(maxWidth: 90, alignment: .leading)
                WidgetText.caption(status)
                    .font(.caption)
            }
            linearProgress
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var linearProgress: some View {
        if let anchor = status.liveAnchor, let end = status.exhaustedAt, !status.isOvertime, end > anchor {
            ProgressView(timerInterval: anchor...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
        } else {
            ProgressView(value: min(max(status.progress, 0), 1))
                .progressViewStyle(.linear)
        }
    }

    /// "Pause · 12:34 übrig" / "Pause · +03:15 über"
    @ViewBuilder
    private var inline: some View {
        if status.isOvertime {
            Text("Pause · \(WidgetText.remaining(status)) über")
        } else {
            Text("Pause · \(WidgetText.remaining(status)) übrig")
        }
    }

    private var title: LocalizedStringKey {
        if status.isOvertime { return "Überzogen" }
        return status.isRunning ? "Pause läuft" : "Pausenbudget"
    }
}

#Preview("Rund · Dunkel", as: .accessoryCircular) {
    BreakTimerLockScreenWidget()
} timeline: {
    WidgetSamples.entry(.empty)
    WidgetSamples.entry(.running)
    WidgetSamples.entry(.low)
    WidgetSamples.entry(.overtime)
}

#Preview("Rechteckig · Dunkel", as: .accessoryRectangular) {
    BreakTimerLockScreenWidget()
} timeline: {
    WidgetSamples.entry(.empty)
    WidgetSamples.entry(.running)
    WidgetSamples.entry(.low)
    WidgetSamples.entry(.overtime)
}

#Preview("Inline · Dunkel", as: .accessoryInline) {
    BreakTimerLockScreenWidget()
} timeline: {
    WidgetSamples.entry(.empty)
    WidgetSamples.entry(.running)
    WidgetSamples.entry(.low)
    WidgetSamples.entry(.overtime)
}

#Preview("Rund · Hell", as: .accessoryCircular) {
    BreakTimerLockScreenWidget()
} timeline: {
    WidgetSamples.entry(.empty, appearance: .light)
    WidgetSamples.entry(.running, appearance: .light)
    WidgetSamples.entry(.low, appearance: .light)
    WidgetSamples.entry(.overtime, appearance: .light)
}

#Preview("Rechteckig · Hell", as: .accessoryRectangular) {
    BreakTimerLockScreenWidget()
} timeline: {
    WidgetSamples.entry(.empty, appearance: .light)
    WidgetSamples.entry(.running, appearance: .light)
    WidgetSamples.entry(.low, appearance: .light)
    WidgetSamples.entry(.overtime, appearance: .light)
}

#Preview("Inline · Hell", as: .accessoryInline) {
    BreakTimerLockScreenWidget()
} timeline: {
    WidgetSamples.entry(.empty, appearance: .light)
    WidgetSamples.entry(.running, appearance: .light)
    WidgetSamples.entry(.low, appearance: .light)
    WidgetSamples.entry(.overtime, appearance: .light)
}
