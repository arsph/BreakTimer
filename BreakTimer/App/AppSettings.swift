import Observation
import SwiftUI

/// Observable view of the app's small settings, persisted in the App Group's UserDefaults.
/// The daily budget lives in `BreakController`, because changing it has side effects on today's data.
@Observable
@MainActor
final class AppSettings {
    var appearance: AppAppearance = SharedDefaults.appearance {
        didSet {
            guard appearance != oldValue else { return }
            SharedDefaults.appearance = appearance
            Log.info(.settings, "Appearance changed to \(appearance.rawValue)")
            WidgetReloader.reloadAll(reason: "appearance changed")
            LiveActivityManager.shared.sync(with: BreakController.shared, reason: "appearance changed")
        }
    }

    var verboseLogging: Bool = SharedDefaults.verboseLogging {
        didSet {
            guard verboseLogging != oldValue else { return }
            // Log while INFO is still guaranteed to be written.
            Log.info(.settings, "Verbose logging \(verboseLogging ? "enabled" : "disabled")")
            SharedDefaults.verboseLogging = verboseLogging
        }
    }

    var notifyLowBudget: Bool = SharedDefaults.notifyLowBudget {
        didSet {
            guard notifyLowBudget != oldValue else { return }
            SharedDefaults.notifyLowBudget = notifyLowBudget
            Log.info(.settings, "5-minute notification \(notifyLowBudget ? "enabled" : "disabled")")
            NotificationScheduler.shared.reschedule(for: BreakController.shared)
        }
    }

    var notifyBudgetUsedUp: Bool = SharedDefaults.notifyBudgetUsedUp {
        didSet {
            guard notifyBudgetUsedUp != oldValue else { return }
            SharedDefaults.notifyBudgetUsedUp = notifyBudgetUsedUp
            Log.info(.settings, "Budget-used-up notification \(notifyBudgetUsedUp ? "enabled" : "disabled")")
            NotificationScheduler.shared.reschedule(for: BreakController.shared)
        }
    }

    init(appearance: AppAppearance? = nil) {
        if let appearance { self.appearance = appearance }
    }

    /// Re-reads everything after sign-out cleared the stored values.
    func reload() {
        appearance = SharedDefaults.appearance
        verboseLogging = SharedDefaults.verboseLogging
        notifyLowBudget = SharedDefaults.notifyLowBudget
        notifyBudgetUsedUp = SharedDefaults.notifyBudgetUsedUp
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var systemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
    }

    /// Hardware model identifier, e.g. "iPhone17,3" (or the simulated model in the Simulator).
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
