import Foundation
import SwiftData
import Testing
@testable import RoteCore

@Suite @MainActor struct ArchiveTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func poemWithHistory() -> Poem {
        let poem = Poem.make(title: "The Tyger", author: "William Blake", rawText: Fixture.tyger.text)
        poem.sourceNote = "Songs of Experience"
        var settings = poem.settings
        settings.contextLines = 3
        poem.settings = settings
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        Handoff.perform(poem: poem, engine: engine, seedGrades: [0: .good, 1: .again], now: now)
        poem.line(order: 2)?.ladderRung = .firstWord
        var spoken = poem.askedLines.map { $0.tokens.filter(\.isWord).map(\.normalized).joined(separator: " ") }
        spoken[4] = "in what distant deeps or sky"
        let attempt = SpeechAttempt(lines: poem.tokenizedLines(), transcript: spoken.joined(separator: " "))
        Propagation.apply(attempt: attempt, to: poem, engine: engine, source: .fullRecitation, mode: .speech, now: now.addingTimeInterval(3600))
        return poem
    }

    @Test func jsonRoundTripRestoresSchedules() throws {
        let container = try RoteSchema.makeInMemoryContainer()
        let context = container.mainContext
        let original = poemWithHistory()
        context.insert(original)
        try context.save()

        let data = try PoemArchive.jsonData(PoemArchive.export([original], now: now))
        let decoded = try PoemArchive.decode(data)
        #expect(decoded.format == RoteExport.format)
        #expect(decoded.poems.count == 1)

        let restored = PoemArchive.makePoem(from: decoded.poems[0])
        context.insert(restored)
        try context.save()

        #expect(restored.id == original.id)
        #expect(restored.rawText == original.rawText)
        #expect(restored.author == "William Blake" && restored.sourceNote == "Songs of Experience")
        #expect(restored.status == .reviewing)
        #expect(restored.settings.contextLines == 3)
        #expect(restored.line(order: 2)?.ladderRung == .firstWord)
        #expect(restored.items?.count == 24)
        for item in original.items ?? [] {
            let r = restored.item(forLine: item.targetLineOrder)!
            #expect(r.id == item.id)
            #expect(r.due == item.due)
            #expect(r.stability == item.stability)
            #expect(r.schedulerState == item.schedulerState)
            #expect(r.logs?.count == item.logs?.count)
        }
        #expect(restored.item(forLine: 1)!.logs!.sorted { $0.reviewedAt < $1.reviewedAt }.map(\.grade) == [.again, .good])
        #expect(restored.wordStats?.count == original.wordStats?.count)
        #expect(restored.runItems?.map(\.scope).sorted { "\($0)" < "\($1)" } == original.runItems?.map(\.scope).sorted { "\($0)" < "\($1)" })
        // Scheduling continues from the restored state identically.
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        let later = now.addingTimeInterval(10 * 86_400)
        let a = engine.scheduler.review(engine.state(of: original.item(forLine: 3)!, now: later), grade: .good, now: later)
        let b = engine.scheduler.review(engine.state(of: restored.item(forLine: 3)!, now: later), grade: .good, now: later)
        #expect(a.due == b.due)
    }

    @Test func rejectsForeignFormats() throws {
        let bad = Data(#"{"format":"other","version":1,"exportedAt":"2027-01-01T00:00:00Z","poems":[]}"#.utf8)
        #expect(throws: PoemArchiveError.self) { try PoemArchive.decode(bad) }
        let future = Data(#"{"format":"rote.poems","version":99,"exportedAt":"2027-01-01T00:00:00Z","poems":[]}"#.utf8)
        #expect(throws: PoemArchiveError.self) { try PoemArchive.decode(future) }
    }

    @Test func plainTextExportRestoresMarkers() {
        let poem = Poem.make(title: "", author: nil, rawText: Fixture.upHill.text)
        #expect(poem.exportText == Fixture.upHill.text)
        #expect(PoemParser.parse(poem.exportText) == PoemParser.parse(Fixture.upHill.text))
    }
}
