import Foundation
import SwiftData

// Every stored property is optional or defaulted and there are no unique
// constraints, as CloudKit requires. Enums are stored as raw strings; small
// Codable values are stored as JSON `Data`.

@Model
public final class Poem {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var title: String = ""
    public var author: String?
    public var sourceNote: String?
    /// Exact text as imported. Never mutated by any mode.
    public var rawText: String = ""
    /// BCP-47; drives speech and normalization.
    public var locale: String = "en-US"
    public var statusRaw: String = PoemStatus.draft.rawValue
    public var acquisitionData: Data?
    public var settingsData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Stanza.poem) public var stanzas: [Stanza]?
    @Relationship(deleteRule: .cascade, inverse: \TransitionItem.poem) public var items: [TransitionItem]?
    @Relationship(deleteRule: .cascade, inverse: \WordStat.poem) public var wordStats: [WordStat]?
    @Relationship(deleteRule: .cascade, inverse: \RunItem.poem) public var runItems: [RunItem]?

    public init(title: String = "", author: String? = nil, rawText: String = "", locale: String = "en-US") {
        self.title = title
        self.author = author
        self.rawText = rawText
        self.locale = locale
    }

    public var status: PoemStatus {
        get { PoemStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    public var settings: PoemSettings {
        get { settingsData.flatMap { try? JSONDecoder().decode(PoemSettings.self, from: $0) } ?? PoemSettings() }
        set { settingsData = try? JSONEncoder().encode(newValue) }
    }

    public var acquisition: AcquisitionState? {
        get { acquisitionData.flatMap { try? JSONDecoder().decode(AcquisitionState.self, from: $0) } }
        set { acquisitionData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    public var orderedStanzas: [Stanza] { (stanzas ?? []).sorted { $0.order < $1.order } }
    public var orderedLines: [Line] { orderedStanzas.flatMap(\.orderedLines) }
    public var askedLines: [Line] { orderedLines.filter { !$0.isContext } }
    public func line(order: Int) -> Line? { orderedLines.first { $0.order == order } }
    public func item(forLine order: Int) -> TransitionItem? { (items ?? []).first { $0.targetLineOrder == order } }
    public func dueItems(now: Date) -> [TransitionItem] { (items ?? []).filter { $0.due <= now } }
}

@Model
public final class Stanza {
    public var id: UUID = UUID()
    public var order: Int = 0
    public var poem: Poem?
    @Relationship(deleteRule: .cascade, inverse: \Line.stanza) public var lines: [Line]?

    public init(order: Int) {
        self.order = order
    }

    public var orderedLines: [Line] { (lines ?? []).sorted { $0.order < $1.order } }
}

@Model
public final class Line {
    public var id: UUID = UUID()
    /// Global within the poem, 0-based.
    public var order: Int = 0
    /// Exact text including leading whitespace.
    public var text: String = ""
    /// Shown but never asked.
    public var isContext: Bool = false
    /// Cached `[Token]` as JSON; rebuilt whenever `text` changes.
    public var tokensData: Data?
    public var ladderRungRaw: Int = LadderRung.full.rawValue
    public var stanza: Stanza?

    public init(order: Int, text: String, isContext: Bool, locale: String) {
        self.order = order
        self.text = text
        self.isContext = isContext
        rebuildTokens(locale: locale)
    }

    public var tokens: [Token] {
        get { tokensData.flatMap { try? JSONDecoder().decode([Token].self, from: $0) } ?? [] }
        set { tokensData = try? JSONEncoder().encode(newValue) }
    }

    public var ladderRung: LadderRung {
        get { LadderRung(rawValue: ladderRungRaw) ?? .full }
        set { ladderRungRaw = newValue.rawValue }
    }

    public func rebuildTokens(locale: String) {
        tokens = Tokenizer.tokenize(text, locale: locale)
    }

    public var wordCount: Int { tokens.filter(\.isWord).count }
}

/// The FSRS unit: "given the previous lines, produce line `targetLineOrder`".
@Model
public final class TransitionItem {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var poem: Poem?
    public var targetLineOrder: Int = 0
    /// Opaque, owned by the `Scheduler`.
    public var schedulerState: Data?
    public var due: Date = Date()
    public var stability: Double = 0
    public var difficulty: Double = 0
    public var lapses: Int = 0
    public var reps: Int = 0
    public var lastReviewedAt: Date?
    /// Days between the last two reviews; used by the propagation guardrail.
    public var previousIntervalDays: Double = 0
    /// Lapses in a row; two in a row opens the next card at `.firstLetters` (§6.5).
    public var consecutiveLapses: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.item) public var logs: [ReviewLog]?

    public init(targetLineOrder: Int, due: Date = Date()) {
        self.targetLineOrder = targetLineOrder
        self.due = due
    }
}

@Model
public final class ReviewLog {
    public var id: UUID = UUID()
    public var item: TransitionItem?
    public var reviewedAt: Date = Date()
    public var gradeRaw: String = Grade.good.rawValue
    public var sourceRaw: String = ReviewSource.transitionCard.rawValue
    public var modeRaw: String = InputMode.selfGrade.rawValue
    public var wordErrors: Int?
    public var wordCount: Int?
    public var elapsedMs: Int?
    public var hintsUsed: Int = 0
    public var asrCorrections: Int = 0
    /// Days since the previous review, for the optimizer later.
    public var elapsedDays: Double?
    /// Interval scheduled by this review, in days.
    public var scheduledDays: Double?

    public init(reviewedAt: Date, grade: Grade, source: ReviewSource, mode: InputMode) {
        self.reviewedAt = reviewedAt
        self.gradeRaw = grade.rawValue
        self.sourceRaw = source.rawValue
        self.modeRaw = mode.rawValue
    }

    public var grade: Grade {
        get { Grade(rawValue: gradeRaw) ?? .good }
        set { gradeRaw = newValue.rawValue }
    }
    public var source: ReviewSource {
        get { ReviewSource(rawValue: sourceRaw) ?? .transitionCard }
        set { sourceRaw = newValue.rawValue }
    }
    public var mode: InputMode {
        get { InputMode(rawValue: modeRaw) ?? .selfGrade }
        set { modeRaw = newValue.rawValue }
    }
}

/// Heat-map source: one row per asked word.
@Model
public final class WordStat {
    public var id: UUID = UUID()
    public var poem: Poem?
    public var lineOrder: Int = 0
    public var tokenIndex: Int = 0
    public var attempts: Int = 0
    public var errors: Int = 0
    public var lastErrorAt: Date?
    /// Outcomes of the last few attempts, newest last: "0" correct, "1" error.
    public var recentHistory: String = ""

    public init(lineOrder: Int, tokenIndex: Int) {
        self.lineOrder = lineOrder
        self.tokenIndex = tokenIndex
    }

    public static let historyLength = 8

    public func record(error: Bool, at date: Date) {
        attempts += 1
        if error {
            errors += 1
            lastErrorAt = date
        }
        recentHistory.append(error ? "1" : "0")
        if recentHistory.count > Self.historyLength {
            recentHistory.removeFirst(recentHistory.count - Self.historyLength)
        }
    }

    /// Error rate over all attempts; 0 when never attempted.
    public var errorRate: Double { attempts == 0 ? 0 : Double(errors) / Double(attempts) }

    /// True when either of the last two attempts was an error.
    public var recentlyWrong: Bool { recentHistory.suffix(2).contains("1") }
}

/// Whole-poem or stanza recitation chain (§6.4).
@Model
public final class RunItem {
    public var id: UUID = UUID()
    public var poem: Poem?
    /// Nil for the whole poem, otherwise the stanza's `order`.
    public var stanzaOrder: Int?
    public var due: Date = Date()
    public var lastRunAt: Date?

    public init(scope: RunScope, due: Date) {
        self.scope = scope
        self.due = due
    }

    public var scope: RunScope {
        get { stanzaOrder.map { .stanza($0) } ?? .wholePoem }
        set {
            switch newValue {
            case .wholePoem: stanzaOrder = nil
            case .stanza(let o): stanzaOrder = o
            }
        }
    }
}

public enum RoteSchema {
    public static let models: [any PersistentModel.Type] = [
        Poem.self, Stanza.self, Line.self, TransitionItem.self, ReviewLog.self, WordStat.self, RunItem.self,
    ]

    public static let cloudKitContainer = "iCloud.com.avienu.rote"

    /// In-memory container for tests and previews.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(models), configurations: [config])
    }

    /// Persistent container. With `cloudKit` true it syncs through the private
    /// CloudKit database; callers pass false when the process lacks the iCloud
    /// entitlement (unsigned development builds), since CloudKit setup traps
    /// asynchronously rather than throwing.
    public static func makePersistentContainer(cloudKit: Bool) throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: cloudKit ? .private(cloudKitContainer) : .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
