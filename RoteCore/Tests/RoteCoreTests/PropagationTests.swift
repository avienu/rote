import Foundation
import Testing
@testable import RoteCore

@Suite struct PropagationGradeTests {
    func line(_ order: Int, words: Int, errors: Int, skipped: Bool = false) -> LineAlignment {
        let ops = (0..<words).map { i in
            LineAlignment.TokenOp(tokenIndex: i, op: skipped ? .deletion : (i < errors ? .substitution : .match), hypothesisIndex: skipped ? nil : i)
        }
        return LineAlignment(lineOrder: order, wordCount: words, errors: skipped ? words : errors, insertions: 0, tokenOps: ops, firstHypothesisIndex: skipped ? nil : 0)
    }

    @Test func mappingNeverEasy() {
        let g = Propagation.grades(for: [line(0, words: 20, errors: 0), line(1, words: 10, errors: 1), line(2, words: 10, errors: 3)])
        #expect(g.map(\.grade) == [.good, .hard, .again])
        #expect(g.allSatisfy { $0.grade != .easy })
        #expect(g[0].reasons == [.accuracy])
    }

    @Test func skippedLineRule() {
        let g = Propagation.grades(for: [line(0, words: 5, errors: 0), line(1, words: 5, errors: 0, skipped: true), line(2, words: 5, errors: 0), line(3, words: 5, errors: 0)])
        #expect(g[1].grade == .again && g[1].reasons == [.skipped])
        #expect(g[2].grade == .hard && g[2].reasons.contains(.afterSkipped))
        #expect(g[3].grade == .good)
    }

    @Test func hesitationCapsAtHard() {
        let g = Propagation.grades(for: [line(0, words: 5, errors: 0), line(1, words: 5, errors: 0)]) { $0 == 1 }
        #expect(g[0].grade == .good)
        #expect(g[1].grade == .hard && g[1].reasons.contains(.hesitation))
        // A hesitation never lifts an .again.
        let h = Propagation.grades(for: [line(0, words: 5, errors: 3)]) { _ in true }
        #expect(h[0].grade == .again)
    }
}

@Suite @MainActor struct PropagationApplyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func reviewingPoem() -> (Poem, ReviewEngine<FSRSScheduler>) {
        let poem = Poem.make(title: "The Tyger", author: nil, rawText: Fixture.tyger.text)
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        Handoff.perform(poem: poem, engine: engine, now: now)
        return (poem, engine)
    }

    @Test func oneRecitationUpdatesEveryLine() {
        let (poem, engine) = reviewingPoem()
        var spoken = poem.askedLines.map { $0.tokens.filter(\.isWord).map(\.normalized).joined(separator: " ") }
        spoken[2] = "what immortal hand or foot"             // one error of 5 → 80% → hard
        spoken[7] = ""                                       // skipped → again, line 8 capped at hard
        let attempt = SpeechAttempt(lines: poem.tokenizedLines(), transcript: spoken.joined(separator: " "))
        let report = Propagation.apply(attempt: attempt, to: poem, engine: engine, source: .fullRecitation, mode: .speech, now: now)

        #expect(report.grades.count == 24)
        #expect(poem.items!.allSatisfy { $0.reps == 1 && $0.lastReviewedAt == now })
        #expect(report.grades[2].grade == .hard)
        #expect(report.grades[7].grade == .again)
        #expect(report.grades[8].grade == .hard)
        #expect(report.grades[0].grade == .good)
        let logs = poem.items!.flatMap { $0.logs ?? [] }
        #expect(logs.count == 24)
        #expect(logs.allSatisfy { $0.source == .fullRecitation && $0.mode == .speech })
        #expect(poem.item(forLine: 7)!.due < poem.item(forLine: 0)!.due)
        // Word stats: every asked token got an attempt; the substituted word has an error.
        let stats = poem.wordStats!
        #expect(stats.count == poem.askedLines.reduce(0) { $0 + $1.wordCount })
        #expect(stats.allSatisfy { $0.attempts == 1 })
        let hand = poem.orderedLines[2].tokens.firstIndex { $0.normalized == "eye" }!
        #expect(stats.first { $0.lineOrder == 2 && $0.tokenIndex == hand }!.errors == 1)
        #expect(stats.filter { $0.lineOrder == 7 }.allSatisfy { $0.errors == 1 })
        #expect(report.cappedLines.isEmpty)   // fresh items have no interval to cap against
    }

    @Test func guardrailCapsLuckyRunThrough() {
        let (poem, engine) = reviewingPoem()
        let item = poem.item(forLine: 0)!
        // Give the item a short real interval first.
        engine.apply(grade: .hard, to: item, now: now, source: .transitionCard, mode: .selfGrade)
        let interval = item.previousIntervalDays
        #expect(interval > 0)
        let later = now.addingTimeInterval(interval * 86_400)
        let perfect = poem.askedLines.map { $0.tokens.filter(\.isWord).map(\.normalized).joined(separator: " ") }.joined(separator: " ")
        let attempt = SpeechAttempt(lines: poem.tokenizedLines(), transcript: perfect)
        let report = Propagation.apply(attempt: attempt, to: poem, engine: engine, source: .fullRecitation, mode: .speech, now: later)
        let cap = later.addingTimeInterval(interval * Propagation.guardrailMultiplier * 86_400)
        #expect(item.due <= cap)
        #expect(report.grades.allSatisfy { $0.grade == .good })
        // Compare with what the scheduler alone would have proposed.
        let uncapped = engine.scheduler.review(engine.state(of: poem.item(forLine: 1)!, now: later), grade: .good, now: later).due
        if uncapped > cap { #expect(report.cappedLines.contains(0)) }
    }

    @Test func maxDueIsNilForFreshItems() {
        let item = TransitionItem(targetLineOrder: 0)
        #expect(Propagation.maxDue(for: item, now: now) == nil)
        item.previousIntervalDays = 5
        #expect(Propagation.maxDue(for: item, now: now) == now.addingTimeInterval(10 * 86_400))
    }
}

