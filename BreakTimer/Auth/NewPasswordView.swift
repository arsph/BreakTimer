import SwiftUI

/// Sets a new password: after opening a reset link, or "Passwort ändern" in Settings.
struct NewPasswordView: View {
    enum Purpose {
        case reset, change
    }

    let purpose: Purpose
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var touched = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var done = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 24)
                        Text("Dein Passwort wurde geändert.")
                            .font(.headline)
                        AuthPrimaryButton(title: "Fertig", isBusy: false) { close() }
                    } else {
                        Text(purpose == .reset
                             ? "Lege ein neues Passwort für dein Konto fest."
                             : "Wähle ein neues Passwort mit mindestens 8 Zeichen.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PasswordField(title: "Neues Passwort", text: $password, isNew: true,
                                      message: touched ? CredentialRules.newPasswordMessage(password) : nil)
                        PasswordField(title: "Passwort wiederholen", text: $confirmation, isNew: true,
                                      message: touched && confirmation != password ? String(localized: "Die Passwörter stimmen nicht überein.") : nil)
                        InlineMessage(text: errorMessage)
                        AuthPrimaryButton(title: "Passwort speichern", isBusy: isBusy, action: save)
                            .disabled(isBusy)
                    }
                }
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(purpose == .reset ? "Neues Passwort" : "Passwort ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !done {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { close() }
                    }
                }
            }
        }
    }

    private func save() {
        touched = true
        guard CredentialRules.newPasswordMessage(password) == nil, password == confirmation, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await auth.updatePassword(password)
                done = true
            } catch {
                errorMessage = BackendError.userMessage(error)
            }
        }
    }

    private func close() {
        auth.isResettingPassword = false
        dismiss()
    }
}

#Preview("Zurücksetzen · Dunkel") {
    NewPasswordView(purpose: .reset)
        .environment(AuthService.preview(signedIn: true))
        .preferredColorScheme(.dark)
}

#Preview("Ändern · Hell") {
    NewPasswordView(purpose: .change)
        .environment(AuthService.preview(signedIn: true))
        .preferredColorScheme(.light)
}
