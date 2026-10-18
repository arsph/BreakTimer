import Foundation
import SwiftData

/// One break. Timestamps are absolute instants (stored and synced as UTC);
/// `day` is the local calendar date of `startedAt` as "yyyy-MM-dd".
@Model
final class BreakSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    /// nil while the break is running.
    var endedAt: Date?
    var day: String
    /// The budget in effect for this session's day.
    var budgetMinutes: Int
    var updatedAt: Date
    /// Last successful push to Supabase; the session needs syncing while `syncedAt < updatedAt`.
    var syncedAt: Date?
    /// Local tombstone: kept until the delete has been pushed, then purged.
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        day: DayKey,
        budgetMinutes: Int,
        updatedAt: Date = .now,
        syncedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.day = day.string
        self.budgetMinutes = budgetMinutes
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
        self.deletedAt = deletedAt
    }

    var dayKey: DayKey { DayKey(string: day) ?? DayKey(startedAt) }
    var isRunning: Bool { endedAt == nil }
    var needsSync: Bool { syncedAt.map { $0 < updatedAt } ?? true }

    var snapshot: SessionSnapshot {
        SessionSnapshot(id: id, startedAt: startedAt, endedAt: endedAt, day: dayKey, budgetMinutes: budgetMinutes)
    }

    func duration(at now: Date) -> TimeInterval { snapshot.duration(at: now) }

    var record: SessionRecord {
        SessionRecord(
            id: id, startedAt: startedAt, endedAt: endedAt, day: day,
            budgetMinutes: budgetMinutes, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}

/// A session as exchanged with the server, independent of SwiftData and Supabase.
struct SessionRecord: Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let day: String
    let budgetMinutes: Int
    let updatedAt: Date
    let deletedAt: Date?
}

enum SharedModelContainer {
    static let storeURL = AppGroup.containerURL.appending(path: "BreakTimer.store")

    /// The store in the App Group container, shared by the app and the widget extension.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: storeURL)
        return try ModelContainer(for: BreakSession.self, configurations: configuration)
    }
}
