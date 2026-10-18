import SwiftUI
import WidgetKit

@main
struct BreakTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        BreakTimerHomeWidget()
        BreakTimerLockScreenWidget()
        BreakLiveActivity()
    }
}
