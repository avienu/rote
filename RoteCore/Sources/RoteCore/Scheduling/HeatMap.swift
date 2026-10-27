import Foundation

/// Four-step word tint (§8): reads at a glance, no continuous scale.
public enum HeatLevel: Int, Hashable, Sendable, Comparable, CaseIterable {
    case none = 0, low, mid, high

    public static func < (a: HeatLevel, b: HeatLevel) -> Bool { a.rawValue < b.rawValue }

    public static let lowCutoff = 0.2
    public static let highCutoff = 0.5

    /// errors / attempts → level. Never-attempted words are `.none`.
    public static func level(errorRate: Double, attempts: Int) -> HeatLevel {
        guard attempts > 0, errorRate > 0 else { return .none }
        if errorRate >= highCutoff { return .high }
        if errorRate >= lowCutoff { return .mid }
        return .low
    }
}

public struct LineStats: Hashable, Sendable {
    public var lineOrder: Int
    public var retrievability: Double
    public var stability: Double
    public var difficulty: Double
    public var due: Date?
    public var lapses: Int
    public var reps: Int
    /// Heat level per token index.
    public var heat: [Int: HeatLevel]
    public var recentlyWrong: Bool

    public init(lineOrder: Int, retrievability: Double, stability: Double, difficulty: Double, due: Date?,
                lapses: Int, reps: Int, heat: [Int: HeatLevel], recentlyWrong: Bool) {
        self.lineOrder = lineOrder
        self.retrievability = retrievability
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.lapses = lapses
        self.reps = reps
        self.heat = heat
        self.recentlyWrong = recentlyWrong
    }
}

/// Heat map and drill selection (§8).
public enum HeatMap {
    public static let drillRetrievability = 0.7
    public static let weakestCount = 5

    public static func lineStats<S: Scheduler>(poem: Poem, engine: ReviewEngine<S>, now: Date) -> [LineStats] {
        let stats = poem.wordStats ?? []
        return poem.askedLines.map { line in
            let item = poem.item(forLine: line.order)
            let lineStats = stats.filter { $0.lineOrder == line.order }
            let heat = Dictionary(uniqueKeysWithValues: lineStats.map { ($0.tokenIndex, HeatLevel.level(errorRate: $0.errorRate, attempts: $0.attempts)) })
            return LineStats(lineOrder: line.order,
                             retrievability: item.map { engine.retrievability(of: $0, now: now) } ?? 0,
                             stability: item?.stability ?? 0,
                             difficulty: item?.difficulty ?? 0,
                             due: item?.due,
                             lapses: item?.lapses ?? 0,
                             reps: item?.reps ?? 0,
                             heat: heat,
                             recentlyWrong: lineStats.contains { $0.recentlyWrong })
        }
    }

    /// Mean retrievability over the poem's items; nil when there are none.
    public static func retentionForecast(_ stats: [LineStats]) -> Double? {
        guard !stats.isEmpty else { return nil }
        return stats.map(\.retrievability).reduce(0, +) / Double(stats.count)
    }

    /// Lines whose retrievability is under 0.7 or whose last two word attempts
    /// show an error, weakest first.
    public static func drillLines(_ stats: [LineStats]) -> [Int] {
        stats.filter { $0.retrievability < drillRetrievability || $0.recentlyWrong }
            .sorted { a, b in
                if a.retrievability != b.retrievability { return a.retrievability < b.retrievability }
                return a.lineOrder < b.lineOrder
            }
            .map(\.lineOrder)
    }

    /// The weakest lines by retrievability, for the stats box.
    public static func weakestLines(_ stats: [LineStats], count: Int = weakestCount) -> [LineStats] {
        Array(stats.sorted { $0.retrievability < $1.retrievability }.prefix(count))
    }

    /// Gutter bar length: stability relative to the poem's strongest line, 0…1.
    public static func stabilityFraction(_ stat: LineStats, among stats: [LineStats]) -> Double {
        let maxStability = stats.map(\.stability).max() ?? 0
        guard maxStability > 0 else { return 0 }
        return stat.stability / maxStability
    }
}

extension LineStats: Identifiable {
    public var id: Int { lineOrder }
}
