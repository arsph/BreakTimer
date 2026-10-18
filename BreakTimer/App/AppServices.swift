import Foundation

/// Owns the app's long-lived services and wires them together.
/// Created at launch, also when iOS launches the app in the background to run an App Intent.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let controller: BreakController
    let settings: AppSettings
    let auth: AuthService
    let sync: SyncService

    private init() {
        controller = BreakController.shared
        settings = AppSettings()
        auth = AuthService()
        sync = SyncService(controller: controller)

        controller.register(sync)
        sync.isSignedIn = { [auth] in auth.account != nil }
        auth.onSignedIn = { [sync] _ in
            Task { await sync.syncNow(reason: "signed in") }
        }
        auth.clearLocalData = { [weak self] includingLogs in
            await self?.clearLocalData(includingLogs: includingLogs)
        }
        auth.start()
    }

    /// Called when the app comes to the foreground.
    func didBecomeActive() {
        controller.reloadFromStore()
        sync.schedule(reason: "app foreground", delay: .zero)
    }

    /// Sign-out: all break data and settings. Account deletion: logs too.
    private func clearLocalData(includingLogs: Bool) async {
        SharedDefaults.reset()
        controller.deleteAllLocalData() // also ends the Live Activity, cancels notifications, reloads widgets
        settings.reload()
        sync.refreshUnsyncedCount()
        if includingLogs {
            await LogFiles.deleteAll()
        }
    }
}
