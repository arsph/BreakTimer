import ActivityKit
import Foundation

/// Keeps the Live Activity in line with the running break: starts it when a break starts,
/// updates it when the budget or appearance changes, ends it when the break ends.
@MainActor
final class LiveActivityManager: BreakEffect {
    static let shared = LiveActivityManager()

    private var pending: [UUID: Task<Void, Never>] = [:]

    func breakStateDidChange(_ change: BreakChange, controller: BreakController) {
        sync(with: controller, reason: change.description)
    }

    /// Brings the activities in line with the controller's state.
    func sync(with controller: BreakController, reason: String) {
        let activities = Activity<BreakActivityAttributes>.activities
        let now = Date()

        guard
            let running = controller.runningSession,
            let state = BreakActivityAttributes.ContentState(status: controller.status(at: now), appearance: SharedDefaults.appearance)
        else {
            for activity in activities { end(activity, reason: reason) }
            return
        }

        let content = ActivityContent(state: state, staleDate: state.exhaustedAt)
        for activity in activities where activity.attributes.sessionID != running.id {
            end(activity, reason: "belongs to another session")
        }

        if let existing = activities.first(where: { $0.attributes.sessionID == running.id }) {
            guard existing.content.state != state else { return }
            let id = existing.id
            track {
                await Self.update(activityID: id, content: content)
                Log.info(.liveActivity, "Live Activity updated (\(reason)), budget runs out at \(state.exhaustedAt.formatted(date: .omitted, time: .standard))")
            }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.warn(.liveActivity, "Live Activities are disabled for BreakTimer, not starting one")
            return
        }
        do {
            let attributes = BreakActivityAttributes(sessionID: running.id, startedAt: running.startedAt)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            Log.info(.liveActivity, "Live Activity started (\(reason)) id \(activity.id) in \(Log.process) process")
        } catch {
            Log.error(.liveActivity, "Starting the Live Activity failed (\(reason)) in \(Log.process) process", error: error)
        }
    }

    /// Waits for pending ActivityKit calls, so an App Intent doesn't finish before they're done.
    func drain() async {
        for task in pending.values { await task.value }
    }

    private func end(_ activity: Activity<BreakActivityAttributes>, reason: String) {
        let id = activity.id
        track {
            await Self.end(activityID: id)
            Log.info(.liveActivity, "Live Activity ended (\(reason)) id \(id)")
        }
    }

    // Activity isn't Sendable, so async calls look it up by id outside the main actor.

    private nonisolated static func update(activityID: String, content: ActivityContent<BreakActivityAttributes.ContentState>) async {
        guard let activity = Activity<BreakActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.update(content)
    }

    private nonisolated static func end(activityID: String) async {
        guard let activity = Activity<BreakActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func track(_ work: @escaping @MainActor () async -> Void) {
        let id = UUID()
        pending[id] = Task {
            await work()
            self.pending[id] = nil
        }
    }
}
