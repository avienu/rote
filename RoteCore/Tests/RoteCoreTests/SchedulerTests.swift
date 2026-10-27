import Foundation
import Testing
@testable import RoteCore

@Suite struct SchedulerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func stateRoundTripsThroughJSON() throws {
        let s = FSRSScheduler()
        let out = s.review(s.newState(now: now), grade: .good, now: now)
        let data = try JSONEncoder().encode(out.state)
        let back = try JSONDecoder().decode(FSRSScheduler.State.self, from: data)
        #expect(back == out.state)
    }

    @Test func dueIsMonotonicUnderGood() {
        let s = FSRSScheduler()
        var state = s.newState(now: now)
        var clock = now
        var lastInterval = 0.0
        for _ in 0..<6 {
            let out = s.review(state, grade: .good, now: clock)
            #expect(out.due > clock)
            #expect(out.scheduledDays >= lastInterval)
            lastInterval = out.scheduledDays
            state = out.state
            clock = out.due
        }
        #expect(lastInterval > 10)
    }

    @Test func againShortensAndCountsLapse() {
        let s = FSRSScheduler()
        var state = s.newState(now: now)
        var clock = now
        for _ in 0..<3 {
            let out = s.review(state, grade: .good, now: clock)
            state = out.state; clock = out.due
        }
        let before = s.review(state, grade: .good, now: clock).scheduledDays
        let lapse = s.review(state, grade: .again, now: clock)
        #expect(lapse.scheduledDays < before)
        #expect(lapse.lapses == 1)
    }

    @Test func retrievabilityDecaysOverTime() {
        let s = FSRSScheduler()
        let out = s.review(s.newState(now: now), grade: .good, now: now)
        let r0 = s.retrievability(out.state, now: now)
        let r1 = s.retrievability(out.state, now: out.due)
        let r2 = s.retrievability(out.state, now: out.due.addingTimeInterval(30 * 86_400))
        #expect(r0 > 0.99)
        #expect(r1 < r0 && r1 > 0.8)   // near desired retention at due
        #expect(r2 < r1)
        #expect(s.retrievability(s.newState(now: now), now: now) == 0)
    }

    @Test func desiredRetentionIsClamped() {
        #expect(FSRSScheduler(desiredRetention: 0.5).desiredRetention == 0.80)
        #expect(FSRSScheduler(desiredRetention: 0.99).desiredRetention == 0.97)
        #expect(FSRSScheduler(desiredRetention: 0.9).desiredRetention == 0.9)
    }
}

@Suite @MainActor struct ReviewEngineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func applyUpdatesItemAndLogs() throws {
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        let item = TransitionItem(targetLineOrder: 3, due: now)
        let log = engine.apply(grade: .good, to: item, now: now, source: .transitionCard, mode: .firstLetterTyping,
                               wordErrors: 1, wordCount: 8, elapsedMs: 4200)
        #expect(item.due > now)
        #expect(item.reps == 1)
        #expect(item.stability > 0)
        #expect(item.lastReviewedAt == now)
        #expect(item.schedulerState != nil)
        #expect(item.previousIntervalDays > 0)
        #expect(item.logs?.count == 1)
        #expect(log.grade == .good && log.mode == .firstLetterTyping && log.wordErrors == 1)
        #expect(engine.retrievability(of: item, now: now) > 0.99)
    }

    @Test func stateSurvivesReload() {
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        let item = TransitionItem(targetLineOrder: 0, due: now)
        engine.apply(grade: .good, to: item, now: now, source: .transitionCard, mode: .selfGrade)
        let later = item.due
        engine.apply(grade: .good, to: item, now: later, source: .transitionCard, mode: .selfGrade)
        #expect(item.reps == 2)
        #expect(item.due > later)
    }

    @Test func twoLapsesOpenFirstLetters() {
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        let item = TransitionItem(targetLineOrder: 0, due: now)
        engine.apply(grade: .again, to: item, now: now, source: .transitionCard, mode: .selfGrade)
        #expect(!item.opensWithFirstLetters)
        engine.apply(grade: .again, to: item, now: now.addingTimeInterval(60), source: .transitionCard, mode: .selfGrade)
        #expect(item.opensWithFirstLetters)
        engine.apply(grade: .good, to: item, now: now.addingTimeInterval(120), source: .transitionCard, mode: .selfGrade)
        #expect(!item.opensWithFirstLetters)
    }

    @Test func maxDueCapsSchedule() {
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        let item = TransitionItem(targetLineOrder: 0, due: now)
        let cap = now.addingTimeInterval(86_400)
        engine.apply(grade: .easy, to: item, now: now, source: .fullRecitation, mode: .speech, maxDue: cap)
        #expect(item.due == cap)
    }
}

