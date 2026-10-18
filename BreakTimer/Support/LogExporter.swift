import Foundation

/// A temporary, merged log file ready to send to support.
struct SupportReport: Identifiable, Sendable {
    let id = UUID()
    let fileURL: URL
    let data: Data

    var fileName: String { fileURL.lastPathComponent }

    static var subject: String {
        "BreakTimer Support – v\(AppInfo.version) (\(AppInfo.build))"
    }

    static var mailBody: String {
        String(localized: """
        Hallo BreakTimer-Support,

        bitte beschreibe hier kurz dein Problem:
        – Was hast du gemacht?
        – Was ist passiert?
        – Was hast du stattdessen erwartet?



        Das Protokoll ist angehängt. Es enthält technische Daten und Pausenzeiten, aber keine Passwörter.
        """)
    }

    /// SUPPORT_EMAIL from Config.xcconfig, nil if not configured.
    static var supportEmail: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SupportEmail") as? String,
              value.contains("@") else { return nil }
        return value
    }
}

/// Builds the support log: app.log and widget.log merged by timestamp, with a diagnostic header.
enum LogExporter {
    struct Context: Sendable {
        var maskedEmail: String
        var userID: String
        var budgetMinutes: Int
        var lastSuccessfulSync: Date?
        var unsyncedItems: Int
    }

    private static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "SupportExport", directoryHint: .isDirectory)
    }

    static func makeReport(context: Context) async throws -> SupportReport {
        await Log.writer.flush()
        let header = header(for: context)
        let directory = exportDirectory
        let logFiles = LogFiles.allFiles

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: directory) // leftovers of earlier exports
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let merged = LogRetention.merge(logFiles.map(LogFiles.readLines))
            let text = header + merged.joined(separator: "\n") + "\n"
            let data = Data(text.utf8)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmm"
            let url = directory.appending(path: "BreakTimer-Log-\(formatter.string(from: .now)).txt")
            try data.write(to: url, options: .atomic)
            return SupportReport(fileURL: url, data: data)
        }.value
    }

    /// Deletes the temporary export file.
    static func delete(_ report: SupportReport) {
        guard FileManager.default.fileExists(atPath: report.fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: report.fileURL)
            Log.debug(.support, "Temporary support export deleted")
        } catch {
            Log.error(.support, "Deleting the temporary support export failed", error: error)
        }
    }

    private static func header(for context: Context) -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        let timeZone = TimeZone.current
        let offset = timeZone.secondsFromGMT() / 3600
        let appLanguage = Bundle.main.preferredLocalizations.first ?? "?"
        let deviceLanguage = Locale.preferredLanguages.first ?? "?"
        let rows: [(String, String)] = [
            ("Created", iso.string(from: .now)),
            ("App version", "\(AppInfo.version) (\(AppInfo.build))"),
            ("iOS version", AppInfo.systemVersion),
            ("Device model", AppInfo.deviceModel),
            ("Language", "\(appLanguage) (device: \(deviceLanguage))"),
            ("Time zone", "\(timeZone.identifier) (GMT\(offset >= 0 ? "+" : "")\(offset))"),
            ("Email", context.maskedEmail),
            ("User ID", context.userID),
            ("Daily budget", "\(context.budgetMinutes) min"),
            ("Last successful sync", context.lastSuccessfulSync.map { iso.string(from: $0) } ?? "never"),
            ("Unsynced items", "\(context.unsyncedItems)"),
        ]
        let width = rows.map(\.0.count).max() ?? 0
        let body = rows.map { "\($0.0.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.1)" }
        return (["BreakTimer support log"] + body + [String(repeating: "-", count: 72)]).joined(separator: "\n") + "\n"
    }
}
