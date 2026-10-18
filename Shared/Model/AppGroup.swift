import Foundation
import os

/// The App Group shared by the app and the widget extension.
/// The identifier comes from the `AppGroupIdentifier` Info.plist key (group.$(BUNDLE_ID_PREFIX)).
enum AppGroup {
    static let identifier: String =
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String) ?? ""

    static let containerURL: URL = {
        if !identifier.isEmpty,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        // Without the entitlement (e.g. an unsigned build) fall back to the process's own container.
        // Uses os.Logger directly: Log depends on this value.
        Logger(subsystem: "BreakTimer", category: "lifecycle")
            .error("App Group container unavailable for '\(identifier, privacy: .public)', using Application Support")
        let fallback = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()

    /// UserDefaults is thread-safe; it just isn't annotated as Sendable.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: identifier.isEmpty ? nil : identifier) ?? .standard
}
