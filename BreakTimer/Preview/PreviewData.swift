import SwiftData
import SwiftUI

/// Sample states for previews: no breaks yet, break running, under 5 minutes left, overtime.
enum PreviewScenario: String, CaseIterable {
    case empty, running, low, overtime
}

extension BreakController {
    /// An in-memory controller (30-minute budget) filled for `scenario`, plus 30 days of history.
    static func preview(_ scenario: PreviewScenario, history: Bool = true, now: Date = .now) -> BreakController {
        // swiftlint:disable:next force_try
        let container = try! SharedModelContainer.make(inMemory: true)
        let context = container.mainContext

        func add(minutesAgo: Double, length: Double?) {
            let start = now.addingTimeInterval(-minutesAgo * 60)
            let end = length.map { start.addingTimeInterval($0 * 60) }
            context.insert(BreakSession(startedAt: start, endedAt: end, day: DayKey(start), budgetMinutes: 30, updatedAt: now))
        }

        switch scenario {
        case .empty:
            break
        case .running: // 8 + 6 = 14 min used, 16 left
            add(minutesAgo: 150, length: 8)
            add(minutesAgo: 6, length: nil)
        case .low: // 10 + 12 + 4.5 = 26.5 min used, 3:30 left
            add(minutesAgo: 180, length: 10)
            add(minutesAgo: 90, length: 12)
            add(minutesAgo: 4.5, length: nil)
        case .overtime: // 15 + 10 + 8 = 33 min used, 3 min over
            add(minutesAgo: 200, length: 15)
            add(minutesAgo: 100, length: 10)
            add(minutesAgo: 8, length: nil)
        }
        if history {
            // Deterministic sample history: the budget was 45 minutes until 12 days ago.
            let calendar = Calendar.current
            let minutesPattern: [Double] = [22, 31, 18, 27, 40, 12, 25, 33, 29, 15, 36, 24, 19, 28]
            for offset in 1...30 {
                let day = DayKey(now).adding(days: -offset)
                let used = minutesPattern[offset % minutesPattern.count]
                let budget = offset > 12 ? 45 : 30
                guard offset % 7 != 0 else { continue } // a few days without breaks
                let start = calendar.date(byAdding: .hour, value: 10, to: day.startDate()) ?? day.startDate()
                let first = used * 0.6
                context.insert(BreakSession(startedAt: start, endedAt: start.addingTimeInterval(first * 60), day: day, budgetMinutes: budget, updatedAt: now))
                let second = start.addingTimeInterval(3 * 3600)
                context.insert(BreakSession(startedAt: second, endedAt: second.addingTimeInterval((used - first) * 60), day: day, budgetMinutes: budget, updatedAt: now))
            }
        }
        try? context.save()
        return BreakController(container: container, budgetMinutes: 30, isPreview: true)
    }
}

extension View {
    func previewEnvironment(_ scenario: PreviewScenario, appearance: AppAppearance = .dark, signedIn: Bool = true, history: Bool = true) -> some View {
        let controller = BreakController.preview(scenario, history: history)
        return environment(controller)
            .environment(AppSettings(appearance: appearance))
            .environment(AuthService.preview(signedIn: signedIn))
            .environment(SyncService(controller: controller, client: nil))
            .preferredColorScheme(appearance.colorScheme)
            .tint(Theme.accent)
    }
}
