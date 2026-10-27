import RoteCore
import SwiftUI

/// Drives one recording on a card: prepare → record → stop → aligned attempt.
/// Owns the engine so views stay declarative.
@MainActor @Observable
final class SpeechController {
    enum Status: Equatable {
        case idle, preparing, ready, recording, finished
        case unavailable(String)
    }

    private(set) var status: Status = .idle
    private(set) var transcript = ""
    private(set) var attempt: SpeechAttempt?
    private(set) var startedAt: Date?

    private let engine: any SpeechEngine
    private let lines: [(order: Int, tokens: [Token])]
    private let locale: String
    private let vocabulary: [String]
    private var streamTask: Task<Void, Never>?

    init(lines: [(order: Int, tokens: [Token])], locale: String, vocabulary: [String], engine: (any SpeechEngine)? = nil) {
        self.lines = lines
        self.locale = locale
        self.vocabulary = vocabulary
        self.engine = engine ?? Self.defaultEngine(for: lines)
    }

    var isRecording: Bool { status == .recording }
    var canRecord: Bool { status == .ready || status == .finished }

    func prepare() async {
        guard status == .idle else { return }
        status = .preparing
        do {
            try await engine.prepare(locale: Locale(identifier: locale))
            await engine.setVocabulary(vocabulary)
            status = .ready
        } catch let error as SpeechEngineError {
            status = .unavailable(Self.message(for: error))
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    func toggle() {
        if isRecording { Task { await stop() } } else { Task { await record() } }
    }

    func record() async {
        guard canRecord else { return }
        transcript = ""
        attempt = nil
        status = .recording
        startedAt = Date()
        do {
            let stream = try await engine.start()
            streamTask = Task { [weak self] in
                for await update in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.transcript = update.text
                }
                // The engine ended the stream on its own (fake engine): wrap up.
                if let self, self.status == .recording { await self.stop() }
            }
        } catch let error as SpeechEngineError {
            status = .unavailable(Self.message(for: error))
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    func stop() async {
        guard status == .recording else { return }
        streamTask?.cancel()
        streamTask = nil
        do {
            let result = try await engine.stop()
            transcript = result.transcript
            attempt = SpeechAttempt(lines: lines, transcript: result.transcript, timings: result.timings, locale: locale)
            status = .finished
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    func toggleCorrection(expectedIndex: Int) {
        attempt?.toggleCorrection(expectedIndex: expectedIndex)
    }

    var elapsedMs: Int { startedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0 }

    static func message(for error: SpeechEngineError) -> String {
        switch error {
        case .localeUnsupported(let id): "Speech recognition isn't available for \(id). Use typing or self-grade."
        case .assetsUnavailable(let id): "Speech assets for \(id) can't be installed on this device."
        case .microphoneDenied: "Microphone access was denied. Enable it in System Settings."
        case .notPrepared: "Speech engine not ready."
        case .audioSetupFailed(let why): "Audio input failed: \(why)."
        }
    }

    /// The real engine, or a canned one when `ROTE_FAKE_TRANSCRIPT` is set in
    /// Debug builds ("auto" recites the target with one wrong word).
    private static func defaultEngine(for lines: [(order: Int, tokens: [Token])]) -> any SpeechEngine {
        #if DEBUG
        if let fake = ProcessInfo.processInfo.environment["ROTE_FAKE_TRANSCRIPT"] {
            if fake == "auto" {
                var words = lines.flatMap { $0.tokens.filter(\.isWord).map(\.surface) }
                if words.count > 2 { words[2] = "something" }
                if words.count > 5 { words.insert("um", at: 5) }
                return FakeSpeechEngine(transcript: words.joined(separator: " "))
            }
            return FakeSpeechEngine(transcript: fake)
        }
        #endif
        return SpeechAnalyzerEngine()
    }
}
