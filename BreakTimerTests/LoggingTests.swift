import Foundation
import Testing

@Suite("Email masking")
struct EmailMaskerTests {
    @Test(arguments: [
        ("anna.schmidt@gmail.com", "a***@gmail.com"),
        ("  Max@Firma.DE ", "M***@firma.de"),
        ("x@y.io", "x***@y.io"),
        ("odd@name@example.com", "o***@example.com"),
    ])
    func masksAddresses(input: String, expected: String) {
        #expect(EmailMasker.mask(input) == expected)
    }

    @Test(arguments: ["", "no-at-sign", "@example.com", "user@"])
    func invalidInputIsFullyMasked(input: String) {
        #expect(EmailMasker.mask(input) == "***")
    }

    @Test func scrubsEmailsInFreeText() {
        let text = "Sign-in failed for anna.schmidt@gmail.com (retry for bob@firma.de)"
        #expect(EmailMasker.scrub(text) == "Sign-in failed for a***@gmail.com (retry for b***@firma.de)")
    }

    @Test func scrubsTokens() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJl"
        #expect(EmailMasker.scrub("token=\(jwt) end") == "token=<token> end")
        #expect(EmailMasker.scrub("Authorization: Bearer abc.def-123") == "Authorization: Bearer <token>")
    }

    @Test func leavesOrdinaryTextAlone() {
        let text = "Break ended (source: widget), remaining 12:34"
        #expect(EmailMasker.scrub(text) == text)
    }
}

@Suite("Log retention")
struct LogRetentionTests {
    let utc = TimeZone(identifier: "UTC")!
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let now = Date(timeIntervalSince1970: 1_792_000_000) // fixed reference

    func line(_ date: Date, _ message: String, process: String = "app", timeZone: TimeZone? = nil) -> String {
        LogLine.format(
            date: date, level: .info, process: process, category: .lifecycle,
            message: message, formatter: LogLine.makeFormatter(timeZone: timeZone ?? utc)
        )
    }

    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    @Test func lineFormat() {
        let date = Date(timeIntervalSince1970: 1_792_000_000.25)
        let text = LogLine.format(
            date: date, level: .warn, process: "widget", category: .liveActivity,
            message: "first\nsecond", formatter: LogLine.makeFormatter(timeZone: berlin)
        )
        let parts = text.components(separatedBy: " | ")
        #expect(parts.count == 5)
        #expect(parts[0].hasSuffix("+01:00") || parts[0].hasSuffix("+02:00"))
        #expect(parts[0].contains(".250"))
        #expect(Array(parts[1...]) == ["WARN", "widget", "liveActivity", "first ⏎ second"])
        #expect(LogLine.timestamp(of: text, formatter: LogLine.makeFormatter()) == date)
    }

    @Test func dropsEntriesOlderThan14Days() {
        let files = [
            "app": [line(daysAgo(20), "old"), line(daysAgo(14.5), "older than cutoff"), line(daysAgo(13), "keep"), line(daysAgo(0), "new")],
            "widget": [line(daysAgo(15), "old widget", process: "widget"), line(daysAgo(1), "keep widget", process: "widget")],
        ]
        let result = LogRetention.apply(to: files, now: now)
        #expect(result.droppedLines == 3)
        #expect(result.files["app"]?.map { $0.components(separatedBy: " | ").last! } == ["keep", "new"])
        #expect(result.files["widget"]?.count == 1)
    }

    @Test func nothingToDropKeepsEverything() {
        let files = ["app": [line(daysAgo(2), "a"), line(daysAgo(1), "b")]]
        let result = LogRetention.apply(to: files, now: now)
        #expect(result.droppedLines == 0)
        #expect(result.files == files)
    }

    @Test func trimsOldestAcrossFilesToFitSizeLimit() {
        let app = (0..<10).map { line(daysAgo(Double(10 - $0)), "app \($0)") }
        let widget = (0..<10).map { line(daysAgo(Double(10 - $0) - 0.5), "widget \($0)", process: "widget") }
        // Exactly enough room for the 6 newest lines (plus a little slack, less than one line).
        let newest = Array(app[7...]) + Array(widget[7...])
        let limit = newest.reduce(0) { $0 + $1.utf8.count + 1 } + 10
        let result = LogRetention.apply(to: ["app": app, "widget": widget], now: now, maxTotalBytes: limit)

        let kept = (result.files["app"] ?? []) + (result.files["widget"] ?? [])
        let totalBytes = kept.reduce(0) { $0 + $1.utf8.count + 1 }
        #expect(totalBytes <= limit)
        #expect(kept.count == 6)
        #expect(result.droppedLines == 20 - kept.count)
        // The newest entries survive, interleaved by time: app 7..9 and widget 7..9.
        #expect(result.files["app"]?.last?.hasSuffix("app 9") == true)
        #expect(result.files["widget"]?.last?.hasSuffix("widget 9") == true)
        #expect(result.files["app"]?.first?.hasSuffix("app 7") == true)
        #expect(result.files["widget"]?.first?.hasSuffix("widget 7") == true)
    }

    @Test func linesWithoutTimestampFollowThePreviousLine() {
        let files = ["app": [line(daysAgo(20), "old"), "continuation of old", line(daysAgo(1), "new"), "continuation of new"]]
        let result = LogRetention.apply(to: files, now: now)
        #expect(result.files["app"]?.count == 2)
        #expect(result.files["app"]?.last == "continuation of new")
    }

    @Test func mergeSortsByTimestampAcrossTimeZones() {
        let app = [line(daysAgo(3), "a1"), line(daysAgo(1), "a2")]
        // Same instants written with a different offset must still sort by instant.
        let widget = [line(daysAgo(2), "w1", process: "widget", timeZone: berlin), line(daysAgo(0.5), "w2", process: "widget", timeZone: berlin)]
        let merged = LogRetention.merge([app, widget]).map { $0.components(separatedBy: " | ").last! }
        #expect(merged == ["a1", "w1", "a2", "w2"])
    }
}