@Suite struct GradeProposalTests {
    @Test func cardMapping() {
        #expect(GradeProposal.forCard(accuracy: 1.0) == .good)
        #expect(GradeProposal.forCard(accuracy: 0.95) == .good)
        #expect(GradeProposal.forCard(accuracy: 0.9) == .hard)
        #expect(GradeProposal.forCard(accuracy: 0.79) == .again)
    }

    @Test func hintCaps() {
        #expect(GradeProposal.forCard(accuracy: 1, hint: .nextLetter) == .good)
        #expect(GradeProposal.forCard(accuracy: 1, hint: .nextWord) == .hard)
        #expect(GradeProposal.forCard(accuracy: 1, hint: .wholeLine) == .again)
        #expect(GradeProposal.maxGrade(hint: .none, capAtGood: false) == .easy)
        #expect(GradeProposal.maxGrade(hint: .none, capAtGood: true) == .good)
        #expect(GradeProposal.maxGrade(hint: .nextWord, capAtGood: true) == .hard)
    }

    @Test func propagationNeverEasy() {
        for a in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(GradeProposal.forPropagation(accuracy: a) != .easy)
        }
        #expect(GradeProposal.forHandoff(accuracy: 0.96) == .easy)
        #expect(GradeProposal.forHandoff(accuracy: 0.6) == .again)
    }
}

@Suite struct ReviewQueueTests {
    func cards(poems: Int, perPoem: Int) -> [QueueCard] {
        (0..<poems).flatMap { p in
            let pid = UUID()
            return (0..<perPoem).map { i in
                QueueCard(itemID: UUID(), poemID: pid, lineOrder: i, contextOrders: [max(0, i - 2), max(0, i - 1)].filter { $0 < i })
            }
        }
    }

    @Test func noAdjacentSamePoemWhenAlternativesExist() {
        let all = cards(poems: 3, perPoem: 5)
        for seed in UInt64(1)...20 {
            let ordered = ReviewQueue.order(all, seed: seed)
            #expect(ordered.count == all.count)
            #expect(Set(ordered) == Set(all))
            for (a, b) in zip(ordered, ordered.dropFirst()) {
                #expect(a.poemID != b.poemID)
            }
        }
    }

    @Test func singlePoemStillReturnsEverything() {
        let all = cards(poems: 1, perPoem: 6)
        let ordered = ReviewQueue.order(all, seed: 7)
        #expect(Set(ordered) == Set(all))
    }

    @Test func lineNotAskedSoonAfterBeingContext() {
        let all = cards(poems: 1, perPoem: 12)
        for seed in UInt64(1)...30 {
            let ordered = ReviewQueue.order(all, seed: seed)
            for (i, card) in ordered.enumerated() {
                let window = ordered[max(0, i - ReviewQueue.contextSpacing)..<i]
                let recent = Set(window.flatMap(\.contextOrders))
                // With a single poem a violation is sometimes unavoidable at the
                // very end; check only that it is avoided while alternatives exist.
                if ordered.count - i > ReviewQueue.contextSpacing + 1 {
                    #expect(!recent.contains(card.lineOrder), "seed \(seed) position \(i)")
                }
            }
        }
    }
}

@Suite struct FirstLetterSessionTests {
    @Test func typingFlow() {
        var s = FirstLetterSession(tokens: Tokenizer.tokenize("Tyger Tyger, burning bright,"))
        #expect(s.wordCount == 4)
        #expect(s.type("t") == true)
        #expect(s.type(" ") == nil)
        #expect(s.type("T") == true)      // case-insensitive
        #expect(s.type("x") == false)     // reveals "burning"
        #expect(s.revealed == [2])
        #expect(s.type("b") == true)
        #expect(s.isComplete)
        #expect(s.errors == 1)
        #expect(s.accuracy == 0.75)
        #expect(s.type("z") == nil)
    }

