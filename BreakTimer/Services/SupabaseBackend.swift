import Foundation
import Supabase

/// The Supabase client, configured from Info.plist (SupabaseURL, SupabaseAnonKey ← Config.xcconfig).
/// The session is stored in the Keychain (supabase-swift's default storage on Apple platforms).
enum SupabaseBackend {
    enum Redirect {
        /// Email confirmation after sign-up.
        static let authCallback = URL(string: "breaktimer://auth-callback")!
        /// Password reset link.
        static let resetPassword = URL(string: "breaktimer://reset-password")!
    }

    static let url: URL? = {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            !raw.isEmpty, !raw.contains("your-project-ref"),
            let url = URL(string: raw), let host = url.host()
        else { return nil }
        let isLocal = host == "localhost" || host == "127.0.0.1"
        return url.scheme == "https" || isLocal ? url : nil
    }()

    static let anonKey: String? = {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            !key.isEmpty, key != "your-anon-key"
        else { return nil }
        return key
    }()

    static var isConfigured: Bool { client != nil }

    static let client: SupabaseClient? = {
        guard let url, let anonKey else {
            Log.warn(.auth, "Supabase is not configured (Config.xcconfig): sign-in and sync are unavailable")
            return nil
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: Redirect.authCallback,
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()
}

/// Maps backend errors to German user messages and to log descriptions with error codes.
enum BackendError {
    static func userMessage(_ error: any Error) -> String {
        if let auth = error as? AuthError {
            // Rejected by the Before User Created hook (supabase/migrations/20261024000000_signup_ip_limit.sql).
            if auth.message.contains("signup_ip_limit") {
                return String(localized: "Zu viele Registrierungen von diesem Netzwerk. Bitte versuche es in einer Stunde erneut.")
            }
            switch auth.errorCode {
            case .invalidCredentials: return String(localized: "E-Mail oder Passwort ist falsch.")
            case .emailNotConfirmed: return String(localized: "Bitte bestätige zuerst deine E-Mail-Adresse.")
            case .userAlreadyExists, .emailExists: return String(localized: "Für diese E-Mail-Adresse gibt es bereits ein Konto.")
            case .weakPassword: return String(localized: "Das Passwort ist zu schwach. Wähle ein längeres oder komplexeres Passwort.")
            case .samePassword: return String(localized: "Das neue Passwort muss sich vom bisherigen unterscheiden.")
            case .overEmailSendRateLimit, .overRequestRateLimit: return String(localized: "Zu viele Versuche. Bitte warte einen Moment.")
            case .sessionNotFound: return String(localized: "Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.")
            default: break
            }
            if case .pkceGrantCodeExchange = auth {
                return String(localized: "Der Link ist abgelaufen oder wurde auf einem anderen Gerät angefordert.")
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return String(localized: "Keine Verbindung zum Server. Bitte prüfe deine Internetverbindung.")
            default: break
            }
        }
        return String(localized: "Etwas ist schiefgelaufen. Bitte versuche es erneut.")
    }

    /// For the log: type, server error code and message (scrubbed of emails/tokens by Log).
    static func logDescription(_ error: any Error) -> String {
        switch error {
        case let auth as AuthError:
            return "AuthError code=\(auth.errorCode.rawValue): \(auth.message)"
        case let postgrest as PostgrestError:
            return "PostgrestError code=\(postgrest.code ?? "-"): \(postgrest.message)"
        case let functions as FunctionsError:
            switch functions {
            case .httpError(let code, let data):
                return "FunctionsError http=\(code): \(String(decoding: data.prefix(200), as: UTF8.self))"
            case .relayError:
                return "FunctionsError relay error"
            @unknown default:
                return "FunctionsError \(functions)"
            }
        case let urlError as URLError:
            return "URLError code=\(urlError.code.rawValue): \(urlError.localizedDescription)"
        default:
            return Log.describe(error)
        }
    }
}
