import SwiftUI

/// The ring with the remaining time and the start/end button.
struct BudgetHeaderView: View {
    @Environment(BreakController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 60
    @State private var actionCount = 0

    var body: some View {
        let isRunning = controller.runningSession != nil
        VStack(spacing: 28) {
            // Everything is derived from the stored start time and the timeline's date; nothing ticks.
            TimelineView(.periodic(from: .now, by: isRunning ? 1 : 60)) { timeline in
                let status = controller.status(at: timeline.date)
                VStack(spacing: 16) {
                    ring(status)
                        .frame(maxWidth: 300)
                    // At accessibility text sizes the usage line moves out of the ring.
                    if dynamicTypeSize.isAccessibilitySize {
                        usageText(status, font: .body)
                    }
                }
            }
            .padding(.top, 8)

            Button(action: toggle) {
                HStack(spacing: 10) {
                    // The icon gives way to the text at accessibility sizes.
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: isRunning ? "stop.fill" : "cup.and.saucer.fill")
                    }
                    Text(isRunning ? "Pause beenden" : "Pause starten")
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .prominentActionStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(isRunning ? Color(uiColor: .systemGray) : Theme.accent)
            .sensoryFeedback(isRunning ? .start : .stop, trigger: actionCount)
            .accessibilityHint(isRunning ? "Beendet die laufende Pause." : "Startet eine Pause und zieht sie vom Tagesbudget ab.")
        }
        .padding(24)
        .glassCard()
        .padding(.horizontal, 16)
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.15), value: isRunning)
    }

    private func ring(_ status: DayStatus) -> some View {
        let tint = Theme.color(for: status.level)
        let seconds = DurationFormat.remainingSeconds(status.remaining)
        return BudgetRing(progress: status.progress, tint: tint, lineWidth: 20) {
            VStack(spacing: 4) {
                Text(RemainingText.clock(status))
                    .font(.system(size: digitSize, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: !status.isOvertime))
                    .animation(reduceMotion ? nil : .snappy, value: seconds)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(status.isOvertime ? Theme.overtime : .primary)
                Text(status.isOvertime ? "über" : "übrig")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(status.isOvertime ? Theme.overtime : .secondary)
                if !dynamicTypeSize.isAccessibilitySize {
                    usageText(status, font: .footnote)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.6), value: status.level)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pausenbudget")
        .accessibilityValue("\(RemainingText.accessibilityValue(status)), \(String(localized: "\(minutes(status.used)) von \(minutes(status.budget)) genutzt"))")
    }

    private func usageText(_ status: DayStatus, font: Font) -> some View {
        Text("\(minutes(status.used)) von \(minutes(status.budget)) genutzt")
            .font(font)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .accessibilityHidden(true) // part of the ring's accessibility value
    }

    private func minutes(_ interval: TimeInterval) -> String {
        Duration.seconds(Int(interval / 60) * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func toggle() {
        if controller.runningSession != nil {
            controller.endBreak(source: .app)
        } else {
            controller.startBreak(source: .app)
        }
        actionCount += 1
    }
}

#Preview("Läuft · Dunkel") {
    BudgetHeaderView().previewEnvironment(.running)
}

#Preview("Überzogen · Hell") {
    BudgetHeaderView().previewEnvironment(.overtime, appearance: .light)
}
