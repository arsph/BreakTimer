import Foundation
import Observation
import SwiftData

/// Where a start/end action came from (logged with every break).
enum BreakSource: String, Sendable {
    case app, widget, liveActivity
}

enum BreakChange: Sendable, Equatable, CustomStringConvertible {
    case started(BreakSource)
    case ended(BreakSource)
    case edited
    case deleted
    case budgetChanged
    /// Data changed outside the controller (e.g. sync pulled new rows).
    case reloaded

    var description: String {
        switch self {
        case .started(let source): "break started via \(source.rawValue)"
        case .ended(let source): "break ended via \(source.rawValue)"
        case .edited: "session edited"
        case .deleted: "session deleted"
        case .budgetChanged: "budget changed"
        case .reloaded: "data reloaded"
        }
    }
}

/// Reacts to break changes: notifications, Live Activity, widget reloads, sync.
@MainActor
protocol BreakEffect: AnyObject {
    func breakStateDidChange(_ change: BreakChange, controller: BreakController)
}

/// Single entry point for every change to break data, used by the app UI and by App Intents.
/// Every mutation saves, then informs the registered effects.
@Observable
@MainActor
final class BreakController {
    /// The controller of this process, with the shared effects (widgets, notifications,
    /// Live Activity) registered. App-only effects such as sync register themselves.
    static let shared: BreakController = {
        let controller: BreakController
        do {
            controller = BreakController(container: try SharedModelContainer.make())
        } catch {
            Log.error(.lifecycle, "Opening the shared store failed, using an in-memory store", error: error)
            // swiftlint:disable:next force_try
            controller = BreakController(container: try! SharedModelContainer.make(inMemory: true))
        }
        controller.register(WidgetReloader.shared)
        controller.register(NotificationScheduler.shared)
        controller.register(LiveActivityManager.shared)
        return controller
    }()

    let container: ModelContainer
    /// Replaced on `reloadFromStore()`, so changes written by the other process are picked up.
    @ObservationIgnored private var context: ModelContext
    private let isPreview: Bool
    @ObservationIgnored private var effects: [any BreakEffect] = []

    /// Sessions of the active day (see `BudgetEngine.activeDay`), oldest first, without deleted ones.
    private(set) var activeSessions: [BreakSession] = []
    private(set) var runningSession: BreakSession?
    private(set) var activeDay: DayKey
    /// Today's budget (the current setting).
    private(set) var budgetMinutes: Int
    /// Increments on every change, so views showing derived data can refresh.
    private(set) var revision = 0

    init(container: ModelContainer, budgetMinutes: Int? = nil, isPreview: Bool = false) {
        self.container = container
        self.context = ModelContext(container)
        self.isPreview = isPreview
        self.budgetMinutes = budgetMinutes ?? SharedDefaults.dailyBudgetMinutes
        self.activeDay = DayKey(.now)
        refresh()
    }

    func register(_ effect: any BreakEffect) {
        guard !effects.contains(where: { $0 === effect }) else { return }
        effects.append(effect)
    }

    // MARK: Reading

    /// Drops cached objects and re-reads the store (after returning to the foreground, since the
    /// widget extension may have written to the store in the meantime).
    func reloadFromStore() {
        if !context.hasChanges {
            context = ModelContext(container)
        }
        refresh()
        // Lets effects reconcile, e.g. start a missing Live Activity or reschedule notifications.
        notify(.reloaded)
    }

