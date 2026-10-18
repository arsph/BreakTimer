import SwiftUI

struct SettingsView: View {
    @Environment(BreakController.self) private var controller
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var presentation = SettingsPresentation()

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Stepper(value: budgetBinding, in: BudgetRules.minMinutes...BudgetRules.maxMinutes, step: BudgetRules.stepMinutes) {
                        LabeledContent("Tägliches Pausenbudget", value: String(localized: "\(controller.budgetMinutes) Min."))
                    }
                } header: {
                    Text("Pausenbudget")
                } footer: {
                    Text("Gilt sofort für heute, auch für eine laufende Pause, und für alle folgenden Tage.")
                }

                Section("Darstellung") {
                    Picker("Erscheinungsbild", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Button(action: openAppSettings) {
                        HStack {
                            Text("Sprache")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Text(currentLanguage)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint("Öffnet die Einstellungen von BreakTimer in der App „Einstellungen“.")
                } footer: {
                    Text("Die Sprache der App wählst du in den iOS-Einstellungen von BreakTimer.")
                }

                Section {
                    Toggle("Bei 5 Minuten Restzeit", isOn: $settings.notifyLowBudget)
                    Toggle("Wenn das Budget aufgebraucht ist", isOn: $settings.notifyBudgetUsedUp)
                } header: {
                    Text("Mitteilungen")
                } footer: {
                    Text("Erinnerungen während einer laufenden Pause.")
                }

                SyncSection()
                SupportSection()
                AccountSection()

                Section {
                    LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                }
            }
            .navigationTitle("Einstellungen")
            .sheet(item: $presentation.sheet, onDismiss: presentation.didDismiss) { sheet in
                presentation.content(for: sheet)
            }
        }
        .environment(presentation)
    }

    private var budgetBinding: Binding<Int> {
        Binding(get: { controller.budgetMinutes }, set: { controller.setBudget(minutes: $0) })
    }

    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "de"
        return Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    /// The app's own page in iOS Settings (value of UIApplication.openSettingsURLString),
    /// where iOS offers the per-app language choice.
    private func openAppSettings() {
        Log.info(.settings, "Opening iOS Settings for the app language")
        if let url = URL(string: "app-settings:") { openURL(url) }
    }
}

/// Sync status, last sync time and "Jetzt synchronisieren".
struct SyncSection: View {
    @Environment(SyncService.self) private var sync

    var body: some View {
        Section {
            LabeledContent("Zuletzt synchronisiert") {
                if let last = sync.lastSuccessfulSync {
                    Text(last, format: .relative(presentation: .named))
                } else {
                    Text("Noch nie")
                }
            }
            if sync.unsyncedCount > 0 {
                LabeledContent("Noch nicht synchronisiert", value: "\(sync.unsyncedCount)")
            }
            Button {
                Task { await sync.syncNow(reason: "manual") }
            } label: {
                HStack {
                    Text("Jetzt synchronisieren")
                    Spacer()
                    if sync.isSyncing { ProgressView() }
                }
            }
            .disabled(sync.isSyncing)
        } header: {
            Text("Synchronisierung")
        } footer: {
            if let error = sync.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.overtime)
            } else {
                Text("Deine Pausen werden auf dem Gerät gespeichert und mit deinem Konto abgeglichen.")
            }
        }
    }
}

/// Email, change password, sign out, delete account.
struct AccountSection: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(SettingsPresentation.self) private var presentation
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleteConfirmationText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var deleteKeyword: String { String(localized: "LÖSCHEN") }

    var body: some View {
        Section {
            LabeledContent("E-Mail", value: auth.account?.email ?? "–")
            Button("Passwort ändern") { presentation.sheet = .changePassword }
            Button("Abmelden") { confirmSignOut = true }
                .disabled(isWorking)
            Button("Konto löschen", role: .destructive) {
                deleteConfirmationText = ""
                confirmDelete = true
            }
            .disabled(isWorking)
        } header: {
            Text("Konto")
        } footer: {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.overtime)
            }
        }
        .confirmationDialog("Abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) {
                Task {
                    isWorking = true
                    await auth.signOut()
                    isWorking = false
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            if sync.unsyncedCount > 0 {
                Text("\(sync.unsyncedCount) Änderungen sind noch nicht synchronisiert und gehen beim Abmelden verloren. Alle Pausen und Einstellungen werden von diesem iPhone entfernt.")
            } else {
                Text("Alle Pausen und Einstellungen werden von diesem iPhone entfernt. Sie bleiben in deinem Konto gespeichert.")
            }
        }
        .alert("Konto endgültig löschen?", isPresented: $confirmDelete) {
            TextField(deleteKeyword, text: $deleteConfirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Konto löschen", role: .destructive, action: deleteAccount)
                .disabled(deleteConfirmationText.trimmingCharacters(in: .whitespaces).uppercased() != deleteKeyword)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Konto, alle Pausen, Einstellungen und das Protokoll werden unwiderruflich gelöscht. Gib zur Bestätigung „\(deleteKeyword)“ ein.")
        }
    }

    private func deleteAccount() {
        Task {
            isWorking = true
            errorMessage = nil
            do {
                try await auth.deleteAccount()
            } catch {
                errorMessage = BackendError.userMessage(error)
            }
            isWorking = false
        }
    }
}

#Preview("Dunkel") { SettingsView().previewEnvironment(.running) }
#Preview("Hell") { SettingsView().previewEnvironment(.running, appearance: .light) }
