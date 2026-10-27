import Foundation
import Testing
@testable import RoteCore

@Suite struct SpeechAttemptTests {
    let lines = [(order: 0, tokens: Tokenizer.tokenize("Tyger Tyger, burning bright,")),
                 (order: 1, tokens: Tokenizer.tokenize("In the forests of the night;"))]

    @Test func alignsTranscriptAndProposes() {
        let a = SpeechAttempt(lines: lines, transcript: "tiger tyger burning bright in the forest of the night")
        #expect(a.wordCount == 10)
        #expect(a.errors == 2)
        #expect(a.accuracy == 0.8)
        #expect(GradeProposal.forCard(accuracy: a.accuracy) == .hard)
        #expect(a.perLine().map(\.errors) == [1, 1])
    }

    @Test func correctionsRegrade() {
        var a = SpeechAttempt(lines: lines, transcript: "tiger tyger burning bright in the forests of the night")
        #expect(a.op(expectedIndex: 0) == .substitution)
        a.toggleCorrection(expectedIndex: 0)
        #expect(a.op(expectedIndex: 0) == .match)
        #expect(a.errors == 0)
        #expect(a.corrections == [0])
        a.toggleCorrection(expectedIndex: 1)       // was a match: ignored
        #expect(a.corrections == [0])
        a.toggleCorrection(expectedIndex: 0)       // undo
        #expect(a.errors == 1)
        #expect(a.rawAlignment.errors == 1)        // raw alignment is never mutated
    }

    @Test func timingsDriveHypothesisAndPauses() {
        var t: [WordTiming] = []
        let words = ["Tyger", "Tyger", "burning", "bright", "in", "the", "forests", "of", "the", "night"]
        var clock = 0.0
        for (i, w) in words.enumerated() {
            if i == 4 { clock += 3.0 }     // long pause before line 1
            t.append(WordTiming(word: w, start: clock, end: clock + 0.3))
            clock += 0.35
        }
        let a = SpeechAttempt(lines: lines, transcript: words.joined(separator: " "), timings: t)
        #expect(a.hypothesis.count == 10)
        #expect(a.errors == 0)
        #expect(a.pauseBefore(lineOrder: 0) == nil)
        #expect(abs((a.pauseBefore(lineOrder: 1) ?? 0) - 3.05) < 0.001)
        #expect(a.hesitated(before: 1))
        #expect(!a.hesitated(before: 0))
    }

    @Test func timedWordMayTokenizeIntoSeveral() {
        let t = [WordTiming(word: "well-nigh,", start: 0, end: 0.5), WordTiming(word: "o'er", start: 0.6, end: 0.9)]
        let a = SpeechAttempt(lines: [(0, Tokenizer.tokenize("well-nigh o'er"))], transcript: "well-nigh, o'er", timings: t)
        #expect(a.hypothesis == ["wellnigh", "o'er"])
        #expect(a.errors == 0)
    }
}

@Suite struct FakeSpeechEngineTests {
    @Test func streamsPartialThenFinal() async throws {
        let engine = FakeSpeechEngine(transcript: "in the forests of the night")
        await #expect(throws: SpeechEngineError.notPrepared) { _ = try await engine.start() }
        try await engine.prepare(locale: Locale(identifier: "en-US"))
        await engine.setVocabulary(["forests"])
        var updates: [SpeechUpdate] = []
        for await u in try await engine.start() { updates.append(u) }
        #expect(updates.count == 6)
        #expect(updates.first?.text == "in")
        #expect(updates.last?.isFinal == true)
        #expect(updates.dropLast().allSatisfy { !$0.isFinal })
        let result = try await engine.stop()
        #expect(result.transcript == "in the forests of the night")
        #expect(result.timings.count == 6)
        #expect(result.timings[4].start == 1.2)
    }
}
