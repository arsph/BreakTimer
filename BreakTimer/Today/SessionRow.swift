import SwiftUI

struct SessionRow: View {
    let session: BreakSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if session.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                content(now: timeline.date)
            }
        } else {
            content(now: .now)
        }
    }

    private func content(now: Date) -> some View {
        let duration = Text(SessionRow.duration(session.duration(at: now)))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(timeRange)
                    duration
                }
            } else {
                HStack {
                    Image(systemName: session.isRunning ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .foregroundStyle(session.isRunning ? Theme.accent : .secondary)
                        .accessibilityHidden(true)
                    Text(timeRange)
                    Spacer()
                    duration
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Zum Bearbeiten tippen, zum Löschen wischen.")
    }

    private var timeRange: String {
        let start = session.startedAt.formatted(date: .omitted, time: .shortened)
        guard let end = session.endedAt else { return String(localized: "\(start) – läuft") }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = seconds < 3600 ? [.minutes, .seconds] : [.hours, .minutes]
        return Duration.seconds(seconds).formatted(.units(allowed: allowed, width: .abbreviated))
    }
}
