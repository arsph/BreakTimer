import Foundation

/// Keeps personal data and secrets out of log files.
enum EmailMasker {
    /// `anna.schmidt@gmail.com` → `a***@gmail.com`
    static func mask(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let at = trimmed.lastIndex(of: "@"),
            at != trimmed.startIndex,
            trimmed.index(after: at) != trimmed.endIndex
        else { return "***" }

        let first = trimmed[trimmed.startIndex]
        let domain = trimmed[trimmed.index(after: at)...].lowercased()
        return "\(first)***@\(domain)"
    }

    /// Masks every email address and redacts JWT-like tokens in free text,
    /// e.g. error descriptions returned by a server.
    static func scrub(_ text: String) -> String {
        guard text.contains("@") || text.contains("eyJ") || text.localizedCaseInsensitiveContains("bearer") else {
            return text
        }
        var result = text.replacing(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/) { match in
            mask(String(match.output))
        }
        result = result.replacing(/eyJ[A-Za-z0-9_\-]+(\.[A-Za-z0-9_\-]+){1,2}/, with: "<token>")
        result = result.replacing(/(?i)bearer\s+[A-Za-z0-9._\-]+/, with: "Bearer <token>")
        return result
    }
}
