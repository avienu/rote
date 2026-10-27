import Foundation
import Testing
@testable import RoteCore

@Suite struct HeatLevelTests {
    @Test func fourSteps() {
        #expect(HeatLevel.level(errorRate: 0, attempts: 0) == .none)
        #expect(HeatLevel.level(errorRate: 0, attempts: 5) == .none)
        #expect(HeatLevel.level(errorRate: 0.1, attempts: 10) == .low)
        #expect(HeatLevel.level(errorRate: 0.2, attempts: 5) == .mid)
        #expect(HeatLevel.level(errorRate: 0.49, attempts: 100) == .mid)
        #expect(HeatLevel.level(errorRate: 0.5, attempts: 2) == .high)
        #expect(HeatLevel.level(errorRate: 1, attempts: 1) == .high)
    }
}

@Suite @MainActor struct HeatMapTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func poemWithHistory() -> (Poem, ReviewEngine<FSRSScheduler>) {
        let poem = Poem.make(title: "The Tyger", author: nil, rawText: Fixture.tyger.text)
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        Handoff.perform(poem: poem, engine: engine, now: now)
        var spoken = poem.askedLines.map { $0.tokens.filter(\.isWord).map(\.normalized).joined(separator: " ") }
        spoken[1] = "in the forest of the night"       // one error
        spoken[5] = ""                                 // skipped
        let attempt = SpeechAttempt(lines: poem.tokenizedLines(), transcript: spoken.joined(separator: " "))
        Propagation.apply(attempt: attempt, to: poem, engine: engine, source: .fullRecitation, mode: .speech, now: now)
        return (poem, engine)
    }

    @Test func lineStatsCarryHeatAndSchedule() {
        let (poem, engine) = poemWithHistory()
        let stats = HeatMap.lineStats(poem: poem, engine: engine, now: now)
        #expect(stats.count == 24)
        let forests = poem.orderedLines[1].tokens.firstIndex { $0.normalized == "forests" }!
        #expect(stats[1].heat[forests] == .high)
        #expect(stats[1].heat.values.filter { $0 == .none }.count == 5)
        #expect(stats[5].heat.values.allSatisfy { $0 == .high })
        #expect(stats[5].recentlyWrong && !stats[0].recentlyWrong)
        #expect(stats[0].reps == 1 && stats[0].stability > 0)
        #expect(stats[0].retrievability > 0.99)
        #expect(HeatMap.retentionForecast(stats)! > 0.99)
        #expect(HeatMap.retentionForecast([]) == nil)
    }

    @Test func drillPicksWeakLinesWeakestFirst() {
        let (poem, engine) = poemWithHistory()
        // Right after the run every line is fresh, so only recent errors qualify.
        let drill = HeatMap.drillLines(HeatMap.lineStats(poem: poem, engine: engine, now: now))
        #expect(drill == [1, 5])
        // Months later the .again line (short stability) decays first.
        let later = now.addingTimeInterval(60 * 86_400)
        let stats = HeatMap.lineStats(poem: poem, engine: engine, now: later)
        let drillLater = HeatMap.drillLines(stats)
        #expect(drillLater.first == 5)
        #expect(stats[5].retrievability < stats[0].retrievability)
        #expect(HeatMap.weakestLines(stats).count == 5)
        #expect(HeatMap.weakestLines(stats).first?.lineOrder == 5)
        #expect(HeatMap.stabilityFraction(stats[5], among: stats) < HeatMap.stabilityFraction(stats[0], among: stats))
        #expect(HeatMap.stabilityFraction(stats[0], among: stats) == 1)
    }

    @Test func editResetsHeatForThatLineOnly() {
        let (poem, _) = poemWithHistory()
        var lines = Fixture.tyger.text.components(separatedBy: "\n")
        lines[1] = "In the forests of the night,"
        poem.rebuildStructure(from: lines.joined(separator: "\n"))
        let stats = poem.wordStats!
        #expect(!stats.contains { $0.lineOrder == 1 })
        #expect(stats.contains { $0.lineOrder == 5 })
    }
}
