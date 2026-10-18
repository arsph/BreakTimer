import AppIntents
import Foundation

// Start/end buttons in widgets and the Live Activity. As LiveActivityIntents they run in the
// app's process (iOS launches it in the background if needed), which is required to start a
// Live Activity. The code also works if it ever runs in the widget extension: everything goes
// through the shared store, and every step is logged with the process it ran in.

struct StartBreakIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause starten"
    static let description = IntentDescription("Startet eine Pause und zieht sie vom Tagesbudget ab.")
    static let isDiscoverable = false

    @Parameter(title: "Quelle", default: "widget")
    var source: String

    init() {}

    init(source: BreakSource) {
        self.source = source.rawValue
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let origin = BreakSource(rawValue: source) ?? .widget
        Log.info(.widget, "StartBreakIntent (source: \(origin.rawValue)) running in \(Log.process) process")
        guard SharedDefaults.signedInUserID != nil else {
            Log.warn(.widget, "StartBreakIntent ignored: nobody is signed in")
            return .result()
        }
        BreakController.shared.startBreak(source: origin)
        await BreakEffectsDrain.run()
        return .result()
    }
}

struct EndBreakIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause beenden"
    static let description = IntentDescription("Beendet die laufende Pause.")
    static let isDiscoverable = false

    @Parameter(title: "Quelle", default: "widget")
    var source: String

    init() {}

    init(source: BreakSource) {
        self.source = source.rawValue
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let origin = BreakSource(rawValue: source) ?? .widget
        Log.info(.widget, "EndBreakIntent (source: \(origin.rawValue)) running in \(Log.process) process")
        guard SharedDefaults.signedInUserID != nil else {
            Log.warn(.widget, "EndBreakIntent ignored: nobody is signed in")
            return .result()
        }
        BreakController.shared.endBreak(source: origin)
        await BreakEffectsDrain.run()
        return .result()
    }
}

/// Waits until the Live Activity and notification changes triggered by an intent are done,
/// so iOS doesn't suspend the process halfway.
@MainActor
enum BreakEffectsDrain {
    static func run() async {
        await LiveActivityManager.shared.drain()
        await NotificationScheduler.shared.drain()
    }
}
