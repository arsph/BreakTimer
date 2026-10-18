import Foundation

/// Pure retention and merge logic for log files, kept free of file I/O so it can be unit-tested.
enum LogRetention {
    static let maxAge: TimeInterval = 14 * 24 * 60 * 60
    static let maxTotalBytes = 2 * 1024 * 1024

    struct Result: Equatable {
        /// Remaining lines per file, in their original order.
        var files: [String: [String]]
        var droppedLines: Int
    }

    /// Drops lines older than `maxAge`, then drops the oldest lines across all files
    /// until all files together fit into `maxTotalBytes` (counting one newline per line).
    static func apply(
        to files: [String: [String]],
        now: Date,
        maxAge: TimeInterval = maxAge,
        maxTotalBytes: Int = maxTotalBytes
    ) -> Result {
        let formatter = LogLine.makeFormatter()
        let cutoff = now.addingTimeInterval(-maxAge)

        struct Entry {
            let file: String
            let index: Int
            let date: Date
            let bytes: Int
        }

        var entries: [Entry] = []
        var total = 0
        for (file, lines) in files {
            for (index, (line, date)) in dated(lines, formatter: formatter).enumerated() where date >= cutoff {
                let bytes = line.utf8.count + 1
                entries.append(Entry(file: file, index: index, date: date, bytes: bytes))
                total += bytes
            }
        }

        if total > maxTotalBytes {
            // Stable sort keeps file order for equal timestamps; the file name breaks ties between files.
            entries = entries.enumerated().sorted { lhs, rhs in
                if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
                if lhs.element.file != rhs.element.file { return lhs.element.file < rhs.element.file }
                return lhs.offset < rhs.offset
            }.map(\.element)

            var dropCount = 0
            while total > maxTotalBytes, dropCount < entries.count {
                total -= entries[dropCount].bytes
                dropCount += 1
            }
            entries.removeFirst(dropCount)
        }

        var kept: [String: Set<Int>] = [:]
        for entry in entries { kept[entry.file, default: []].insert(entry.index) }

        var result: [String: [String]] = [:]
        var originalCount = 0
        var keptCount = 0
        for (file, lines) in files {
            originalCount += lines.count
            let indices = kept[file] ?? []
            let remaining = lines.enumerated().filter { indices.contains($0.offset) }.map(\.element)
            keptCount += remaining.count
            result[file] = remaining
        }
        return Result(files: result, droppedLines: originalCount - keptCount)
    }

    /// Merges the lines of several files into one list sorted by timestamp.
    /// Lines without a timestamp stay attached to the line before them.
    static func merge(_ files: [[String]]) -> [String] {
        let formatter = LogLine.makeFormatter()
        var all: [(date: Date, file: Int, index: Int, line: String)] = []
        for (fileIndex, lines) in files.enumerated() {
            for (index, (line, date)) in dated(lines, formatter: formatter).enumerated() {
                all.append((date, fileIndex, index, line))
            }
        }
        return all.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.file != rhs.file { return lhs.file < rhs.file }
            return lhs.index < rhs.index
        }.map(\.line)
    }

    /// Pairs each line with its timestamp; lines without one inherit the previous line's timestamp.
    private static func dated(_ lines: [String], formatter: ISO8601DateFormatter) -> [(String, Date)] {
        var last = Date.distantPast
        return lines.map { line in
            if let date = LogLine.timestamp(of: line, formatter: formatter) { last = date }
            return (line, last)
        }
    }
}
