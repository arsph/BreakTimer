import Foundation
import Testing

@Suite("BudgetEngine")
struct BudgetEngineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    func session(start: Date, end: Date?, budget: Int = 30) -> SessionSnapshot {
        SessionSnapshot(id: UUID(), startedAt: start, endedAt: end, day: DayKey(start, calendar: calendar), budgetMinutes: budget)
    }

    var today: DayKey { DayKey(year: 2026, month: 10, day: 18) }

    // MARK: Normal day

    @Test func noBreaksLeavesFullBudget() {
        let status = BudgetEngine.status(day: today, sessions: [], budgetMinutes: 30, now: date(18, 10, 0))
        #expect(status.used == 0)
        #expect(status.remaining == 30 * 60)
        #expect(status.level == .plenty)
        #expect(!status.isRunning)
        #expect(status.exhaustedAt == nil)
    }

    @Test func singleFinishedBreak() {
        let sessions = [session(start: date(18, 10, 0), end: date(18, 10, 12))]
        let status = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: date(18, 12, 0))
        #expect(status.used == 12 * 60)
        #expect(status.remaining == 18 * 60)
        #expect(status.progress == 0.4)
    }

    @Test func runningBreakIsDerivedFromNow() {
        let sessions = [session(start: date(18, 10, 0), end: nil)]
        let status = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: date(18, 10, 7, 30))
        #expect(status.isRunning)
        #expect(status.used == 7 * 60 + 30)
        #expect(status.exhaustedAt == date(18, 10, 30))
        #expect(status.lowMarkAt == date(18, 10, 25))
        #expect(status.liveAnchor == date(18, 10, 0))
    }

    // MARK: Multiple sessions

    @Test func multipleSessionsAddUp() {
        let sessions = [
            session(start: date(18, 9, 0), end: date(18, 9, 10)),
            session(start: date(18, 11, 0), end: date(18, 11, 5)),
            session(start: date(18, 13, 0), end: nil),
        ]
        let now = date(18, 13, 4)
        let status = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: now)
        #expect(status.finishedUsage == 15 * 60)
        #expect(status.used == 19 * 60)
        #expect(status.remaining == 11 * 60)
        // Anchor shifts back by the finished usage, so the running break's exhaustion moment is fixed.
        #expect(status.liveAnchor == date(18, 12, 45))
        #expect(status.exhaustedAt == date(18, 13, 15))
    }

    @Test func otherDaysAreIgnored() {
        let sessions = [
            session(start: date(17, 9, 0), end: date(17, 9, 25)),
            session(start: date(18, 9, 0), end: date(18, 9, 10)),
        ]
        let status = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: date(18, 12, 0))
        #expect(status.used == 10 * 60)
    }

    // MARK: Levels and overtime

    @Test func underFiveMinutesIsLow() {
        let sessions = [session(start: date(18, 10, 0), end: date(18, 10, 26))]
        let status = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: date(18, 11, 0))
        #expect(status.level == .low)
        #expect(!status.isOvertime)
    }

    @Test func exactlyUsedUpIsNotOvertime() {
        let sessions = [session(start: date(18, 10, 0), end: date(18, 10, 30))]
        let status = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: date(18, 11, 0))
        #expect(status.remaining == 0)
        #expect(status.level == .low)
        #expect(!status.isOvertime)
    }

    @Test func overtimeGoesNegative() {
        let sessions = [
            session(start: date(18, 9, 0), end: date(18, 9, 20)),
            session(start: date(18, 12, 0), end: nil),
        ]
        let status = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: date(18, 12, 13, 15))
        #expect(status.used == 33 * 60 + 15)
        #expect(status.remaining == -(3 * 60 + 15))
        #expect(status.isOvertime)
        #expect(status.level == .overtime)
        #expect(status.progress > 1)
        #expect(DurationFormat.clock(remaining: status.remaining) == "03:15")
    }

    // MARK: Midnight

    @Test func breakCrossingMidnightCountsTowardStartDay() {
        let running = session(start: date(18, 23, 50), end: nil)
        let now = date(19, 0, 10)
        let next = DayKey(year: 2026, month: 10, day: 19)

        #expect(BudgetEngine.activeDay(sessions: [running], now: now, calendar: calendar) == today)
        let started = BudgetEngine.status(day: today, sessions: [running], budgetMinutes: 30, now: now)
        #expect(started.used == 20 * 60)
        let following = BudgetEngine.status(day: next, sessions: [running], budgetMinutes: 30, now: now)
        #expect(following.used == 0)
    }

    @Test func finishedMidnightBreakStaysOnStartDay() {
        let finished = session(start: date(18, 23, 50), end: date(19, 0, 20))
        let now = date(19, 9, 0)
        #expect(BudgetEngine.activeDay(sessions: [finished], now: now, calendar: calendar) == DayKey(year: 2026, month: 10, day: 19))
        let totals = BudgetEngine.dailyTotals(
            for: [today, today.adding(days: 1, calendar: calendar)],
            sessions: [finished], currentBudgetMinutes: 30,
            today: today.adding(days: 1, calendar: calendar), now: now
        )
        #expect(totals[0].used == 30 * 60)
        #expect(totals[1].used == 0)
    }

    // MARK: Editing

    @Test func editingASessionChangesUsage() {
        var first = session(start: date(18, 9, 0), end: date(18, 9, 10))
        let second = session(start: date(18, 11, 0), end: date(18, 11, 5))
        let now = date(18, 12, 0)

        #expect(BudgetEngine.validateEdit(sessionID: first.id, start: date(18, 9, 0), end: date(18, 9, 25), sessions: [first, second], now: now) == nil)
        first = BudgetEngine.edited(first, start: date(18, 9, 0), end: date(18, 9, 25), calendar: calendar)

        let status = BudgetEngine.status(day: today, sessions: [first, second], budgetMinutes: 30, now: now)
        #expect(status.used == 30 * 60)
    }

    @Test func editValidation() {
        let first = session(start: date(18, 9, 0), end: date(18, 9, 10))
        let second = session(start: date(18, 11, 0), end: date(18, 11, 5))
        let sessions = [first, second]
        let now = date(18, 12, 0)

        #expect(BudgetEngine.validateEdit(sessionID: first.id, start: date(18, 9, 10), end: date(18, 9, 0), sessions: sessions, now: now) == .endBeforeStart)
        #expect(BudgetEngine.validateEdit(sessionID: first.id, start: date(18, 9, 0), end: date(18, 12, 30), sessions: sessions, now: now) == .endInFuture)
        #expect(BudgetEngine.validateEdit(sessionID: first.id, start: date(18, 12, 30), end: nil, sessions: sessions, now: now) == .startInFuture)
        #expect(BudgetEngine.validateEdit(sessionID: first.id, start: date(18, 9, 0), end: date(18, 11, 1), sessions: sessions, now: now) == .overlapsOtherSession)
        // Touching end-to-start is fine.
        #expect(BudgetEngine.validateEdit(sessionID: first.id, start: date(18, 9, 0), end: date(18, 11, 0), sessions: sessions, now: now) == nil)
    }

    @Test func forgottenBreakAfterTwoHours() {
        let running = session(start: date(18, 9, 0), end: nil)
        #expect(!BudgetEngine.isLikelyForgotten(running, now: date(18, 11, 0)))
        #expect(BudgetEngine.isLikelyForgotten(running, now: date(18, 11, 0, 1)))
    }

    // MARK: Budget changes

    @Test func budgetChangeMidDay() {
        var sessions = [
            session(start: date(18, 9, 0), end: date(18, 9, 20)),
            session(start: date(17, 9, 0), end: date(17, 9, 40)),
        ]
        let now = date(18, 12, 0)
        let before = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: now)
        #expect(before.remaining == 10 * 60)

        sessions = BudgetEngine.applyingBudgetChange(45, to: sessions, on: today)
        let after = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 45, now: now)
        #expect(after.remaining == 25 * 60)

        // Today's session records the new budget, yesterday keeps its own.
        #expect(sessions[0].budgetMinutes == 45)
        #expect(sessions[1].budgetMinutes == 30)
        let yesterday = today.adding(days: -1, calendar: calendar)
        let totals = BudgetEngine.dailyTotals(for: [yesterday, today], sessions: sessions, currentBudgetMinutes: 45, today: today, now: now)
        #expect(totals[0].budgetMinutes == 30)
        #expect(totals[0].isOverBudget)
        #expect(totals[1].budgetMinutes == 45)
        #expect(!totals[1].isOverBudget)
    }

    @Test func budgetChangeDuringRunningBreak() {
        var sessions = [
            session(start: date(18, 9, 0), end: date(18, 9, 10)),
            session(start: date(18, 12, 0), end: nil),
        ]
        let now = date(18, 12, 15)
        let before = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 30, now: now)
        #expect(before.remaining == 5 * 60)
        #expect(before.exhaustedAt == date(18, 12, 20))

        sessions = BudgetEngine.applyingBudgetChange(20, to: sessions, on: today)
        let lowered = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 20, now: now)
        #expect(lowered.isOvertime)
        #expect(lowered.remaining == -5 * 60)
        #expect(lowered.exhaustedAt == date(18, 12, 10))
        #expect(sessions.allSatisfy { $0.budgetMinutes == 20 })

        let raised = BudgetEngine.status(day: today, sessions: sessions, budgetMinutes: 60, now: now)
        #expect(raised.remaining == 35 * 60)
        #expect(raised.exhaustedAt == date(18, 12, 50))
        #expect(raised.lowMarkAt == date(18, 12, 45))
    }

    @Test func pastDayWithoutSessionsUsesFallbackBudget() {
        let totals = BudgetEngine.dailyTotals(
            for: [today.adding(days: -3, calendar: calendar)], sessions: [],
            currentBudgetMinutes: 40, today: today, now: date(18, 12, 0)
        )
        #expect(totals[0].budgetMinutes == 40)
        #expect(totals[0].used == 0)
    }

    // MARK: Rules and formatting

    @Test func budgetClamping() {
        #expect(BudgetRules.clamp(5) == 10)
        #expect(BudgetRules.clamp(500) == 120)
        #expect(BudgetRules.clamp(32) == 30)
        #expect(BudgetRules.clamp(33) == 35)
        #expect(BudgetRules.allowedMinutes.first == 10)
        #expect(BudgetRules.allowedMinutes.last == 120)
        #expect(BudgetRules.allowedMinutes.count == 23)
    }

    @Test func clockFormatting() {
        #expect(DurationFormat.clock(remaining: 30 * 60) == "30:00")
        #expect(DurationFormat.clock(remaining: 754.2) == "12:35")
        #expect(DurationFormat.clock(remaining: 0) == "00:00")
        #expect(DurationFormat.clock(remaining: -0.5) == "00:00")
        #expect(DurationFormat.clock(remaining: -61.9) == "01:01")
        #expect(DurationFormat.clock(seconds: 3725) == "1:02:05")
    }

    @Test func dayKeyRoundTrip() {
        let key = DayKey(string: "2026-03-09")
        #expect(key == DayKey(year: 2026, month: 3, day: 9))
        #expect(key?.string == "2026-03-09")
        #expect(DayKey(string: "2026-13-01") == nil)
        #expect(DayKey(year: 2026, month: 12, day: 31).adding(days: 1, calendar: calendar) == DayKey(year: 2027, month: 1, day: 1))
        #expect(DayKey(year: 2026, month: 3, day: 1) < DayKey(year: 2026, month: 3, day: 2))
    }
}
