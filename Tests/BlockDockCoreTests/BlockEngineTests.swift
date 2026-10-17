import Foundation
import XCTest
@testable import BlockDockCore

final class BlockEngineTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BlockDockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testExpiryAcrossRestartRecordsOnlyPlannedTimeAndRequiresDecision() throws {
        let path = try directory()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try BlockEngine(dataDirectory: path, now: start)
        try first.start(category: "Work", minutes: 25, at: start)

        let restart = try BlockEngine(dataDirectory: path, now: start.addingTimeInterval(2 * 3600))
        XCTAssertNil(restart.document.running)
        XCTAssertEqual(restart.document.pending?.category, "Work")
        XCTAssertEqual(restart.document.history.count, 1)
        XCTAssertEqual(restart.document.history[0].duration, 25 * 60)
        XCTAssertThrowsError(try restart.start(category: "Study", minutes: 30, at: start.addingTimeInterval(2 * 3600)))

        let answerTime = start.addingTimeInterval(2 * 3600 + 50)
        try restart.answer(category: "Study", minutes: 30, at: answerTime)
        XCTAssertEqual(restart.document.running?.startedAt, answerTime)
        XCTAssertEqual(restart.document.history.count, 1)
        XCTAssertEqual(restart.totals(for: answerTime, includingRunningAt: answerTime)["Work"], 25 * 60)

        let secondRestart = try BlockEngine(dataDirectory: path, now: answerTime.addingTimeInterval(10 * 60))
        XCTAssertEqual(secondRestart.document.running?.category, "Study")
        XCTAssertEqual(secondRestart.secondsRemaining(at: answerTime.addingTimeInterval(10 * 60)), 20 * 60)
        XCTAssertEqual(secondRestart.totals(for: answerTime, includingRunningAt: answerTime.addingTimeInterval(10 * 60))["Study"], 10 * 60)
    }

    func testContinueAfterLongUnansweredGateStartsFreshBlock() throws {
        let path = try directory()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = try BlockEngine(dataDirectory: path, now: start)
        try engine.start(category: "Break", minutes: 15, at: start)
        try engine.reconcile(at: start.addingTimeInterval(3600))
        let continuation = start.addingTimeInterval(7200)
        try engine.answer(category: "Break", minutes: 15, at: continuation)
        try engine.stop(at: continuation.addingTimeInterval(90))
        XCTAssertEqual(engine.document.history.map(\.duration), [900, 90])
        XCTAssertEqual(engine.totals(for: start)["Break"], 990)
        try engine.dismissDecision()
        XCTAssertNil(engine.document.pending)
    }

    func testDailyTotalsSplitAtLocalMidnightAndIncludeOnlyElapsedRunningTime() throws {
        let path = try directory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = Date(timeIntervalSince1970: 1_700_006_400)
        let start = midnight.addingTimeInterval(-600)
        let engine = try BlockEngine(dataDirectory: path, calendar: calendar, now: start)
        try engine.start(category: "Work", minutes: 25, at: start)
        let nextDay = midnight.addingTimeInterval(300)
        XCTAssertEqual(engine.totals(for: start, includingRunningAt: nextDay)["Work"], 600)
        XCTAssertEqual(engine.totals(for: nextDay, includingRunningAt: nextDay)["Work"], 300)
        try engine.reconcile(at: midnight.addingTimeInterval(7200))
        XCTAssertEqual(engine.totals(for: start)["Work"], 600)
        XCTAssertEqual(engine.totals(for: nextDay)["Work"], 900)
    }

    func testCategoriesPersistAndOldHistorySurvivesRemoval() throws {
        let path = try directory()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = try BlockEngine(dataDirectory: path, now: now)
        try engine.addCategory("Reading")
        try engine.start(category: "Reading", minutes: 20, at: now)
        try engine.stop(at: now.addingTimeInterval(75))
        try engine.dismissDecision()
        try engine.removeCategory("Reading")
        let restored = try BlockEngine(dataDirectory: path, now: now.addingTimeInterval(100))
        XCTAssertFalse(restored.document.categories.contains("Reading"))
        XCTAssertEqual(restored.document.history.first?.category, "Reading")
        XCTAssertEqual(restored.totals(for: now)["Reading"], 75)
    }

    func testInvalidInputAndCorruptDataDoNotOverwriteSavedState() throws {
        let path = try directory()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = try BlockEngine(dataDirectory: path, now: now)
        try engine.start(category: "Work", minutes: 25, at: now)
        let bytes = try Data(contentsOf: engine.fileURL)
        XCTAssertThrowsError(try engine.start(category: "Study", minutes: 25, at: now))
        XCTAssertThrowsError(try engine.addCategory("work"))
        XCTAssertEqual(try Data(contentsOf: engine.fileURL), bytes)
        try Data("invalid json".utf8).write(to: engine.fileURL, options: .atomic)
        XCTAssertThrowsError(try BlockEngine(dataDirectory: path, now: now))
        XCTAssertEqual(try Data(contentsOf: engine.fileURL), Data("invalid json".utf8))
    }
}
