import Foundation
import Observation
import Supabase

/// Email + password authentication with Supabase: sign-up with email confirmation, sign-in,
/// password reset via breaktimer:// link, password change, sign-out and account deletion.
@Observable
@MainActor
final class AuthService {
    enum State: Equatable {
        case loading, signedOut, signedIn
    }

    struct Account: Equatable {
        let id: UUID
        let email: String
        var maskedEmail: String { EmailMasker.mask(email) }
    }

    private(set) var state: State = .loading
    private(set) var account: Account?
    /// Set after sign-up while the email still needs confirming ("check your inbox").
    var pendingConfirmationEmail: String?
    /// Shows the set-new-password screen after opening a reset link.
    var isResettingPassword = false
    /// Problem with an opened auth link (expired, other device), shown on the auth screen.
    var linkError: String?

    var isConfigured: Bool { client != nil }

    /// Clears local data after sign-out (`false`) or account deletion (`true`, logs too).
    @ObservationIgnored var clearLocalData: (_ includingLogs: Bool) async -> Void = { _ in }
    /// Called once per sign-in of a user (initial sync).
    @ObservationIgnored var onSignedIn: (Account) -> Void = { _ in }

    private let client: SupabaseClient?
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(client: SupabaseClient? = SupabaseBackend.client) {
        self.client = client
        if client == nil { state = .signedOut }
    }