    /// Reloads from the store, e.g. after returning to the foreground, at midnight, or after a sync.
    func refresh(now: Date = .now) {
        if !isPreview { budgetMinutes = SharedDefaults.dailyBudgetMinutes }
        runningSession = fetch(#Predicate { $0.endedAt == nil && $0.deletedAt == nil }).first
        activeDay = runningSession?.dayKey ?? DayKey(now)
        let key = activeDay.string
        activeSessions = fetch(#Predicate { $0.day == key && $0.deletedAt == nil })
        revision += 1
    }

    func status(at now: Date) -> DayStatus {
        BudgetEngine.status(day: activeDay, sessions: activeSessions.map(\.snapshot), budgetMinutes: budgetMinutes, now: now)
    }

    /// Non-deleted sessions from `start` through `end` (inclusive), oldest first.
    func sessions(from start: DayKey, through end: DayKey) -> [BreakSession] {
        let lower = start.string
        let upper = end.string
        return fetch(#Predicate { $0.day >= lower && $0.day <= upper && $0.deletedAt == nil })
    }

    /// Sessions whose latest change has not been pushed yet (including local deletes).
    func unsyncedSessions() -> [BreakSession] {
        fetch(#Predicate { _ in true }).filter(\.needsSync)
    }

    func unsyncedRecords() -> [SessionRecord] {
        unsyncedSessions().map(\.record)
    }

    // MARK: Breaks

    /// Starts a break unless one is already running.
    @discardableResult
    func startBreak(source: BreakSource, at now: Date = .now) -> Bool {
        refresh(now: now)
        if runningSession != nil {
            Log.warn(.timer, "Start ignored (source: \(source.rawValue)): a break is already running")
            return false
        }
        let session = BreakSession(startedAt: now, day: DayKey(now), budgetMinutes: budgetMinutes, updatedAt: now)
        context.insert(session)
        guard save("starting a break") else { return false }
        refresh(now: now)
        Log.info(.timer, "Break started (source: \(source.rawValue)), remaining \(signedClock(status(at: now).remaining))")
        notify(.started(source))
        return true
    }

    /// Ends the running break at `end` (defaults to now; earlier for a forgotten break).
    func endBreak(source: BreakSource, at end: Date = .now) {
        refresh()
        guard let session = runningSession else {
            Log.warn(.timer, "End ignored (source: \(source.rawValue)): no break is running")
            return
        }
        let now = Date()
        session.endedAt = min(max(end, session.startedAt), now)
        session.updatedAt = now
        guard save("ending a break") else { return }
        refresh(now: now)
        let duration = DurationFormat.clock(seconds: Int(session.duration(at: now)))
        let remaining = signedClock(BudgetEngine.status(
            day: session.dayKey, sessions: snapshotsOfDay(session.dayKey), budgetMinutes: budgetMinutes(for: session.dayKey), now: now
        ).remaining)
        Log.info(.timer, "Break ended (source: \(source.rawValue)), duration \(duration), remaining \(remaining)")
        notify(.ended(source))
    }

    /// Changes start/end of a session after validating it against the day's other sessions.
    func update(_ original: BreakSession, start: Date, end: Date?) throws(SessionEditError) {
        guard let session = resolve(original) else { return }
        let now = Date()
        let others = snapshotsOfDay(DayKey(start)) + snapshotsOfDay(session.dayKey)
        if let error = BudgetEngine.validateEdit(sessionID: session.id, start: start, end: end, sessions: others, now: now) {
            Log.info(.timer, "Edit rejected for session \(session.id): \(error)")
            throw error
        }
        let edited = BudgetEngine.edited(session.snapshot, start: start, end: end)
        session.startedAt = edited.startedAt
        session.endedAt = edited.endedAt
        session.day = edited.day.string
        session.updatedAt = now
        guard save("editing a session") else { return }
        refresh(now: now)
        Log.info(.timer, "Session \(session.id) edited, remaining \(signedClock(status(at: now).remaining))")
        notify(.edited)
    }

    /// Soft-deletes a session; sync pushes the delete, then the row is purged.
    func delete(_ original: BreakSession) {
        guard let session = resolve(original) else { return }
        let now = Date()
        let wasRunning = session.isRunning
        session.deletedAt = now
        session.updatedAt = now
        if wasRunning { session.endedAt = now }
        guard save("deleting a session") else { return }
        refresh(now: now)
        Log.info(.timer, "Session \(session.id) deleted\(wasRunning ? " (was running)" : ""), remaining \(signedClock(status(at: now).remaining))")
        notify(wasRunning ? .ended(.app) : .deleted)
    }

    // MARK: Budget

    /// Applies a new daily budget to today (including a running break) and all future days.
    func setBudget(minutes: Int, updatedAt: Date = .now, fromSync: Bool = false) {
        let value = BudgetRules.clamp(minutes)
        guard value != budgetMinutes else { return }
        let previous = budgetMinutes
        budgetMinutes = value
        if !isPreview {
            SharedDefaults.dailyBudgetMinutes = value
            SharedDefaults.budgetUpdatedAt = updatedAt
        }

        let now = Date()
        let today = DayKey(now)
        for session in Set([today, activeDay]).flatMap({ sessionsOfDay($0) }) {
            let changed = BudgetEngine.applyingBudgetChange(value, to: [session.snapshot], on: session.dayKey)[0]
            session.budgetMinutes = changed.budgetMinutes
            session.updatedAt = now
        }
        save("changing the budget")
        refresh(now: now)
        Log.info(.budget, "Daily budget changed \(previous) → \(value) min\(fromSync ? " (from sync)" : ""), remaining \(signedClock(status(at: now).remaining))")
        notify(.budgetChanged)
    }

    // MARK: Sync support

    /// Marks pushed sessions as synced, unless they changed again while the push was running.
    func markSynced(_ pushed: [(id: UUID, updatedAt: Date)]) {
        let byID = Dictionary(pushed.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: max)
        for session in fetch(#Predicate { _ in true }) {
            guard let pushedAt = byID[session.id], session.updatedAt == pushedAt else { continue }
            session.syncedAt = pushedAt
        }
        save("marking sessions as synced")
        purgeSyncedTombstones()
    }

    /// Applies rows pulled from the server: "latest updated_at wins". Returns how many local rows changed.
    @discardableResult
    func mergeRemote(_ records: [SessionRecord]) -> Int {
        let local = Dictionary(fetch(#Predicate { _ in true }).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = 0
        for record in records {
            if let session = local[record.id] {
                // 1 ms tolerance: the server stores microseconds, Date round-trips may differ slightly.
                guard record.updatedAt.timeIntervalSince(session.updatedAt) > 0.001 else { continue }
                session.startedAt = record.startedAt
                session.endedAt = record.endedAt
                session.day = record.day
                session.budgetMinutes = record.budgetMinutes
                session.deletedAt = record.deletedAt
                session.updatedAt = record.updatedAt
                session.syncedAt = record.updatedAt
                changed += 1
            } else if record.deletedAt == nil {
                context.insert(BreakSession(
                    id: record.id, startedAt: record.startedAt, endedAt: record.endedAt,
                    day: DayKey(string: record.day) ?? DayKey(record.startedAt), budgetMinutes: record.budgetMinutes,
                    updatedAt: record.updatedAt, syncedAt: record.updatedAt
                ))
                changed += 1
            }
        }
        if changed > 0 {
            save("merging pulled sessions")
            purgeSyncedTombstones()
            refresh()
            notify(.reloaded)
        }
        return changed
    }

    /// Removes local tombstones whose delete has reached the server.
    func purgeSyncedTombstones() {
        let tombstones = fetch(#Predicate { $0.deletedAt != nil }).filter { !$0.needsSync }
        guard !tombstones.isEmpty else { return }
        for session in tombstones { context.delete(session) }
        save("purging deleted sessions")
    }

    /// Called after data changed outside the controller.
    func didReloadExternally() {
        refresh()
        notify(.reloaded)
    }

    /// Removes all break data from the device (sign-out, account deletion).
    func deleteAllLocalData() {
        do {
            try context.delete(model: BreakSession.self)
            try context.save()
            Log.info(.auth, "Local break data deleted")
        } catch {
            Log.error(.auth, "Deleting local break data failed", error: error)
        }
        refresh()
        notify(.reloaded)
    }

    @discardableResult
    func save(_ action: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            Log.error(.timer, "Saving failed while \(action)", error: error)
            context.rollback()
            return false
        }
    }

    // MARK: Private

    private func notify(_ change: BreakChange) {
        revision += 1
        guard !isPreview else { return }
        for effect in effects { effect.breakStateDidChange(change, controller: self) }
    }

    private func fetch(_ predicate: Predicate<BreakSession>) -> [BreakSession] {
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.startedAt)])
        do {
            return try context.fetch(descriptor)
        } catch {
            Log.error(.timer, "Fetching sessions failed", error: error)
            return []
        }
    }

    /// The same session in the current context (views may still hold an object from a replaced context).
    private func resolve(_ session: BreakSession) -> BreakSession? {
        if session.modelContext === context { return session }
        let id = session.id
        let match = fetch(#Predicate { $0.id == id }).first
        if match == nil { Log.warn(.timer, "Session \(id) no longer exists") }
        return match
    }

    private func sessionsOfDay(_ day: DayKey) -> [BreakSession] {
        let key = day.string
        return fetch(#Predicate { $0.day == key && $0.deletedAt == nil })
    }

    private func snapshotsOfDay(_ day: DayKey) -> [SessionSnapshot] {
        sessionsOfDay(day).map(\.snapshot)
    }

    private func budgetMinutes(for day: DayKey) -> Int {
        day == DayKey(.now) || day == activeDay
            ? budgetMinutes
            : BudgetEngine.budgetMinutes(for: day, sessions: snapshotsOfDay(day), fallback: budgetMinutes)
    }

    private func signedClock(_ remaining: TimeInterval) -> String {
        (remaining < 0 ? "+" : "") + DurationFormat.clock(remaining: remaining) + (remaining < 0 ? " over" : "")
    }
}