    @Test func leadingApostropheWords() {
        var s = FirstLetterSession(tokens: Tokenizer.tokenize("'Tis the e'en"))
        #expect(s.type("t") == true)
        #expect(s.type("t") == true)
        #expect(s.type("e") == true)
        #expect(s.errors == 0)
    }
}

@Suite struct HintAndMaskTests {
    let line = CardLine(order: 0, stanzaIndex: 0, text: "  Should I compare thee, to a day?", isContext: false,
                        tokens: Tokenizer.tokenize("  Should I compare thee, to a day?"))

    @Test func progressiveHints() {
        var h = HintState()
        #expect(h.render(line) == "  ▁▁▁▁▁▁ ▁ ▁▁▁▁▁▁▁ ▁▁▁▁, ▁▁ ▁ ▁▁▁?")
        h.next(wordCount: 7)
        #expect(h.level == .nextLetter && h.hintsUsed == 1)
        #expect(h.render(line) == "  S▁▁▁▁▁ ▁ ▁▁▁▁▁▁▁ ▁▁▁▁, ▁▁ ▁ ▁▁▁?")
        h.next(wordCount: 7)
        #expect(h.level == .nextWord)
        #expect(h.render(line) == "  Should ▁ ▁▁▁▁▁▁▁ ▁▁▁▁, ▁▁ ▁ ▁▁▁?")
        h.next(wordCount: 7)
        #expect(h.level == .wholeLine)
        #expect(h.render(line) == line.text)
        #expect(h.maxGrade == .again)
    }

    @Test func firstLettersOpening() {
        let h = HintState.firstLettersOpening()
        #expect(h.render(line) == "  S I c t, t a d?")
        #expect(h.hintsUsed == 0)
    }

    @Test func maskKeepsIndentationAndPunctuation() {
        let text = "\tWi' bickering brattle!"
        let out = LineMask.render(text: text, tokens: Tokenizer.tokenize(text), style: .underscores) { $0 == 0 ? .full : .hidden }
        #expect(out == "\tWi' ▁▁▁▁▁▁▁▁▁ ▁▁▁▁▁▁▁!")
    }
}

@Suite @MainActor struct TransitionCardAndHandoffTests {
    @Test func cardContextAndTitle() throws {
        let poem = Poem.make(title: "The Tyger", author: nil, rawText: Fixture.tyger.text)
        let first = try #require(TransitionCard.make(poem: poem, targetOrder: 0))
        #expect(first.showsTitleAsContext)
        #expect(first.target.text == "Tyger Tyger, burning bright,")

        let card = try #require(TransitionCard.make(poem: poem, targetOrder: 4))
        #expect(card.contextOrders == [2, 3])
        #expect(card.hasStanzaBreak(before: card.target))
        #expect(!card.hasStanzaBreak(before: card.context[1]))

        let three = try #require(TransitionCard.make(poem: poem, targetOrder: 10, contextLines: 3))
        #expect(three.contextOrders == [7, 8, 9])
    }

    @Test func contextLinesAppearAsContext() throws {
        let poem = Poem.make(title: "", author: nil, rawText: Fixture.upHill.text)
        let card = try #require(TransitionCard.make(poem: poem, targetOrder: 10))
        #expect(card.context.map(\.order) == [8, 9])
        #expect(card.context[1].isContext)
    }

    @Test func handoffCreatesItemsForAskedLinesOnly() {
        let poem = Poem.make(title: "", author: nil, rawText: Fixture.upHill.text)
        let engine = ReviewEngine(scheduler: FSRSScheduler())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let created = Handoff.perform(poem: poem, engine: engine, seedGrades: [1: .easy, 2: .again], now: now)
        #expect(created.count == 16)
        #expect(poem.status == .reviewing)
        #expect(poem.item(forLine: 0) == nil)
        #expect(poem.item(forLine: 1)!.due > now)
        #expect(poem.item(forLine: 2)!.lapses == 0 && poem.item(forLine: 2)!.reps == 1)
        #expect(poem.item(forLine: 3)!.due == now)
        // Idempotent.
        #expect(Handoff.perform(poem: poem, engine: engine, now: now).isEmpty)
    }
}