    /// Starts listening to Supabase auth events (restores the Keychain session first).
    func start() {
        #if DEBUG
        // Debug builds only: launch with "-skipAuth" to try the app without a Supabase project
        // (local demo account, no sync). Signing in with a real account later clears its data.
        if ProcessInfo.processInfo.arguments.contains("-skipAuth") {
            let demoID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            account = Account(id: demoID, email: "demo@example.com")
            state = .signedIn
            SharedDefaults.signedInUserID = demoID.uuidString
            SharedDefaults.lastUserID = demoID.uuidString
            Log.warn(.auth, "Signed in with the local demo account (-skipAuth, debug build)")
            WidgetReloader.reloadAll(reason: "demo sign-in")
            return
        }
        #endif
        guard let client, listener == nil else { return }
        listener = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                self?.handle(event: event, session: session)
            }
        }
    }

    // MARK: Actions

    func signUp(email: String, password: String) async throws {
        let client = try requireClient()
        let masked = EmailMasker.mask(email)
        Log.info(.auth, "Sign-up requested for \(masked)")
        do {
            let response = try await client.auth.signUp(email: email, password: password, redirectTo: SupabaseBackend.Redirect.authCallback)
            if response.session == nil {
                pendingConfirmationEmail = email
                Log.info(.auth, "Sign-up for \(masked) created user \(response.user.id), email confirmation pending")
            } else {
                Log.info(.auth, "Sign-up for \(masked) completed without confirmation, user \(response.user.id)")
            }
        } catch {
            Log.error(.auth, "Sign-up failed for \(masked): \(BackendError.logDescription(error))")
            throw error
        }
    }

    func resendConfirmation(email: String) async throws {
        let client = try requireClient()
        let masked = EmailMasker.mask(email)
        do {
            try await client.auth.resend(email: email, type: .signup, emailRedirectTo: SupabaseBackend.Redirect.authCallback)
            Log.info(.auth, "Confirmation email resent to \(masked)")
        } catch {
            Log.error(.auth, "Resending confirmation to \(masked) failed: \(BackendError.logDescription(error))")
            throw error
        }
    }

    func signIn(email: String, password: String) async throws {
        let client = try requireClient()
        let masked = EmailMasker.mask(email)
        Log.info(.auth, "Sign-in requested for \(masked)")
        do {
            try await client.auth.signIn(email: email, password: password)
        } catch {
            Log.error(.auth, "Sign-in failed for \(masked): \(BackendError.logDescription(error))")
            if (error as? AuthError)?.errorCode == .emailNotConfirmed {
                pendingConfirmationEmail = email
                return
            }
            throw error
        }
    }

    func sendPasswordReset(email: String) async throws {
        let client = try requireClient()
        let masked = EmailMasker.mask(email)
        do {
            try await client.auth.resetPasswordForEmail(email, redirectTo: SupabaseBackend.Redirect.resetPassword)
            Log.info(.auth, "Password reset requested for \(masked)")
        } catch {
            Log.error(.auth, "Password reset request for \(masked) failed: \(BackendError.logDescription(error))")
            throw error
        }
    }

    /// Sets a new password (after a reset link, or "Passwort ändern" in Settings).
    func updatePassword(_ password: String) async throws {
        let client = try requireClient()
        do {
            try await client.auth.update(user: UserAttributes(password: password))
            Log.info(.auth, "Password changed for user \(account?.id.uuidString ?? "?")")
            isResettingPassword = false
        } catch {
            Log.error(.auth, "Changing the password failed: \(BackendError.logDescription(error))")
            throw error
        }
    }

    /// Handles breaktimer://auth-callback (email confirmed) and breaktimer://reset-password links.
    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "breaktimer", let client else { return }
        let host = url.host() ?? ""
        guard host == "auth-callback" || host == "reset-password" else { return }
        Log.info(.auth, "Auth link opened (\(host))")
        do {
            let session = try await client.auth.session(from: url)
            linkError = nil
            pendingConfirmationEmail = nil
            if host == "reset-password" {
                isResettingPassword = true
                Log.info(.auth, "Password recovery session for user \(session.user.id)")
            } else {
                Log.info(.auth, "Email confirmed for user \(session.user.id)")
            }
        } catch {
            Log.error(.auth, "Auth link (\(host)) failed: \(BackendError.logDescription(error))")
            linkError = BackendError.userMessage(error)
        }
    }

    /// Signs out and clears local break data and settings. Logs are kept (they help with login problems).
    func signOut() async {
        guard let client else { return }
        let userID = account?.id.uuidString ?? "?"
        Log.info(.auth, "Sign-out requested by user \(userID)")
        do {
            try await client.auth.signOut()
        } catch {
            Log.error(.auth, "Server sign-out failed, signing out locally: \(BackendError.logDescription(error))")
            try? await client.auth.signOut(scope: .local)
        }
        await clearLocalData(false)
        account = nil
        state = .signedOut
        Log.info(.auth, "Signed out user \(userID), local data cleared")
    }

    /// Deletes the account on the server (Edge Function), then all local data including logs.
    func deleteAccount() async throws {
        let client = try requireClient()
        let userID = account?.id.uuidString ?? "?"
        Log.info(.auth, "Account deletion requested by user \(userID)")
        do {
            try await client.functions.invoke("delete-account")
        } catch {
            Log.error(.auth, "Account deletion failed: \(BackendError.logDescription(error))")
            throw error
        }
        Log.info(.auth, "Account \(userID) deleted on the server")
        try? await client.auth.signOut(scope: .local)
        await clearLocalData(true)
        account = nil
        state = .signedOut
    }

    // MARK: Events

    private func handle(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            if let session {
                setSignedIn(session.user)
            } else if event == .initialSession {
                Log.info(.auth, "No stored session")
                state = .signedOut
            }
        case .passwordRecovery:
            if let session { setSignedIn(session.user) }
            isResettingPassword = true
            Log.info(.auth, "Password recovery started")
        case .signedOut, .userDeleted:
            if state == .signedIn {
                Log.info(.auth, "Session ended (\(event.rawValue))")
            }
            account = nil
            state = .signedOut
            SharedDefaults.signedInUserID = nil
            WidgetReloader.reloadAll(reason: "signed out")
        @unknown default:
            Log.debug(.auth, "Unhandled auth event \(event.rawValue)")
        }
    }

    private func setSignedIn(_ user: User) {
        let newAccount = Account(id: user.id, email: user.email ?? "")
        let isNewSignIn = account?.id != newAccount.id
        account = newAccount
        state = .signedIn
        guard isNewSignIn else { return }

        let userID = user.id.uuidString
        let previousOwner = SharedDefaults.lastUserID
        SharedDefaults.signedInUserID = userID
        SharedDefaults.lastUserID = userID
        Log.info(.auth, "Signed in as user \(userID) (\(newAccount.maskedEmail))")

        Task {
            if let previousOwner, previousOwner != userID {
                // Local data belonged to someone else whose session was lost without sign-out.
                Log.warn(.auth, "Local data belonged to user \(previousOwner), clearing it")
                await clearLocalData(false)
                SharedDefaults.signedInUserID = userID
                SharedDefaults.lastUserID = userID
            }
            WidgetReloader.reloadAll(reason: "signed in")
            onSignedIn(newAccount)
        }
    }

    /// A client-less instance for SwiftUI previews.
    static func preview(signedIn: Bool, pendingConfirmation: Bool = false) -> AuthService {
        let service = AuthService(client: nil)
        if signedIn {
            service.account = Account(id: UUID(), email: "anna.schmidt@example.com")
            service.state = .signedIn
        }
        if pendingConfirmation { service.pendingConfirmationEmail = "anna.schmidt@example.com" }
        return service
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw URLError(.cannotFindHost) }
        return client
    }
}
