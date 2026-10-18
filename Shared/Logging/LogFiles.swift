import Foundation

/// Locations and housekeeping of the log files in the App Group container.
enum LogFiles {
    static var directory: URL {
        AppGroup.containerURL.appending(path: "Logs", directoryHint: .isDirectory)
    }

    static func url(forProcess process: String) -> URL {
        directory.appending(path: "\(process).log")
    }

    static var allFiles: [URL] {
        [url(forProcess: "app"), url(forProcess: "widget")]
    }

    /// Size of all log files together, in bytes.
    static func totalSize() -> Int {
        allFiles.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + size
        }
    }

    static func readLines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Drops entries older than 14 days and trims the oldest entries so that all logs together
    /// stay under 2 MB. Runs on the app's writer queue so it never races the app's own appends.
    static func applyRetention(now: Date = .now) {
        Log.writer.perform {
            let urls = allFiles
            var files: [String: [String]] = [:]
            for url in urls { files[url.path] = readLines(url) }

            let result = LogRetention.apply(to: files, now: now)
            guard result.droppedLines > 0 else { return }

            for url in urls {
                let lines = result.files[url.path] ?? []
                let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
                try? Data(text.utf8).write(to: url, options: .atomic)
            }
            Log.info(.support, "Log retention dropped \(result.droppedLines) lines")
        }
    }

    /// Deletes all log files (used by "Protokoll löschen" and account deletion).
    static func deleteAll() async {
        await Log.writer.flush()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Log.writer.perform {
                for url in allFiles { try? FileManager.default.removeItem(at: url) }
                continuation.resume()
            }
        }
    }
}
