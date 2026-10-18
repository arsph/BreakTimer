import Foundation
import os

/// Logging facade used by the app and the widget extension.
/// Every entry goes to os.Logger (Xcode console) and to this process's log file in the App Group.
///
/// Never pass passwords, tokens, keys or full email addresses. Use `EmailMasker.mask` for emails;
/// messages are additionally scrubbed for email addresses and JWTs before they are written.
enum Log {
    /// "widget" for the widget extension, "app" for everything running in the app process
    /// (including App Intents that iOS runs in the app).
    static let process: String = Bundle.main.bundleURL.pathExtension == "appex" ? "widget" : "app"

    static let writer = LogFileWriter(url: LogFiles.url(forProcess: process))

    private static let subsystem = Bundle.main.bundleIdentifier ?? "BreakTimer"

    /// DEBUG entries are written only while "Ausführliche Protokollierung" is on.
    static var minimumLevel: LogLevel {
        SharedDefaults.verboseLogging ? .debug : .info
    }

    static func debug(_ category: LogCategory, _ message: @autoclosure () -> String) {
        write(.debug, category, message)
    }

    static func info(_ category: LogCategory, _ message: @autoclosure () -> String) {
        write(.info, category, message)
    }

    static func warn(_ category: LogCategory, _ message: @autoclosure () -> String) {
        write(.warn, category, message)
    }

    static func error(_ category: LogCategory, _ message: @autoclosure () -> String) {
        write(.error, category, message)
    }

    /// Logs a caught error with its description at ERROR level.
    static func error(_ category: LogCategory, _ message: @autoclosure () -> String, error: any Error) {
        write(.error, category, { "\(message()): \(describe(error))" })
    }

    static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        let description = String(describing: error)
        return "\(description) [\(nsError.domain) \(nsError.code)]"
    }

    private static func write(_ level: LogLevel, _ category: LogCategory, _ message: () -> String) {
        guard level >= minimumLevel else { return }
        let text = EmailMasker.scrub(message())
        let date = Date()

        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warn: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }

        writer.append(date: date, level: level, process: process, category: category, message: text)
    }
}
