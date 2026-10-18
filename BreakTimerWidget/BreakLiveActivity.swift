import ActivityKit
import SwiftUI
import WidgetKit

struct BreakLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreakActivityAttributes.self) { context in
            LiveActivityBanner(context: context)
                .activityBackgroundTint(Self.backgroundTint(context.state.appearance))
                .activitySystemActionForegroundColor(Theme.accent)
                .widgetURL(URL(string: "breaktimer://today"))
        } dynamicIsland: { context in
            let model = LiveActivityModel(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(model.isOvertime ? "Über" : "Übrig", systemImage: "cup.and.saucer.fill")
                            .font(.caption)
                            .foregroundStyle(model.tint)
                        model.remainingText
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(model.isOvertime ? Theme.overtime : .white)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Heute genutzt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.state.liveAnchor, style: .timer)
                            .font(.system(.title3, design: .rounded, weight: .medium))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        model.progressBar
                        EndBreakButton()
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(model.tint)
            } compactTrailing: {
                model.remainingText
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56)
                    .foregroundStyle(model.isOvertime ? Theme.overtime : model.tint)
            } minimal: {
                model.ring
            }
            .keylineTint(model.tint)
            .widgetURL(URL(string: "breaktimer://today"))
        }
    }

    /// The Lock Screen banner follows the app's appearance (dark by default).
    static func backgroundTint(_ appearance: AppAppearance) -> Color? {
        appearance.colorScheme.map { Theme.widgetBackground($0).opacity(0.92) }
    }
}

/// Derived display values; overtime once the stale date (budget runs out) has passed.
struct LiveActivityModel {
    let context: ActivityViewContext<BreakActivityAttributes>

    var state: BreakActivityAttributes.ContentState { context.state }
    var isOvertime: Bool { context.isStale || state.wasOvertimeAtUpdate }
    var tint: Color { isOvertime ? Theme.overtime : Theme.accent }

    /// Live countdown, or a live "+m:ss" count-up in overtime.
    var remainingText: Text {
        isOvertime
            ? Text("+\(Text(state.exhaustedAt, style: .timer))")
            : Text(timerInterval: state.liveAnchor...state.exhaustedAt, countsDown: true)
    }

    @ViewBuilder
    var progressBar: some View {
        if isOvertime {
            ProgressView(value: 1).tint(Theme.overtime)
        } else {
            ProgressView(timerInterval: state.liveAnchor...state.exhaustedAt, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(Theme.accent)
        }
    }

    @ViewBuilder
    var ring: some View {
        if isOvertime {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.overtime)
        } else {
            ProgressView(timerInterval: state.liveAnchor...state.exhaustedAt, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 8))
            }
            .progressViewStyle(.circular)
            .tint(Theme.accent)
        }
    }
}

struct EndBreakButton: View {
    var body: some View {
        Button(intent: EndBreakIntent(source: .liveActivity)) {
            Label("Pause beenden", systemImage: "stop.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(Color(uiColor: .systemGray), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Lock Screen / banner presentation.
struct LiveActivityBanner: View {
    let context: ActivityViewContext<BreakActivityAttributes>
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let model = LiveActivityModel(context: context)
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                model.ring
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(model.isOvertime ? "Pausenbudget überzogen" : "Pause läuft")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        model.remainingText
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(model.isOvertime ? Theme.overtime : .primary)
                            .layoutPriority(1)
                        Text(model.isOvertime ? "über" : "übrig")
                            .font(.subheadline)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(model.isOvertime ? Theme.overtime : .secondary)
                    }
                }

                Spacer(minLength: 8)

                Button(intent: EndBreakIntent(source: .liveActivity)) {
                    Label("Beenden", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(.white)
                        .background(Color(uiColor: .systemGray), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pause beenden")
            }
            model.progressBar
        }
        .padding(16)
        .environment(\.colorScheme, context.state.appearance.colorScheme ?? systemScheme)
    }
}

// MARK: - Previews (a Live Activity only exists while a break runs: running, under 5 minutes, overtime)

extension BreakActivityAttributes {
    static let preview = BreakActivityAttributes(sessionID: UUID(), startedAt: .now.addingTimeInterval(-6 * 60))
}

extension BreakActivityAttributes.ContentState {
    static func sample(_ scenario: WidgetSamples.Scenario, appearance: AppAppearance = .dark) -> Self {
        let status = WidgetSamples.entry(scenario).status
        return Self(status: status, appearance: appearance)
            ?? Self(liveAnchor: .now, exhaustedAt: .now.addingTimeInterval(1800), budgetMinutes: 30, appearance: appearance, wasOvertimeAtUpdate: false)
    }
}

#Preview("Sperrbildschirm · Dunkel", as: .content, using: BreakActivityAttributes.preview) {
    BreakLiveActivity()
} contentStates: {
    BreakActivityAttributes.ContentState.sample(.running)
    BreakActivityAttributes.ContentState.sample(.low)
    BreakActivityAttributes.ContentState.sample(.overtime)
}

#Preview("Sperrbildschirm · Hell", as: .content, using: BreakActivityAttributes.preview) {
    BreakLiveActivity()
} contentStates: {
    BreakActivityAttributes.ContentState.sample(.running, appearance: .light)
    BreakActivityAttributes.ContentState.sample(.low, appearance: .light)
    BreakActivityAttributes.ContentState.sample(.overtime, appearance: .light)
}

#Preview("Dynamic Island · kompakt", as: .dynamicIsland(.compact), using: BreakActivityAttributes.preview) {
    BreakLiveActivity()
} contentStates: {
    BreakActivityAttributes.ContentState.sample(.running)
    BreakActivityAttributes.ContentState.sample(.low)
    BreakActivityAttributes.ContentState.sample(.overtime)
}

#Preview("Dynamic Island · erweitert", as: .dynamicIsland(.expanded), using: BreakActivityAttributes.preview) {
    BreakLiveActivity()
} contentStates: {
    BreakActivityAttributes.ContentState.sample(.running)
    BreakActivityAttributes.ContentState.sample(.low)
    BreakActivityAttributes.ContentState.sample(.overtime)
}

#Preview("Dynamic Island · minimal", as: .dynamicIsland(.minimal), using: BreakActivityAttributes.preview) {
    BreakLiveActivity()
} contentStates: {
    BreakActivityAttributes.ContentState.sample(.running)
    BreakActivityAttributes.ContentState.sample(.low)
    BreakActivityAttributes.ContentState.sample(.overtime)
}
