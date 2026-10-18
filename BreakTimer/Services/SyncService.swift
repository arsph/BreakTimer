import Foundation
import Observation
import Supabase

/// Offline-first sync: SwiftData is the source of truth on the device. Unsynced changes
/// (`syncedAt < updatedAt`, including soft deletes) are pushed as upserts; then the budget setting
/// and the last 30 days of sessions are pulled. Conflicts: latest `updated_at` wins (enforced by
/// a trigger on the server and by `BreakController.mergeRemote` on the device).
///
/// Runs on app foreground, after a break ends or a session changes, after a budget change,
/// after sign-in, and from Settings.
@Observable
@MainActor
final class SyncService: BreakEffect {
    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastSuccessfulSync: Date? = SharedDefaults.lastSuccessfulSync
    private(set) var unsyncedCount = 0

    /// Whether a user is signed in (set by the app).
    @ObservationIgnored var isSignedIn: () -> Bool = { false }

    private let controller: BreakController
    private let client: SupabaseClient?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var runAgain = false

    static let pullDays = 30

    init(controller: BreakController, client: SupabaseClient? = SupabaseBackend.client) {
        self.controller = controller
        self.client = client
        refreshUnsyncedCount()
    }

    func breakStateDidChange(_ change: BreakChange, controller: BreakController) {
        refreshUnsyncedCount()
        switch change {
        case .ended, .edited, .deleted, .budgetChanged:
            schedule(reason: change.description)
        case .started, .reloaded:
            break
        }
    }

    /// Syncs shortly, coalescing bursts of changes (e.g. tapping the budget stepper).
    func schedule(reason: String, delay: Duration = .seconds(1.5)) {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await syncNow(reason: reason)
        }
    }

    func syncNow(reason: String) async {
        guard let client else { return }
        guard isSignedIn() else {
            Log.debug(.sync, "Sync skipped (\(reason)): not signed in")
            return
        }
        if isSyncing {
            runAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        let started = Date()
        do {
            let result = try await perform(client: client)
            let duration = String(format: "%.2f", Date().timeIntervalSince(started))
            lastError = nil
            lastSuccessfulSync = .now
            SharedDefaults.lastSuccessfulSync = lastSuccessfulSync
            Log.info(.sync, "Sync finished (\(reason)): pushed \(result.pushedSessions) sessions\(result.pushedSettings ? " + settings" : ""), pulled \(result.pulledSessions) sessions (\(result.appliedSessions) applied)\(result.appliedSettings ? " + settings" : ""), \(duration)s")
        } catch is CancellationError {
            Log.debug(.sync, "Sync cancelled (\(reason))")
        } catch {
            let duration = String(format: "%.2f", Date().timeIntervalSince(started))
            lastError = BackendError.userMessage(error)
            Log.error(.sync, "Sync failed (\(reason)) after \(duration)s: \(BackendError.logDescription(error))")
        }
        refreshUnsyncedCount()

        if runAgain {
            runAgain = false
            await syncNow(reason: "changes during sync")
        }
    }

    func refreshUnsyncedCount() {
        unsyncedCount = controller.unsyncedRecords().count + (SharedDefaults.budgetNeedsSync ? 1 : 0)
    }

    // MARK: Sync steps

    private struct Result {
        var pushedSessions = 0
        var pushedSettings = false
        var pulledSessions = 0
        var appliedSessions = 0
        var appliedSettings = false
    }

    private func perform(client: SupabaseClient) async throws -> Result {
        var result = Result()

        // 1. Push sessions changed on this device.
        let dirty = controller.unsyncedRecords()
        for chunk in stride(from: 0, to: dirty.count, by: 500).map({ Array(dirty[$0..<min($0 + 500, dirty.count)]) }) {
            try await client.from("break_sessions")
                .upsert(chunk.map(RemoteSession.init), onConflict: "id", returning: .minimal)
                .execute()
            controller.markSynced(chunk.map { (id: $0.id, updatedAt: $0.updatedAt) })
            result.pushedSessions += chunk.count
        }

        // 2. Push the budget setting if it changed here.
        if SharedDefaults.budgetNeedsSync, let updatedAt = SharedDefaults.budgetUpdatedAt {
            let settings = RemoteSettings(dailyBudgetMinutes: controller.budgetMinutes, updatedAt: updatedAt)
            try await client.from("user_settings")
                .upsert(settings, onConflict: "user_id", returning: .minimal)
                .execute()
            SharedDefaults.budgetSyncedAt = updatedAt
            result.pushedSettings = true
        }

        // 3. Pull the budget setting (follows the user to a new phone).
        let remoteSettings: [RemoteSettings] = try await client.from("user_settings")
            .select("daily_budget_minutes,updated_at")
            .limit(1)
            .execute()
            .value
        if let remote = remoteSettings.first {
            result.appliedSettings = applySettings(remote)
        }

        // 4. Pull the last 30 days of sessions and merge them.
        let since = DayKey(.now).adding(days: -Self.pullDays)
        let remoteSessions: [RemoteSession] = try await client.from("break_sessions")
            .select("id,started_at,ended_at,day,budget_minutes,updated_at,deleted_at")
            .gte("day", value: since.string)
            .execute()
            .value
        result.pulledSessions = remoteSessions.count
        result.appliedSessions = controller.mergeRemote(remoteSessions.map(\.record))
        return result
    }

    /// Applies the server's budget if it is newer than the local one.
    private func applySettings(_ remote: RemoteSettings) -> Bool {
        let local = SharedDefaults.budgetUpdatedAt ?? .distantPast
        guard remote.updatedAt.timeIntervalSince(local) > 0.001 else { return false }
        if remote.dailyBudgetMinutes == controller.budgetMinutes {
            SharedDefaults.budgetUpdatedAt = remote.updatedAt
        } else {
            controller.setBudget(minutes: remote.dailyBudgetMinutes, updatedAt: remote.updatedAt, fromSync: true)
        }
        SharedDefaults.budgetSyncedAt = remote.updatedAt
        return true
    }
}

// MARK: - Rows

/// A `break_sessions` row. Encodes every column (nil as null), so all rows in a bulk upsert
/// have the same keys. user_id is filled in by the server (default auth.uid()).
private struct RemoteSession: Codable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let day: String
    let budgetMinutes: Int
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case day
        case budgetMinutes = "budget_minutes"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(_ record: SessionRecord) {
        id = record.id
        startedAt = record.startedAt
        endedAt = record.endedAt
        day = record.day
        budgetMinutes = record.budgetMinutes
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(day, forKey: .day)
        try container.encode(budgetMinutes, forKey: .budgetMinutes)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    var record: SessionRecord {
        SessionRecord(
            id: id, startedAt: startedAt, endedAt: endedAt, day: day,
            budgetMinutes: budgetMinutes, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}

/// A `user_settings` row (user_id filled in by the server).
private struct RemoteSettings: Codable, Sendable {
    let dailyBudgetMinutes: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case dailyBudgetMinutes = "daily_budget_minutes"
        case updatedAt = "updated_at"
    }
}
