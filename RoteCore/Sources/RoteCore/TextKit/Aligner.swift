import Foundation

/// A word the user was expected to say, with its position in the poem.
public struct ExpectedWord: Hashable, Sendable {
    public var normalized: String
    public var lineOrder: Int
    /// Index into the line's `tokens` array (counting non-word tokens too).
    public var tokenIndex: Int

    public init(normalized: String, lineOrder: Int, tokenIndex: Int) {
        self.normalized = normalized
        self.lineOrder = lineOrder
        self.tokenIndex = tokenIndex
    }
}

public enum AlignmentOp: Hashable, Sendable {
    case match
    /// Correct via the equivalence table; shown in amber, not red.
    case equivalent
    case substitution
    case deletion
    /// Extra spoken word; charged to the span, not to any token.
    case insertion

    public var isError: Bool { self == .substitution || self == .deletion }
}

public struct AlignmentStep: Hashable, Sendable {
    public var op: AlignmentOp
    public var expectedIndex: Int?
    public var hypothesisIndex: Int?
}

/// Per-line view of an alignment, used for grading and the heat map.
public struct LineAlignment: Hashable, Sendable {
    public struct TokenOp: Hashable, Sendable {
        public var tokenIndex: Int
        public var op: AlignmentOp
        public var hypothesisIndex: Int?
    }

    public var lineOrder: Int
    public var wordCount: Int
    /// Substitutions + deletions.
    public var errors: Int
    public var insertions: Int
    public var tokenOps: [TokenOp]
    /// Index of the first hypothesis word aligned to this line, for hesitation checks.
    public var firstHypothesisIndex: Int?

    /// 1 − errors / wordCount. A line with no words scores 1.
    public var accuracy: Double {
        wordCount == 0 ? 1 : 1 - Double(errors) / Double(wordCount)
    }

    /// True when every word of the line was deleted.
    public var isSkipped: Bool {
        wordCount > 0 && errors == wordCount && tokenOps.allSatisfy { $0.op == .deletion }
    }
}

public struct Alignment: Hashable, Sendable {
    public var expected: [ExpectedWord]
    public var hypothesis: [String]
    public var steps: [AlignmentStep]

    public var wordCount: Int { expected.count }
    public var errors: Int { steps.filter { $0.op.isError }.count }
    public var insertions: Int { steps.filter { $0.op == .insertion }.count }
    public var accuracy: Double { wordCount == 0 ? 1 : 1 - Double(errors) / Double(wordCount) }

    /// Splits the ops by the expected tokens' line membership. Insertions attach
    /// to the line of the most recently consumed expected word (or the first line).
    public func perLine() -> [LineAlignment] {
        var order: [Int] = []
        var byLine: [Int: LineAlignment] = [:]
        for w in expected where byLine[w.lineOrder] == nil {
            order.append(w.lineOrder)
            byLine[w.lineOrder] = LineAlignment(lineOrder: w.lineOrder, wordCount: 0, errors: 0,
                                                insertions: 0, tokenOps: [], firstHypothesisIndex: nil)
        }
        var lastLine = order.first
        for step in steps {
            if let e = step.expectedIndex {
                let line = expected[e].lineOrder
                lastLine = line
                byLine[line]!.wordCount += 1
                if step.op.isError { byLine[line]!.errors += 1 }
                byLine[line]!.tokenOps.append(.init(tokenIndex: expected[e].tokenIndex, op: step.op,
                                                    hypothesisIndex: step.hypothesisIndex))
                if let h = step.hypothesisIndex, byLine[line]!.firstHypothesisIndex == nil {
                    byLine[line]!.firstHypothesisIndex = h
                }
            } else if let line = lastLine {
                byLine[line]!.insertions += 1
            }
        }
        return order.map { byLine[$0]! }
    }
}

/// Needleman–Wunsch word alignment with match 0, substitution 1, insertion 1,
/// deletion 1. Spans are at most a few hundred words, so O(n·m) is fine.
public enum Aligner {
    public static func align(expected: [ExpectedWord], hypothesis: [String], locale: String = "en-US") -> Alignment {
        let n = expected.count, m = hypothesis.count
        // dp[i][j] = cost of aligning expected[0..<i] with hypothesis[0..<j]
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let same = Equivalence.areEquivalent(expected[i - 1].normalized, hypothesis[j - 1], locale: locale)
                    let diag = dp[i - 1][j - 1] + (same ? 0 : 1)
                    dp[i][j] = min(diag, dp[i - 1][j] + 1, dp[i][j - 1] + 1)
                }
            }
        }
        // Backtrace, preferring diagonal, then deletion, then insertion.
        var steps: [AlignmentStep] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let e = expected[i - 1].normalized, h = hypothesis[j - 1]
                let exact = e == h
                let same = exact || Equivalence.areEquivalent(e, h, locale: locale)
                let diag = dp[i - 1][j - 1] + (same ? 0 : 1)
                if dp[i][j] == diag {
                    let op: AlignmentOp = exact ? .match : (same ? .equivalent : .substitution)
                    steps.append(.init(op: op, expectedIndex: i - 1, hypothesisIndex: j - 1))
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                steps.append(.init(op: .deletion, expectedIndex: i - 1, hypothesisIndex: nil))
                i -= 1
            } else {
                steps.append(.init(op: .insertion, expectedIndex: nil, hypothesisIndex: j - 1))
                j -= 1
            }
        }
        steps.reverse()
        return Alignment(expected: expected, hypothesis: hypothesis, steps: steps)
    }

    /// Builds the expected-word list for a span of tokenized lines.
    public static func expectedWords(lines: [(order: Int, tokens: [Token])]) -> [ExpectedWord] {
        lines.flatMap { line in
            line.tokens.enumerated().compactMap { idx, token in
                token.isWord ? ExpectedWord(normalized: token.normalized, lineOrder: line.order, tokenIndex: idx) : nil
            }
        }
    }

    /// Convenience: align a span of lines against a plain transcript string.
    public static func align(lines: [(order: Int, tokens: [Token])], transcript: String, locale: String = "en-US") -> Alignment {
        align(expected: expectedWords(lines: lines), hypothesis: Tokenizer.words(transcript, locale: locale), locale: locale)
    }
}
