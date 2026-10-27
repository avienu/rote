import Testing
@testable import RoteCore

@Suite struct AlignerTests {
    private func expected(_ s: String, line: Int = 0) -> [ExpectedWord] {
        Tokenizer.words(s).enumerated().map { ExpectedWord(normalized: $1, lineOrder: line, tokenIndex: $0) }
    }

    @Test func perfectMatch() {
        let a = Aligner.align(expected: expected("the quick brown fox"), hypothesis: ["the", "quick", "brown", "fox"])
        #expect(a.steps.map(\.op) == [.match, .match, .match, .match])
        #expect(a.errors == 0)
        #expect(a.accuracy == 1)
    }

    @Test func substitution() {
        let a = Aligner.align(expected: expected("the quick brown fox"), hypothesis: ["the", "quick", "red", "fox"])
        #expect(a.steps.map(\.op) == [.match, .match, .substitution, .match])
        #expect(a.errors == 1)
        #expect(a.steps[2].hypothesisIndex == 2)
    }

    @Test func deletion() {
        let a = Aligner.align(expected: expected("the quick brown fox"), hypothesis: ["the", "brown", "fox"])
        #expect(a.steps.map(\.op) == [.match, .deletion, .match, .match])
        #expect(a.steps[1].expectedIndex == 1)
        #expect(a.errors == 1)
    }

    @Test func insertionIsNotChargedToTokens() {
        let a = Aligner.align(expected: expected("the quick brown fox"), hypothesis: ["the", "um", "quick", "brown", "fox"])
        #expect(a.steps.map(\.op) == [.match, .insertion, .match, .match, .match])
        #expect(a.errors == 0)
        #expect(a.insertions == 1)
        #expect(a.accuracy == 1)
    }

    @Test func equivalentCountsCorrectButFlagged() {
        let a = Aligner.align(expected: expected("tell o'er the sad account"), hypothesis: ["tell", "over", "the", "sad", "account"])
        #expect(a.steps[1].op == .equivalent)
        #expect(a.errors == 0)
    }

    @Test func emptyHypothesisIsAllDeletions() {
        let a = Aligner.align(expected: expected("a b c"), hypothesis: [])
        #expect(a.steps.map(\.op) == [.deletion, .deletion, .deletion])
        #expect(a.accuracy == 0)
        #expect(a.perLine()[0].isSkipped)
    }

    @Test func skippedLineAttribution() {
        let lines = [(order: 0, tokens: Tokenizer.tokenize("alpha beta gamma")),
                     (order: 1, tokens: Tokenizer.tokenize("delta epsilon zeta")),
                     (order: 2, tokens: Tokenizer.tokenize("eta theta iota"))]
        let a = Aligner.align(lines: lines, transcript: "alpha beta gamma eta theta iota")
        let per = a.perLine()
        #expect(per.map(\.lineOrder) == [0, 1, 2])
        #expect(per[0].errors == 0)
        #expect(per[1].errors == 3)
        #expect(per[1].isSkipped)
        #expect(per[2].errors == 0)
        #expect(per[2].firstHypothesisIndex == 3)
    }

    @Test func wholePoemSplitByLine() {
        let lines = Fixture.tyger.tokenizedLines
        var spoken = lines.map { $0.tokens.filter(\.isWord).map(\.normalized).joined(separator: " ") }
        spoken[5] = "burnt the fire of thy eyes"          // one substitution on line 5
        spoken[10] = "and when thy heart began to um beat" // one insertion on line 10
        let a = Aligner.align(lines: lines, transcript: spoken.joined(separator: " "))
        let per = a.perLine()
        #expect(per.count == 24)
        #expect(per[5].errors == 1)
        #expect(per[5].wordCount == 6)
        #expect(per[10].errors == 0)
        #expect(per[10].insertions == 1)
        #expect(per.filter { $0.errors > 0 }.count == 1)
        #expect(a.wordCount == per.reduce(0) { $0 + $1.wordCount })
    }

    @Test func tokenOpsCarryTokenIndices() {
        let lines = [(order: 3, tokens: Tokenizer.tokenize("Tyger Tyger, burning bright,"))]
        let a = Aligner.align(lines: lines, transcript: "tiger tyger burning bright")
        let ops = a.perLine()[0].tokenOps
        #expect(ops.map(\.tokenIndex) == [0, 1, 3, 4])
        #expect(ops[0].op == .substitution)
    }
}
