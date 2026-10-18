import Foundation

enum LogLevel: Int, Comparable, Sendable, CaseIterable {
    case debug, info, warn, error

    var label: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warn: "WARN"
        case .error: "ERROR"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum LogCategory: String, Sendable, CaseIterable {
    case lifecycle, timer, budget, widget, liveActivity, notifications, sync, auth, settings, support
}

/// Formats and parses a single log line:
/// `2026-10-18T14:47:03.120+02:00 | INFO | app | timer | Break started`
enum LogLine {
    static let separator = " | "

    /// Not thread-safe to share across threads while mutating; create one per queue or per operation.
    static func makeFormatter(timeZone: TimeZone = .current) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timeZone
        return formatter
    }

    static func format(
        date: Date,
        level: LogLevel,
        process: String,
        category: LogCategory,
        message: String,
        formatter: ISO8601DateFormatter
    ) -> String {
        // One entry per line keeps merging and trimming simple.
        let singleLine = message
            .replacingOccurrences(of: "\r\n", with: " ⏎ ")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return [formatter.string(from: date), level.label, process, category.rawValue, singleLine]
            .joined(separator: separator)
    }

    /// Timestamp at the start of a line, or nil for lines that don't start with one.
    static func timestamp(of line: some StringProtocol, formatter: ISO8601DateFormatter) -> Date? {
        guard let range = line.range(of: separator) else { return nil }
        return formatter.date(from: String(line[..<range.lowerBound]))
    }
}
