import Foundation

/// A recited span aligned against its lines, with the user's corrections of
/// misheard words. Grades are proposed from `accuracy`, never applied automatically.
public struct SpeechAttempt: Hashable, Sendable {
    public static let hesitationThreshold: TimeInterval = 2.5

    public let transcript: String
    /// Hypothesis words in order, each with its timing when the engine gave one.
    public let hypothesisTimings: [WordTiming?]
    public let rawAlignment: Alignment
    /// Expected-word indices the user flipped to "I actually said this".
    public private(set) var corrections: Set<Int> = []

    public init(lines: [(order: Int, tokens: [Token])], transcript: String, timings: [WordTiming] = [], locale: String = "en-US") {
        self.transcript = transcript
        var words: [String] = []
        var timingList: [WordTiming?] = []
        if timings.isEmpty {
            words = Tokenizer.words(transcript, locale: locale)
            timingList = Array(repeating: nil, count: words.count)
        } else {
            // Timings come per recognized word; one may tokenize into several.
            for t in timings {
                for w in Tokenizer.words(t.word, locale: locale) {
                    words.append(w)
                    timingList.append(t)
                }
            }
        }
        hypothesisTimings = timingList
        rawAlignment = Aligner.align(expected: Aligner.expectedWords(lines: lines), hypothesis: words, locale: locale)
    }

    public var hypothesis: [String] { rawAlignment.hypothesis }

    /// Alignment with corrections applied: corrected errors become matches.
    public var alignment: Alignment {
        var a = rawAlignment
        for i in a.steps.indices {
            if let e = a.steps[i].expectedIndex, corrections.contains(e), a.steps[i].op.isError {
                a.steps[i].op = .match
            }
        }
        return a
    }

    public var wordCount: Int { alignment.wordCount }
    public var errors: Int { alignment.errors }
    public var accuracy: Double { alignment.accuracy }
    public func perLine() -> [LineAlignment] { alignment.perLine() }

    /// Flips a misheard word to correct, or undoes that. Only errors can be corrected.
    public mutating func toggleCorrection(expectedIndex: Int) {
        guard rawAlignment.steps.contains(where: { $0.expectedIndex == expectedIndex && $0.op.isError }) else { return }
        if corrections.contains(expectedIndex) { corrections.remove(expectedIndex) } else { corrections.insert(expectedIndex) }
    }

    public var isCorrected: (Int) -> Bool { { self.corrections.contains($0) } }

    /// Op for an expected word after corrections, by expected index.
    public func op(expectedIndex: Int) -> AlignmentOp? {
        alignment.steps.first { $0.expectedIndex == expectedIndex }?.op
    }

    /// Silence before the first spoken word of a line, when timings exist and a
    /// word preceded it. Nil for the first spoken word or without timings.
    public func pauseBefore(lineOrder: Int) -> TimeInterval? {
        guard let line = perLine().first(where: { $0.lineOrder == lineOrder }),
              let h = line.firstHypothesisIndex, h > 0,
              let current = hypothesisTimings[h], let previous = hypothesisTimings[h - 1]
        else { return nil }
        return max(0, current.start - previous.end)
    }

    /// §7.3: a pause over the threshold right before a line caps it at `.hard`.
    public func hesitated(before lineOrder: Int, threshold: TimeInterval = SpeechAttempt.hesitationThreshold) -> Bool {
        (pauseBefore(lineOrder: lineOrder) ?? 0) > threshold
    }
}
