import Foundation
import WidgetKit

enum WidgetKind {
    static let home = "BreakTimerHomeWidget"
    static let lockScreen = "BreakTimerLockScreenWidget"
}

/// Reloads all widget timelines whenever break data, the budget or the appearance changes.
@MainActor
final class WidgetReloader: BreakEffect {
    static let shared = WidgetReloader()

    func breakStateDidChange(_ change: BreakChange, controller: BreakController) {
        Self.reloadAll(reason: String(describing: change))
    }

    static func reloadAll(reason: String) {
        WidgetCenter.shared.reloadAllTimelines()
        Log.info(.widget, "Widget timelines reloaded (\(reason))")
    }
}
