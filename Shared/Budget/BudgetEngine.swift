import Foundation

// All budget math lives here. No SwiftUI or SwiftData: everything is derived from stored
// timestamps and a given `now`, so the app, widgets and Live Activity always agree.

enum BudgetRules {
    static let defaultMinutes = 30
    static let minMinutes = 10
    static let maxMinutes = 120
    static let stepMinutes = 5

    /// "Under 5 minutes left" warning threshold.
    static let lowThreshold: TimeInterval = 5 * 60
    /// A break running longer than this triggers "Pause vergessen zu beenden?".
    static let forgottenThreshold: TimeInterval = 2 * 60 * 60

    static var allowedMinutes: [Int] { Array(stride(from: minMinutes, through: maxMinutes, by: stepMinutes)) }

    /// Clamps to 10...120 and rounds to the nearest 5-minute step.
    static func clamp(_ minutes: Int) -> Int {
        let bounded = min(max(minutes, minMinutes), maxMinutes)
        let steps = (Double(bounded - minMinutes) / Double(stepMinutes)).rounded()
        return minMinutes + Int(steps) * stepMinutes
    }
}

/// A value copy of a break session, independent of persistence.
struct SessionSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var day: DayKey
    var budgetMinutes: Int

    var isRunning: Bool { endedAt == nil }

    func duration(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

enum BudgetLevel: Sendable, Equatable {
    case plenty, low, overtime
}

/// Budget state of one day at one moment.
struct DayStatus: Equatable, Sendable {
    let day: DayKey
    let budget: TimeInterval
    /// Usage of finished sessions only.
    let finishedUsage: TimeInterval
    /// Finished sessions plus the elapsed time of the running one, at the moment of evaluation.
    let used: TimeInterval
    /// Start of the running session counted on this day, if any.
    let runningSince: Date?

    var isRunning: Bool { runningSince != nil }
    /// Can be negative (overtime).
    var remaining: TimeInterval { budget - used }
    var isOvertime: Bool { remaining < 0 }
    var level: BudgetLevel {
        if remaining < 0 { return .overtime }
        if remaining < BudgetRules.lowThreshold { return .low }
        return .plenty
    }
    /// used / budget; can exceed 1 in overtime.
    var progress: Double { budget > 0 ? used / budget : 1 }

    /// Moment the "elapsed" clock would show 0: `now - liveAnchor == used` while running.
    /// Widgets use it for `Text(timerInterval:)` and `ProgressView(timerInterval:)`.
    var liveAnchor: Date? { runningSince.map { $0.addingTimeInterval(-finishedUsage) } }
    /// When the running break uses up the budget. Fixed for the whole break, independent of `now`.
    var exhaustedAt: Date? { liveAnchor.map { $0.addingTimeInterval(budget) } }
    /// When the running break reaches 5 minutes left.
    var lowMarkAt: Date? { exhaustedAt.map { $0.addingTimeInterval(-BudgetRules.lowThreshold) } }
}

struct DayTotal: Identifiable, Equatable, Sendable {
    var id: DayKey { day }
    let day: DayKey
    let used: TimeInterval
    let budgetMinutes: Int

    var budget: TimeInterval { TimeInterval(budgetMinutes * 60) }
    var isOverBudget: Bool { used > budget }
}

enum SessionEditError: Error, Equatable, Sendable {
    case endBeforeStart
    case startInFuture
    case endInFuture
    case overlapsOtherSession
}

enum BudgetEngine {
    /// The day whose budget the Today screen shows: the running break's day while one runs
    /// (a break crossing midnight still counts toward the day it started), otherwise today.
    static func activeDay(sessions: [SessionSnapshot], now: Date, calendar: Calendar = .current) -> DayKey {
        sessions.first(where: \.isRunning)?.day ?? DayKey(now, calendar: calendar)
    }

    /// Daily usage = finished sessions of `day` + elapsed time of its running session.
    /// `budgetMinutes` is the budget in effect for that day (today: the current setting).
    static func status(day: DayKey, sessions: [SessionSnapshot], budgetMinutes: Int, now: Date) -> DayStatus {
        let ofDay = sessions.filter { $0.day == day }
        let finished = ofDay.filter { !$0.isRunning }.reduce(0) { $0 + $1.duration(at: now) }
        let running = ofDay.first(where: \.isRunning)
        let used = finished + (running?.duration(at: now) ?? 0)
        return DayStatus(
            day: day,
            budget: TimeInterval(budgetMinutes * 60),
            finishedUsage: finished,
            used: used,
            runningSince: running?.startedAt
        )
    }

    /// The budget a past day was tracked against: the budget stored on its most recently
    /// started session, or `fallback` if the day has no sessions.
    static func budgetMinutes(for day: DayKey, sessions: [SessionSnapshot], fallback: Int) -> Int {
        sessions.filter { $0.day == day }.max(by: { $0.startedAt < $1.startedAt })?.budgetMinutes ?? fallback
    }

    /// Totals for each day. `today` always uses `currentBudgetMinutes`; past days use their stored budget.
    static func dailyTotals(
        for days: [DayKey],
        sessions: [SessionSnapshot],
        currentBudgetMinutes: Int,
        today: DayKey,
        now: Date
    ) -> [DayTotal] {
        let byDay = Dictionary(grouping: sessions, by: \.day)
        return days.map { day in
            let ofDay = byDay[day] ?? []
            let used = ofDay.reduce(0) { $0 + $1.duration(at: now) }
            let budget = day == today
                ? currentBudgetMinutes
                : budgetMinutes(for: day, sessions: ofDay, fallback: currentBudgetMinutes)
            return DayTotal(day: day, used: used, budgetMinutes: budget)
        }
    }

    /// A budget change applies to the whole of `day` (today), including a running break:
    /// all of that day's sessions take the new budget so history records it. Other days keep theirs.
    static func applyingBudgetChange(_ minutes: Int, to sessions: [SessionSnapshot], on day: DayKey) -> [SessionSnapshot] {
        sessions.map { session in
            guard session.day == day else { return session }
            var changed = session
            changed.budgetMinutes = minutes
            return changed
        }
    }

    /// Validates new start/end times for a session (end nil = still running).
    static func validateEdit(
        sessionID: UUID,
        start: Date,
        end: Date?,
        sessions: [SessionSnapshot],
        now: Date
    ) -> SessionEditError? {
        if start > now { return .startInFuture }
        if let end {
            if end <= start { return .endBeforeStart }
            if end > now { return .endInFuture }
        }
        let effectiveEnd = end ?? now
        let overlaps = sessions.contains { other in
            guard other.id != sessionID else { return false }
            let otherEnd = other.endedAt ?? now
            return start < otherEnd && other.startedAt < effectiveEnd
        }
        return overlaps ? .overlapsOtherSession : nil
    }

    /// Returns the session with new times; its day follows the new start time.
    static func edited(_ session: SessionSnapshot, start: Date, end: Date?, calendar: Calendar = .current) -> SessionSnapshot {
        var changed = session
        changed.startedAt = start
        changed.endedAt = end
        changed.day = DayKey(start, calendar: calendar)
        return changed
    }

    static func isLikelyForgotten(_ session: SessionSnapshot, now: Date) -> Bool {
        session.isRunning && session.duration(at: now) > BudgetRules.forgottenThreshold
    }
}

/// Clock-style formatting shared by the app and widgets.
enum DurationFormat {
    /// Remaining time counts down in whole seconds rounded up (shows 30:00 at the start and
    /// reaches 00:00 exactly when the budget runs out); overtime counts up rounded down.
    static func remainingSeconds(_ remaining: TimeInterval) -> Int {
        remaining >= 0 ? Int(remaining.rounded(.up)) : Int((-remaining).rounded(.down))
    }

    /// "mm:ss", or "h:mm:ss" from one hour on.
    static func clock(seconds: Int) -> String {
        let value = abs(seconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let secs = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    static func clock(remaining: TimeInterval) -> String {
        clock(seconds: remainingSeconds(remaining))
    }
}
