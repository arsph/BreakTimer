import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthService.self) private var auth

    var body: some View {
        @Bindable var auth = auth
        Group {
            switch auth.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                AuthView()
            case .signedIn:
                MainTabView()
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(settings.appearance.colorScheme)
        .animation(.smooth, value: auth.state)
        .sheet(isPresented: $auth.isResettingPassword) {
            NewPasswordView(purpose: .reset)
                .interactiveDismissDisabled()
        }
        .onOpenURL { url in
            Log.info(.lifecycle, "Opened via URL \(url.scheme ?? "")://\(url.host() ?? "")")
            Task { await auth.handleDeepLink(url) }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Heute", systemImage: "cup.and.saucer.fill") }
            HistoryView()
                .tabItem { Label("Verlauf", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
    }
}

#Preview("Dunkel") {
    RootView()
        .previewEnvironment(.running)
}

#Preview("Hell") {
    RootView()
        .previewEnvironment(.running, appearance: .light)
}

#Preview("Abgemeldet") {
    RootView()
        .previewEnvironment(.empty, signedIn: false)
}
