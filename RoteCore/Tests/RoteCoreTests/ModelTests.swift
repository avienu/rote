import Foundation
import SwiftData
import Testing
@testable import RoteCore

@Suite @MainActor struct ModelTests {
    @Test func buildsStructureFromText() throws {
        let container = try RoteSchema.makeInMemoryContainer()
        let context = container.mainContext
        let poem = Poem.make(title: "The Tyger", author: "William Blake", rawText: Fixture.tyger.text)
        context.insert(poem)
        try context.save()

        #expect(poem.orderedStanzas.count == 6)
        #expect(poem.orderedLines.count == 24)
        #expect(poem.orderedLines[8].text == "And what shoulder, & what art,")
        #expect(poem.orderedLines[8].tokens.filter(\.isWord).count == 5)
        #expect(poem.rawText == Fixture.tyger.text)
    }

    @Test func contextLinesAreNotAsked() throws {
        let poem = Poem.make(title: "", author: nil, rawText: Fixture.upHill.text)
        #expect(poem.title == "The traveller asks; the indented lines answer.")
        #expect(poem.askedLines.count == 16)
        #expect(poem.orderedLines[0].isContext)
    }

    @Test func editKeepsItemsResetsStatsRebuildsTokens() throws {
        let container = try RoteSchema.makeInMemoryContainer()
        let context = container.mainContext
        let poem = Poem.make(title: "S30", author: nil, rawText: Fixture.sonnet30.text)
        context.insert(poem)
        poem.status = .reviewing
        poem.items = poem.askedLines.map { TransitionItem(targetLineOrder: $0.order) }
        poem.items?.first { $0.targetLineOrder == 1 }?.stability = 42
        let s1 = WordStat(lineOrder: 1, tokenIndex: 0); s1.attempts = 3
        let s2 = WordStat(lineOrder: 2, tokenIndex: 0); s2.attempts = 3
        poem.wordStats = [s1, s2]
        try context.save()

        var lines = Fixture.sonnet30.text.components(separatedBy: "\n")
        lines[1] = "I summon up remembrance of things past;"   // punctuation change on line 1
        poem.rebuildStructure(from: lines.joined(separator: "\n"))
        try context.save()

        #expect(poem.orderedLines[1].text.hasSuffix(";"))
        #expect(poem.orderedLines[1].tokens.last?.surface == ";")
        #expect(poem.item(forLine: 1)?.stability == 42)        // schedule survives
        #expect(poem.items?.count == 14)
        #expect(poem.wordStats?.map(\.lineOrder) == [2])       // only the edited line reset
    }

    @Test func editAddingLinesCreatesItemsWhenReviewing() throws {
        let poem = Poem.make(title: "T", author: nil, rawText: "a b\nc d")
        poem.status = .reviewing
        poem.items = [TransitionItem(targetLineOrder: 0), TransitionItem(targetLineOrder: 1)]
        poem.rebuildStructure(from: "a b\nc d\n@note\ne f")
        #expect(poem.items?.map(\.targetLineOrder).sorted() == [0, 1, 3])
    }

    @Test func settingsAndAcquisitionRoundTrip() {
        let poem = Poem.make(title: "T", author: nil, rawText: "x")
        var s = poem.settings
        s.contextLines = 3
        poem.settings = s
        var a = AcquisitionState()
        a.phase = .windowing
        a.windowSize = 4
        a.consolidationPasses = [ConsolidationPass(recitedAt: Date(timeIntervalSince1970: 0), accuracy: 0.9, lineAccuracy: [0: 1, 1: 0.8])]
        poem.acquisition = a
        #expect(poem.settings.contextLines == 3)
        #expect(poem.acquisition == a)
    }

    @Test func wordStatHistory() {
        let stat = WordStat(lineOrder: 0, tokenIndex: 0)
        for i in 0..<10 { stat.record(error: i % 3 == 0, at: Date()) }
        #expect(stat.attempts == 10)
        #expect(stat.errors == 4)
        #expect(stat.recentHistory.count == WordStat.historyLength)
        #expect(stat.recentlyWrong)
    }

    @Test func runScopeMapsToStorage() {
        let run = RunItem(scope: .stanza(3), due: Date())
        #expect(run.stanzaOrder == 3)
        run.scope = .wholePoem
        #expect(run.stanzaOrder == nil)
        #expect(run.scope == .wholePoem)
    }

    @Test func exportRestoresContextMarkers() {
        let poem = Poem.make(title: "", author: nil, rawText: Fixture.upHill.text)
        #expect(poem.exportText == Fixture.upHill.text)
    }
}
