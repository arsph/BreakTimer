import Foundation
import SwiftData
import WidgetKit

struct BreakEntry: TimelineEntry {
    let date: Date
    /// Status evaluated at `date`; live values come from `status.liveAnchor` / `status.exhaustedAt`.
    let status: DayStatus
    /// Up to three most recent sessions of the active day, newest first.
    let recent: [SessionSnapshot]
    let appearance: AppAppearance
    /// Widgets show a sign-in hint and no buttons while nobody is signed in.
    var isSignedIn = true
}

/// Builds widget timelines from the shared store. Widgets can't run code every second, so each
/// entry only marks a styling change (now, 5 minutes left, budget used up); countdowns and rings
/// animate on their own via timer-based Text and ProgressView.
struct BreakTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BreakEntry {
        WidgetSamples.entry(.running)
    }

    func getSnapshot(in context: Context, completion: @escaping (BreakEntry) -> Void) {
        if context.isPreview {
            completion(WidgetSamples.entry(.running))
        } else {
            completion(WidgetData.entries(now: .now).first ?? WidgetSamples.entry(.empty))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BreakEntry>) -> Void) {
        let now = Date()
        let entries = WidgetData.entries(now: now)
        // Reload after midnight so a new day starts with a full budget; everything else
        // triggers an explicit reload from the app or the intents.
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60 + 1)
        Log.info(.widget, "Timeline built with \(entries.count) entries, running: \(entries.first?.status.isRunning == true)")
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

enum WidgetData {
    private static let container: ModelContainer? = {
        do {
            return try SharedModelContainer.make()
        } catch {
            Log.error(.widget, "Widget could not open the shared store", error: error)
            return nil
        }
    }()

    /// Entries for now and for each upcoming styling change of a running break.
    static func entries(now: Date) -> [BreakEntry] {
        let (sessions, day) = load(now: now)
        let budget = SharedDefaults.dailyBudgetMinutes
        let appearance = SharedDefaults.appearance
        let isSignedIn = SharedDefaults.signedInUserID != nil
        let current = BudgetEngine.status(day: day, sessions: sessions, budgetMinutes: budget, now: now)

        // One second after each threshold: exactly at it, remaining is still 5:00 / 0:00,
        // which is not yet "low" / "overtime".
        let changes = [current.lowMarkAt, current.exhaustedAt]
            .compactMap { $0?.addingTimeInterval(1) }
            .filter { $0 > now }
        let recent = Array(sessions.sorted { $0.startedAt > $1.startedAt }.prefix(3))
        return ([now] + changes).map { date in
            BreakEntry(
                date: date,
                status: BudgetEngine.status(day: day, sessions: sessions, budgetMinutes: budget, now: date),
                recent: recent,
                appearance: appearance,
                isSignedIn: isSignedIn
            )
        }
    }

    private static func load(now: Date) -> (sessions: [SessionSnapshot], day: DayKey) {
        guard let container else { return ([], DayKey(now)) }
        let context = ModelContext(container)
        do {
            let running = try context.fetch(FetchDescriptor<BreakSession>(
                predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
            )).first
            let day = running?.dayKey ?? DayKey(now)
            let key = day.string
            let sessions = try context.fetch(FetchDescriptor<BreakSession>(
                predicate: #Predicate { $0.day == key && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.startedAt)]
            ))
            return (sessions.map(\.snapshot), day)
        } catch {
            Log.error(.widget, "Widget could not read sessions", error: error)
            return ([], DayKey(now))
        }
    }
}

/// Sample states for previews and the widget gallery: no breaks yet, running, under 5 minutes, overtime.
enum WidgetSamples {
    enum Scenario: CaseIterable {
        case empty, running, low, overtime
    }

    static func entry(_ scenario: Scenario, appearance: AppAppearance = .dark, now: Date = .now) -> BreakEntry {
        let day = DayKey(now)
        func session(minutesAgo: Double, length: Double?) -> SessionSnapshot {
            let start = now.addingTimeInterval(-minutesAgo * 60)
            return SessionSnapshot(id: UUID(), startedAt: start, endedAt: length.map { start.addingTimeInterval($0 * 60) }, day: day, budgetMinutes: 30)
        }
        let sessions: [SessionSnapshot] = switch scenario {
        case .empty: []
        case .running: [session(minutesAgo: 150, length: 8), session(minutesAgo: 6, length: nil)]
        case .low: [session(minutesAgo: 180, length: 10), session(minutesAgo: 90, length: 12), session(minutesAgo: 4.5, length: nil)]
        case .overtime: [session(minutesAgo: 200, length: 15), session(minutesAgo: 100, length: 10), session(minutesAgo: 8, length: nil)]
        }
        return BreakEntry(
            date: now,
            status: BudgetEngine.status(day: day, sessions: sessions, budgetMinutes: 30, now: now),
            recent: Array(sessions.reversed().prefix(3)),
            appearance: appearance
        )
    }
}
