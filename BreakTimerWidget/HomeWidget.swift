import SwiftUI
import WidgetKit

struct BreakTimerHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.home, provider: BreakTimelineProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Pausenbudget")
        .description("Verbleibende Pausenzeit mit Taste zum Starten und Beenden.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeWidgetView: View {
    let entry: BreakEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetAppearance(appearance: entry.appearance) {
            if !entry.isSignedIn {
                SignedOutWidgetView()
            } else {
                switch family {
                case .systemMedium: medium
                default: small
                }
            }
        }
        .widgetURL(URL(string: "breaktimer://today"))
    }

    private var status: DayStatus { entry.status }

    private func ringWithRemaining(digits: Font) -> some View {
        ZStack {
            WidgetRing(status: status, lineWidth: 8)
            VStack(spacing: 0) {
                WidgetText.remaining(status)
                    .font(digits)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(status.isOvertime ? Theme.overtime : .primary)
                WidgetText.caption(status)
                    .font(.caption2)
                    .foregroundStyle(status.isOvertime ? Theme.overtime : .secondary)
            }
            .padding(.horizontal, 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pausenbudget")
        .accessibilityValue(RemainingText.accessibilityValue(status))
    }

    private var small: some View {
        VStack(spacing: 8) {
            ringWithRemaining(digits: .system(size: 20, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            BreakActionButton(isRunning: status.isRunning)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ringWithRemaining(digits: .system(size: 24, weight: .semibold, design: .rounded))
                .frame(maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Heute genutzt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    WidgetText.used(status)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 60, alignment: .trailing)
                }

                if entry.recent.isEmpty {
                    Text("Noch keine Pausen heute.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    ForEach(entry.recent) { session in
                        RecentRow(session: session, now: entry.date)
                    }
                }

                Spacer(minLength: 4)
                BreakActionButton(isRunning: status.isRunning)
            }
        }
    }
}

private struct RecentRow: View {
    let session: SessionSnapshot
    let now: Date

    var body: some View {
        HStack {
            Text(range)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let start = session.isRunning ? session.startedAt : nil {
                Text(start, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 50, alignment: .trailing)
                    .foregroundStyle(Theme.accent)
            } else {
                Text(WidgetText.short(session.duration(at: now)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }

    private var range: String {
        let start = session.startedAt.formatted(date: .omitted, time: .shortened)
        guard let end = session.endedAt else { return String(localized: "\(start) – läuft") }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

#Preview("Klein · Dunkel", as: .systemSmall) {
    BreakTimerHomeWidget()
} timeline: {
    WidgetSamples.entry(.empty, appearance: .dark)
    WidgetSamples.entry(.running, appearance: .dark)
    WidgetSamples.entry(.low, appearance: .dark)
    WidgetSamples.entry(.overtime, appearance: .dark)
}

#Preview("Klein · Hell", as: .systemSmall) {
    BreakTimerHomeWidget()
} timeline: {
    WidgetSamples.entry(.empty, appearance: .light)
    WidgetSamples.entry(.running, appearance: .light)
    WidgetSamples.entry(.low, appearance: .light)
    WidgetSamples.entry(.overtime, appearance: .light)
}

#Preview("Mittel · Dunkel", as: .systemMedium) {
    BreakTimerHomeWidget()
} timeline: {
    WidgetSamples.entry(.empty, appearance: .dark)
    WidgetSamples.entry(.running, appearance: .dark)
    WidgetSamples.entry(.low, appearance: .dark)
    WidgetSamples.entry(.overtime, appearance: .dark)
}

#Preview("Mittel · Hell", as: .systemMedium) {
    BreakTimerHomeWidget()
} timeline: {
    WidgetSamples.entry(.empty, appearance: .light)
    WidgetSamples.entry(.running, appearance: .light)
    WidgetSamples.entry(.low, appearance: .light)
    WidgetSamples.entry(.overtime, appearance: .light)
}