@Suite @MainActor struct RunSchedulingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day = 86_400.0

    @Test func handoffCreatesRunsExceptForSingleStanza() {
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        let tyger = Poem.make(title: "", author: nil, rawText: Fixture.tyger.text)
        Handoff.perform(poem: tyger, engine: engine, now: now)
        let scopes = tyger.runItems!.map(\.scope)
        #expect(scopes.count == 7)
        #expect(scopes.contains(.wholePoem))
        #expect((0..<6).allSatisfy { scopes.contains(.stanza($0)) })

        let sonnet = Poem.make(title: "", author: nil, rawText: Fixture.sonnet30.text)
        Handoff.perform(poem: sonnet, engine: engine, now: now)
        #expect(sonnet.runItems!.map(\.scope) == [.wholePoem])
        #expect(RunScheduling.askedOrders(poem: sonnet, scope: .wholePoem).count == 14)
    }

    @Test func dueChain() {
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        let poem = Poem.make(title: "", author: nil, rawText: Fixture.tyger.text)
        Handoff.perform(poem: poem, engine: engine, now: now)
        // Review stanza 0's lines so their due dates move out; the rest stay due now.
        for order in 0..<4 { engine.apply(grade: .good, to: poem.item(forLine: order)!, now: now, source: .transitionCard, mode: .selfGrade) }
        RunScheduling.recompute(poem: poem, now: now)
        let s0 = poem.runItems!.first { $0.scope == .stanza(0) }!
        let s1 = poem.runItems!.first { $0.scope == .stanza(1) }!
        let whole = poem.runItems!.first { $0.scope == .wholePoem }!
        let earliest0 = (0..<4).map { poem.item(forLine: $0)!.due }.min()!
        #expect(s0.due == earliest0.addingTimeInterval(day))
        #expect(s1.due == now.addingTimeInterval(day))
        #expect(whole.due == now.addingTimeInterval(3 * day))      // earliest stanza run + 2 days
        #expect(RunScheduling.askedOrders(poem: poem, scope: .stanza(2)) == [8, 9, 10, 11])

        // Completing the whole-poem run applies the 3-day floor.
        RunScheduling.complete(run: whole, poem: poem, now: now.addingTimeInterval(5 * day))
        #expect(whole.due == now.addingTimeInterval(8 * day))
        #expect(RunScheduling.dueRuns(poem: poem, now: now.addingTimeInterval(2 * day)).map(\.scope).contains(.stanza(1)))
    }
}
