import Foundation

public struct FinishedBlock: Codable, Equatable, Identifiable {
    public var id: UUID
    public var category: String
    public var startedAt: Date
    public var endedAt: Date
    public var plannedMinutes: Int

    public init(id: UUID = UUID(), category: String, startedAt: Date, endedAt: Date, plannedMinutes: Int) {
        self.id = id
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedMinutes = plannedMinutes
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

public struct RunningBlock: Codable, Equatable {
    public var category: String
    public var startedAt: Date
    public var endsAt: Date
    public var plannedMinutes: Int

    public init(category: String, startedAt: Date, endsAt: Date, plannedMinutes: Int) {
        self.category = category
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.plannedMinutes = plannedMinutes
    }
}

public struct PendingDecision: Codable, Equatable {
    public var category: String
    public var expiredAt: Date
}

public struct BlockDocument: Codable, Equatable {
    public var version = 1
    public var categories = ["Work", "Study", "Admin", "Break", "Other"]
    public var running: RunningBlock?
    public var pending: PendingDecision?
    public var history: [FinishedBlock] = []

    public init() {}
}

public enum BlockError: Error, LocalizedError {
    case invalidCategory, invalidCategoryName, duplicateCategory, invalidDuration, decisionRequired, alreadyRunning, nothingRunning, lastCategory, unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .invalidCategory: return "Choose a category from the list."
        case .invalidCategoryName: return "Use a name of 1–40 characters with no control characters."
        case .duplicateCategory: return "A category with that name already exists."
        case .invalidDuration: return "Choose a duration between 1 and 240 minutes."
        case .decisionRequired: return "Answer the finished block first."
        case .alreadyRunning: return "Finish the current block first."
        case .nothingRunning: return "There is no running block."
        case .lastCategory: return "Keep at least one category."
        case .unsupportedVersion: return "This data file uses a newer format."
        }
    }
}

public final class BlockEngine {
    public private(set) var document: BlockDocument
    public let fileURL: URL
    private let calendar: Calendar

    public init(dataDirectory: URL, calendar: Calendar = .current, now: Date = Date()) throws {
        self.fileURL = dataDirectory.appendingPathComponent("blocks.json")
        self.calendar = calendar
        if FileManager.default.fileExists(atPath: fileURL.path) {
            document = try JSONDecoder().decode(BlockDocument.self, from: Data(contentsOf: fileURL))
            guard document.version == 1 else { throw BlockError.unsupportedVersion }
        } else {
            document = BlockDocument()
        }
        try reconcile(at: now)
    }

    private func change(_ edit: (inout BlockDocument) throws -> Void) throws {
        var next = document
        try edit(&next)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(next)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: fileURL, options: .atomic)
        document = next
    }

    public func reconcile(at now: Date) throws {
        guard let running = document.running, now >= running.endsAt else { return }
        try change { doc in
            doc.history.append(FinishedBlock(category: running.category, startedAt: running.startedAt,
                                             endedAt: running.endsAt, plannedMinutes: running.plannedMinutes))
            doc.running = nil
            doc.pending = PendingDecision(category: running.category, expiredAt: running.endsAt)
        }
    }

    public func start(category: String, minutes: Int, at now: Date) throws {
        try reconcile(at: now)
        guard document.running == nil else { throw BlockError.alreadyRunning }
        guard document.pending == nil else { throw BlockError.decisionRequired }
        try begin(category: category, minutes: minutes, at: now, clearingDecision: false)
    }

    private func begin(category: String, minutes: Int, at now: Date, clearingDecision: Bool) throws {
        guard document.categories.contains(category) else { throw BlockError.invalidCategory }
        guard (1...240).contains(minutes) else { throw BlockError.invalidDuration }
        try change { doc in
            if clearingDecision { doc.pending = nil }
            doc.running = RunningBlock(category: category, startedAt: now,
                                       endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)), plannedMinutes: minutes)
        }
    }

    public func answer(category: String, minutes: Int, at now: Date) throws {
        try reconcile(at: now)
        guard document.pending != nil else { throw BlockError.decisionRequired }
        try begin(category: category, minutes: minutes, at: now, clearingDecision: true)
    }

    public func stop(at now: Date) throws {
        try reconcile(at: now)
        guard let running = document.running else { throw BlockError.nothingRunning }
        try change { doc in
            doc.history.append(FinishedBlock(category: running.category, startedAt: running.startedAt,
                                             endedAt: max(running.startedAt, now), plannedMinutes: running.plannedMinutes))
            doc.running = nil
            doc.pending = PendingDecision(category: running.category, expiredAt: now)
        }
    }

    public func dismissDecision() throws {
        guard document.pending != nil else { return }
        try change { $0.pending = nil }
    }

    public func addCategory(_ raw: String) throws {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, name.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw BlockError.invalidCategoryName }
        guard !document.categories.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { throw BlockError.duplicateCategory }
        try change { $0.categories.append(name) }
    }

    public func removeCategory(_ name: String) throws {
        guard document.categories.count > 1 else { throw BlockError.lastCategory }
        guard document.categories.contains(name) else { throw BlockError.invalidCategory }
        try change { $0.categories.removeAll { $0 == name } }
    }

    public func secondsRemaining(at now: Date) -> TimeInterval {
        max(0, document.running?.endsAt.timeIntervalSince(now) ?? 0)
    }

    public func totals(for day: Date, includingRunningAt now: Date? = nil) -> [String: TimeInterval] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [:] }
        var result: [String: TimeInterval] = [:]
        for block in document.history {
            let seconds = max(0, min(block.endedAt, end).timeIntervalSince(max(block.startedAt, start)))
            if seconds > 0 { result[block.category, default: 0] += seconds }
        }
        if let now, let running = document.running {
            let actualEnd = min(now, running.endsAt)
            let seconds = max(0, min(actualEnd, end).timeIntervalSince(max(running.startedAt, start)))
            if seconds > 0 { result[running.category, default: 0] += seconds }
        }
        return result
    }

    public func recentDays(endingAt now: Date, count: Int = 7) -> [(Date, TimeInterval)] {
        (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return (calendar.startOfDay(for: day), totals(for: day, includingRunningAt: now).values.reduce(0, +))
        }
    }
}
