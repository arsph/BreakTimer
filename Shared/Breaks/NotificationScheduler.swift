import Foundation
import UserNotifications

/// Local notifications for a running break: one at 5 minutes left, one when the budget is used up.
/// Rescheduled on every change (budget, edits) and cancelled when the break ends.
/// Permission is requested on the first break started in the app, never on launch.
@MainActor
final class NotificationScheduler: BreakEffect {
    static let shared = NotificationScheduler()

    enum Identifier {
        static let lowBudget = "break.lowBudget"
        static let budgetUsedUp = "break.budgetUsedUp"
        static let all = [lowBudget, budgetUsedUp]
    }

    private var pending: [UUID: Task<Void, Never>] = [:]

    func breakStateDidChange(_ change: BreakChange, controller: BreakController) {
        let askFrom: BreakSource? = if case .started(let source) = change { source } else { nil }
        reschedule(for: controller, askingPermissionFrom: askFrom)
    }

    /// Cancels the current notifications and schedules them again for the running break, if any.
    func reschedule(for controller: BreakController, askingPermissionFrom source: BreakSource? = nil) {
        let id = UUID()
        pending[id] = Task {
            await self.performReschedule(controller: controller, askingPermissionFrom: source)
            self.pending[id] = nil
        }
    }

    /// Waits for pending scheduling, so an App Intent doesn't finish before it's done.
    func drain() async {
        for task in pending.values { await task.value }
    }

    private func performReschedule(controller: BreakController, askingPermissionFrom source: BreakSource?) async {
        let center = UNUserNotificationCenter.current()
        let scheduled = await center.pendingNotificationRequests().filter { Identifier.all.contains($0.identifier) }
        center.removePendingNotificationRequests(withIdentifiers: Identifier.all)

        guard controller.runningSession != nil else {
            if !scheduled.isEmpty { Log.info(.notifications, "Break notifications cancelled") }
            return
        }

        guard await isAuthorized(center: center, askingFrom: source) else { return }

        let now = Date()
        let status = controller.status(at: now)
        if SharedDefaults.notifyLowBudget, let date = status.lowMarkAt, date > now.addingTimeInterval(1) {
            await schedule(
                Identifier.lowBudget, at: date, now: now, center: center,
                title: String(localized: "Noch 5 Minuten Pause"),
                body: String(localized: "Dein Pausenbudget für heute ist gleich aufgebraucht.")
            )
        }
        if SharedDefaults.notifyBudgetUsedUp, let date = status.exhaustedAt, date > now.addingTimeInterval(1) {
            await schedule(
                Identifier.budgetUsedUp, at: date, now: now, center: center,
                title: String(localized: "Pausenbudget aufgebraucht"),
                body: String(localized: "Ab jetzt zählt deine Pause als Überziehung.")
            )
        }
    }

    private func isAuthorized(center: UNUserNotificationCenter, askingFrom source: BreakSource?) async -> Bool {
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            // The system prompt can only appear while the app is in front.
            guard source == .app else {
                Log.info(.notifications, "Notification permission not asked yet; waiting for a break started in the app")
                return false
            }
            SharedDefaults.askedForNotifications = true
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                Log.info(.notifications, "Notification permission \(granted ? "granted" : "denied")")
            } catch {
                Log.error(.notifications, "Requesting notification permission failed", error: error)
            }
            status = await center.notificationSettings().authorizationStatus
        }
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            Log.debug(.notifications, "Notifications not allowed (status \(status.rawValue)), nothing scheduled")
            return false
        }
    }

    private func schedule(_ identifier: String, at date: Date, now: Date, center: UNUserNotificationCenter, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSince(now), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            Log.info(.notifications, "Scheduled \(identifier) for \(date.formatted(date: .omitted, time: .standard)) (in \(DurationFormat.clock(seconds: Int(date.timeIntervalSince(now)))))")
        } catch {
            Log.error(.notifications, "Scheduling \(identifier) failed", error: error)
        }
    }
}
