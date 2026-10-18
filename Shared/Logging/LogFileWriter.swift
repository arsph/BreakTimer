import Foundation
import os

/// Appends log lines to one file through a serial queue, so callers never block on disk I/O
/// and entries keep their order. Each process has its own file, so two processes never write
/// to the same file.
final class LogFileWriter: Sendable {
    let url: URL
    private let queue: DispatchQueue
    /// Only touched on `queue`.
    nonisolated(unsafe) private let formatter = LogLine.makeFormatter()

    init(url: URL) {
        self.url = url
        self.queue = DispatchQueue(label: "BreakTimer.log.\(url.lastPathComponent)", qos: .utility)
    }

    func append(date: Date, level: LogLevel, process: String, category: LogCategory, message: String) {
        queue.async { [self] in
            formatter.timeZone = .current
            let line = LogLine.format(
                date: date, level: level, process: process, category: category,
                message: message, formatter: formatter
            ) + "\n"
            write(Data(line.utf8))
        }
    }

    /// Runs `work` on the writer queue, after every entry queued before it.
    func perform(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Waits until every entry queued so far is on disk.
    func flush() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { continuation.resume() }
        }
    }

    private func write(_ data: Data) {
        let fileManager = FileManager.default
        do {
            if !fileManager.fileExists(atPath: url.path) {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
                return
            }
            // Open, append, close for every entry: trimming at launch replaces the file atomically,
            // and a long-lived handle would keep writing to the replaced file.
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            Logger(subsystem: "BreakTimer", category: "logging")
                .error("Writing log file failed: \(String(describing: error), privacy: .public)")
        }
    }
}
