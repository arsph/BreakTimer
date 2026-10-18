import SwiftUI

enum CredentialRules {
    static let minPasswordLength = 8

    static func isValidEmail(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]{2,}/) != nil
    }

    static func emailMessage(_ email: String) -> String? {
        isValidEmail(email) ? nil : String(localized: "Bitte gib eine gültige E-Mail-Adresse ein.")
    }

    static func newPasswordMessage(_ password: String) -> String? {
        password.count >= minPasswordLength ? nil : String(localized: "Mindestens \(minPasswordLength) Zeichen.")
    }
}

/// Text field in the app's rounded style with an inline validation message.
struct AuthTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(title, text: $text)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .authFieldStyle()
            InlineMessage(text: message)
        }
    }
}

/// Password field with show/hide toggle. `isNew` enables iOS strong-password suggestions.
struct PasswordField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var isNew: Bool
    var message: String?
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Group {
                    if isVisible {
                        TextField(title, text: $text)
                    } else {
                        SecureField(title, text: $text)
                    }
                }
                .textContentType(isNew ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVisible ? "Passwort verbergen" : "Passwort anzeigen")
            }
            .authFieldStyle()
            InlineMessage(text: message)
        }
    }
}

struct InlineMessage: View {
    var text: String?
    var color: Color = Theme.overtime

    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(color)
                .padding(.leading, 4)
                .transition(.opacity)
        }
    }
}

/// Full-width primary button with a spinner while busy.
struct AuthPrimaryButton: View {
    let title: LocalizedStringKey
    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().tint(.white) }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .prominentActionStyle()
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Theme.accent)
    }
}

extension View {
    func authFieldStyle() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
