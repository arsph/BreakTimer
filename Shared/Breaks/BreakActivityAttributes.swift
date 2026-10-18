import ActivityKit
import Foundation

/// Live Activity for a running break. Everything shown is derived from fixed dates, so the
/// countdown keeps running without updates; the activity is only updated when the budget,
/// the break or the appearance changes. No push updates.
struct BreakActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// `now - liveAnchor` = usage today (see `DayStatus.liveAnchor`).
        var liveAnchor: Date
        /// When the budget runs out; also the activity's stale date.
        var exhaustedAt: Date
        var budgetMinutes: Int
        var appearance: AppAppearance
        /// The budget was already used up when this state was created
        /// (`context.isStale` covers the moment it runs out later).
        var wasOvertimeAtUpdate: Bool
    }

    var sessionID: UUID
    var startedAt: Date
}

extension AppAppearance: Codable {}

extension BreakActivityAttributes.ContentState {
    /// nil when no break is running.
    init?(status: DayStatus, appearance: AppAppearance) {
        guard let anchor = status.liveAnchor, let exhaustedAt = status.exhaustedAt else { return nil }
        self.init(
            liveAnchor: anchor,
            exhaustedAt: exhaustedAt,
            budgetMinutes: Int(status.budget / 60),
            appearance: appearance,
            wasOvertimeAtUpdate: status.remaining <= 0
        )
    }
}
