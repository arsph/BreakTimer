import SwiftUI

/// Sign in or register with email and password. Any email address works.
struct AuthView: View {
    enum Mode: Hashable {
        case signIn, signUp
    }

    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var emailTouched = false
    @State private var passwordTouched = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showsForgotPassword = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        if let pending = auth.pendingConfirmationEmail {
            CheckInboxView(email: pending)
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                if !auth.isConfigured {
                    notice(String(localized: "Supabase ist nicht konfiguriert. Trage URL und Anon Key in Config.xcconfig ein."), systemImage: "wrench.and.screwdriver")
                }
                if let linkError = auth.linkError {
                    notice(linkError, systemImage: "link.badge.plus")
                }

                Picker("Modus", selection: $mode) {
                    Text("Anmelden").tag(Mode.signIn)
                    Text("Registrieren").tag(Mode.signUp)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 14) {
                    AuthTextField(title: "E-Mail-Adresse", text: $email, message: emailTouched ? CredentialRules.emailMessage(email) : nil)
                        .focused($focus, equals: .email)
                        .onSubmit { emailTouched = true; focus = .password }

                    PasswordField(
                        title: "Passwort",
                        text: $password,
                        isNew: mode == .signUp,
                        message: passwordMessage
                    )
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                }

                VStack(spacing: 14) {
                    InlineMessage(text: errorMessage)
                    AuthPrimaryButton(title: mode == .signIn ? "Anmelden" : "Konto erstellen", isBusy: isBusy, action: submit)
                        .disabled(isBusy || !auth.isConfigured)

                    if mode == .signIn {
                        Button("Passwort vergessen?") { showsForgotPassword = true }
                            .font(.subheadline)
                    } else {
                        Text("Nach der Registrierung bekommst du eine E-Mail, um deine Adresse zu bestätigen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: mode)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: errorMessage)
        .onChange(of: mode) {
            errorMessage = nil
            passwordTouched = false
        }
        .onChange(of: email) { errorMessage = nil }
        .onChange(of: password) { errorMessage = nil }
        .sheet(isPresented: $showsForgotPassword) {
            ForgotPasswordView(email: email)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text("BreakTimer")
                .font(.largeTitle.weight(.bold))
            Text("Behalte dein tägliches Pausenbudget im Blick.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard(cornerRadius: 14)
    }

    private var passwordMessage: String? {
        guard passwordTouched else { return nil }
        if mode == .signUp { return CredentialRules.newPasswordMessage(password) }
        return password.isEmpty ? String(localized: "Bitte gib dein Passwort ein.") : nil
    }

    private var isValid: Bool {
        CredentialRules.isValidEmail(email)
            && (mode == .signUp ? CredentialRules.newPasswordMessage(password) == nil : !password.isEmpty)
    }

    private func submit() {
        emailTouched = true
        passwordTouched = true
        guard isValid, !isBusy else { return }
        focus = nil
        isBusy = true
        errorMessage = nil
        let email = email.trimmingCharacters(in: .whitespaces)
        Task {
            defer { isBusy = false }
            do {
                if mode == .signIn {
                    try await auth.signIn(email: email, password: password)
                } else {
                    try await auth.signUp(email: email, password: password)
                }
            } catch {
                errorMessage = BackendError.userMessage(error)
            }
        }
    }
}

/// "Check your inbox" after sign-up, with a resend option.
struct CheckInboxView: View {
    let email: String
    @Environment(AuthService.self) private var auth
    @State private var isBusy = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var cooldownUntil: Date?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "envelope.badge")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Bestätige deine E-Mail-Adresse")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Wir haben einen Link an \(email) geschickt. Öffne ihn auf diesem iPhone, um dein Konto zu aktivieren.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let message {
                InlineMessage(text: message, color: messageIsError ? Theme.overtime : Theme.accent)
            }
            Spacer()
            VStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = cooldownUntil.map { Int($0.timeIntervalSince(context.date).rounded(.up)) } ?? 0
                    AuthPrimaryButton(
                        title: remaining > 0 ? "Erneut senden (\(remaining) s)" : "E-Mail erneut senden",
                        isBusy: isBusy,
                        action: resend
                    )
                    .disabled(isBusy || remaining > 0)
                }
                Button("Zurück zur Anmeldung") {
                    auth.pendingConfirmationEmail = nil
                }
                .font(.subheadline)
            }
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func resend() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await auth.resendConfirmation(email: email)
                message = String(localized: "E-Mail wurde erneut gesendet.")
                messageIsError = false
                cooldownUntil = .now.addingTimeInterval(60)
            } catch {
                message = BackendError.userMessage(error)
                messageIsError = true
            }
        }
    }
}

/// "Passwort vergessen?": sends Supabase's reset email; its link opens the app.
struct ForgotPasswordView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var isBusy = false
    @State private var sent = false
    @State private var errorMessage: String?
    @State private var touched = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if sent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                    Text("Falls es ein Konto für \(email) gibt, haben wir dir einen Link zum Zurücksetzen geschickt. Öffne ihn auf diesem iPhone.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    AuthPrimaryButton(title: "Fertig", isBusy: false) { dismiss() }
                } else {
                    Text("Gib deine E-Mail-Adresse ein. Wir schicken dir einen Link, mit dem du ein neues Passwort festlegen kannst.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AuthTextField(title: "E-Mail-Adresse", text: $email, message: touched ? CredentialRules.emailMessage(email) : nil)
                        .onSubmit(send)
                    InlineMessage(text: errorMessage)
                    AuthPrimaryButton(title: "Link senden", isBusy: isBusy, action: send)
                        .disabled(isBusy)
                }
                Spacer()
            }
            .padding(24)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Passwort zurücksetzen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        touched = true
        guard CredentialRules.isValidEmail(email), !isBusy else { return }
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                sent = true
            } catch {
                errorMessage = BackendError.userMessage(error)
            }
        }
    }
}

#Preview("Anmelden · Dunkel") {
    AuthView()
        .environment(AuthService.preview(signedIn: false))
        .preferredColorScheme(.dark)
}

#Preview("Anmelden · Hell") {
    AuthView()
        .environment(AuthService.preview(signedIn: false))
        .preferredColorScheme(.light)
}

#Preview("Posteingang · Dunkel") {
    AuthView()
        .environment(AuthService.preview(signedIn: false, pendingConfirmation: true))
        .preferredColorScheme(.dark)
}

#Preview("Passwort vergessen · Hell") {
    ForgotPasswordView(email: "anna@example.com")
        .environment(AuthService.preview(signedIn: false))
        .preferredColorScheme(.light)
}
