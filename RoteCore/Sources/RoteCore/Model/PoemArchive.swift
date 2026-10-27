import Foundation

// JSON export/import (§11): the poem plus items, logs, word stats and runs,
// so a restore keeps every schedule and the optimizer can read the history.

public struct RoteExport: Codable, Hashable, Sendable {
    public static let format = "rote.poems"
    public static let version = 1

    public var format: String = RoteExport.format
    public var version: Int = RoteExport.version
    public var exportedAt: Date
    public var poems: [PoemExport]

    public init(exportedAt: Date, poems: [PoemExport]) {
        self.exportedAt = exportedAt
        self.poems = poems
    }
}

public struct PoemExport: Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var author: String?
    public var sourceNote: String?
    public var rawText: String
    public var locale: String
    public var status: PoemStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var settings: PoemSettings
    public var queueOrder: Int?
    public var acquisition: AcquisitionState?
    /// Line order → rung raw value.
    public var rungs: [Int: Int]
    public var items: [ItemExport]
    public var wordStats: [WordStatExport]
    public var runs: [RunExport]
}

public struct ItemExport: Codable, Hashable, Sendable {
    public var id: UUID
    public var targetLineOrder: Int
    public var schedulerState: Data?
    public var due: Date
    public var stability: Double
    public var difficulty: Double
    public var lapses: Int
    public var reps: Int
    public var lastReviewedAt: Date?
    public var previousIntervalDays: Double
    public var consecutiveLapses: Int
    public var logs: [LogExport]
}

public struct LogExport: Codable, Hashable, Sendable {
    public var id: UUID
    public var reviewedAt: Date
    public var grade: Grade
    public var source: ReviewSource
    public var mode: InputMode
    public var wordErrors: Int?
    public var wordCount: Int?
    public var elapsedMs: Int?
    public var hintsUsed: Int
    public var asrCorrections: Int
    public var elapsedDays: Double?
    public var scheduledDays: Double?
}

public struct WordStatExport: Codable, Hashable, Sendable {
    public var lineOrder: Int
    public var tokenIndex: Int
    public var attempts: Int
    public var errors: Int
    public var lastErrorAt: Date?
    public var recentHistory: String
}

public struct RunExport: Codable, Hashable, Sendable {
    public var stanzaOrder: Int?
    public var due: Date
    public var lastRunAt: Date?
}

public enum PoemArchiveError: Error, Sendable {
    case unknownFormat(String)
    case unsupportedVersion(Int)
}

public enum PoemArchive {
    public static func export(_ poems: [Poem], now: Date = Date()) -> RoteExport {
        RoteExport(exportedAt: now, poems: poems.map(export))
    }

    public static func export(_ poem: Poem) -> PoemExport {
        PoemExport(
            id: poem.id, title: poem.title, author: poem.author, sourceNote: poem.sourceNote, rawText: poem.rawText,
            locale: poem.locale, status: poem.status, createdAt: poem.createdAt, updatedAt: poem.updatedAt,
            settings: poem.settings, queueOrder: poem.queueOrder, acquisition: poem.acquisition,
            rungs: Dictionary(uniqueKeysWithValues: poem.orderedLines.map { ($0.order, $0.ladderRungRaw) }),
            items: (poem.items ?? []).sorted { $0.targetLineOrder < $1.targetLineOrder }.map { item in
                ItemExport(id: item.id, targetLineOrder: item.targetLineOrder, schedulerState: item.schedulerState, due: item.due,
                           stability: item.stability, difficulty: item.difficulty, lapses: item.lapses, reps: item.reps,
                           lastReviewedAt: item.lastReviewedAt, previousIntervalDays: item.previousIntervalDays,
                           consecutiveLapses: item.consecutiveLapses,
                           logs: (item.logs ?? []).sorted { $0.reviewedAt < $1.reviewedAt }.map { log in
                               LogExport(id: log.id, reviewedAt: log.reviewedAt, grade: log.grade, source: log.source, mode: log.mode,
                                         wordErrors: log.wordErrors, wordCount: log.wordCount, elapsedMs: log.elapsedMs,
                                         hintsUsed: log.hintsUsed, asrCorrections: log.asrCorrections,
                                         elapsedDays: log.elapsedDays, scheduledDays: log.scheduledDays)
                           })
            },
            wordStats: (poem.wordStats ?? []).map {
                WordStatExport(lineOrder: $0.lineOrder, tokenIndex: $0.tokenIndex, attempts: $0.attempts, errors: $0.errors,
                               lastErrorAt: $0.lastErrorAt, recentHistory: $0.recentHistory)
            },
            runs: (poem.runItems ?? []).map { RunExport(stanzaOrder: $0.stanzaOrder, due: $0.due, lastRunAt: $0.lastRunAt) }
        )
    }

    public static func jsonData(_ export: RoteExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    public static func decode(_ data: Data) throws -> RoteExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(RoteExport.self, from: data)
        guard export.format == RoteExport.format else { throw PoemArchiveError.unknownFormat(export.format) }
        guard export.version <= RoteExport.version else { throw PoemArchiveError.unsupportedVersion(export.version) }
        return export
    }

    /// Builds fresh model objects from an export. The caller inserts them.
    /// Restored poems keep their ids so a re-import can be matched by the caller.
    public static func makePoem(from e: PoemExport) -> Poem {
        let poem = Poem.make(title: e.title, author: e.author, rawText: e.rawText, locale: e.locale)
        poem.id = e.id
        poem.sourceNote = e.sourceNote
        poem.status = e.status
        poem.createdAt = e.createdAt
        poem.updatedAt = e.updatedAt
        poem.settings = e.settings
        poem.acquisition = e.acquisition
        poem.queueOrder = e.queueOrder
        for line in poem.orderedLines {
            if let raw = e.rungs[line.order] { line.ladderRungRaw = raw }
        }
        poem.items = e.items.map { i in
            let item = TransitionItem(targetLineOrder: i.targetLineOrder, due: i.due)
            item.id = i.id
            item.schedulerState = i.schedulerState
            item.stability = i.stability
            item.difficulty = i.difficulty
            item.lapses = i.lapses
            item.reps = i.reps
            item.lastReviewedAt = i.lastReviewedAt
            item.previousIntervalDays = i.previousIntervalDays
            item.consecutiveLapses = i.consecutiveLapses
            item.poem = poem
            item.logs = i.logs.map { l in
                let log = ReviewLog(reviewedAt: l.reviewedAt, grade: l.grade, source: l.source, mode: l.mode)
                log.id = l.id
                log.wordErrors = l.wordErrors
                log.wordCount = l.wordCount
                log.elapsedMs = l.elapsedMs
                log.hintsUsed = l.hintsUsed
                log.asrCorrections = l.asrCorrections
                log.elapsedDays = l.elapsedDays
                log.scheduledDays = l.scheduledDays
                log.item = item
                return log
            }
            return item
        }
        poem.wordStats = e.wordStats.map { w in
            let stat = WordStat(lineOrder: w.lineOrder, tokenIndex: w.tokenIndex)
            stat.attempts = w.attempts
            stat.errors = w.errors
            stat.lastErrorAt = w.lastErrorAt
            stat.recentHistory = w.recentHistory
            stat.poem = poem
            return stat
        }
        poem.runItems = e.runs.map { r in
            let run = RunItem(scope: r.stanzaOrder.map { .stanza($0) } ?? .wholePoem, due: r.due)
            run.lastRunAt = r.lastRunAt
            run.poem = poem
            return run
        }
        return poem
    }
}
