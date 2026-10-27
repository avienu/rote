import Foundation

/// Plays back a canned transcript word by word. For tests, previews and
/// development runs without a microphone.
public actor FakeSpeechEngine: SpeechEngine {
    public var transcript: String
    public var wordDuration: TimeInterval
    public private(set) var prepared = false
    public private(set) var vocabulary: [String] = []
    private var timings: [WordTiming] = []

    public init(transcript: String, wordDuration: TimeInterval = 0.3) {
        self.transcript = transcript
        self.wordDuration = wordDuration
    }

    public func prepare(locale: Locale) async throws {
        prepared = true
    }

    public func setVocabulary(_ words: [String]) async {
        vocabulary = words
    }

    public func start() async throws -> AsyncStream<SpeechUpdate> {
        guard prepared else { throw SpeechEngineError.notPrepared }
        let words = transcript.split(separator: " ").map(String.init)
        let duration = wordDuration
        var all: [WordTiming] = []
        for (i, w) in words.enumerated() {
            all.append(WordTiming(word: w, start: Double(i) * duration, end: Double(i + 1) * duration))
        }
        timings = all
        return AsyncStream { continuation in
            var soFar: [String] = []
            for (i, w) in words.enumerated() {
                soFar.append(w)
                continuation.yield(SpeechUpdate(text: soFar.joined(separator: " "), isFinal: i == words.count - 1,
                                                timings: Array(all.prefix(i + 1))))
            }
            continuation.finish()
        }
    }

    public func stop() async throws -> SpeechResult {
        SpeechResult(transcript: transcript, timings: timings)
    }
}
