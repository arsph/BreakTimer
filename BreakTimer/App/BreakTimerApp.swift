import SwiftUI
import UserNotifications

@main
struct BreakTimerApp: App {
    private let services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.info(.lifecycle, "App launch v\(AppInfo.version) (\(AppInfo.build)), iOS \(AppInfo.systemVersion), \(AppInfo.deviceModel)")
        LogFiles.applyRetention()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        services = AppServices.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.controller)
                .environment(services.settings)
                .environment(services.auth)
                .environment(services.sync)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Log.info(.lifecycle, "App entered foreground")
                services.didBecomeActive()
            case .background:
                Log.info(.lifecycle, "App entered background")
            default:
                break
            }
        }
    }
}
