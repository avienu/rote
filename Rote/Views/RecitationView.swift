import RoteCore
import SwiftUI

/// Shows a span of lines at their cue rungs, takes one recitation (speech,
/// typed text or self-grade) and reports per-line results. Used by acquisition
/// windows, the stumble drill and consolidation.
struct RecitationView: View {
    struct Result {
        var lineResults: [Int: LineResult]
        var mode: InputMode
        var attempt: SpeechAttempt?
    }

    let poem: Poem
    /// Lines shown, in order; context lines render in full and are never asked.
    let lines: [CardLine]
    let rungs: [Int: LadderRung]
    /// Consolidation runs show the title only until the attempt is in.
    var hideLinesUntilDone = false
    @Binding var mode: InputMode
    let onApply: (Result) -> Void

    @State private var speech: SpeechController
    @State private var typed = ""
    @State private var attempt: SpeechAttempt?
    @State private var selfGraded = false
    @State private var selfGrades: [Int: Int] = [:]
    @State private var peeked = false
    @FocusState private var typingFocused: Bool

    private static let selfGradeAccuracy: [Double] = [1.0, 0.8, 0.5]

    init(poem: Poem, lines: [CardLine], rungs: [Int: LadderRung], hideLinesUntilDone: Bool = false,
         mode: Binding<InputMode>, onApply: @escaping (Result) -> Void) {
        self.poem = poem
        self.lines = lines
        self.rungs = rungs
        self.hideLinesUntilDone = hideLinesUntilDone
        self._mode = mode
        self.onApply = onApply
        let asked = lines.filter { !$0.isContext }.map { (order: $0.order, tokens: $0.tokens) }
        _speech = State(initialValue: SpeechController(lines: asked, locale: poem.locale, vocabulary: poem.vocabulary))
    }

    private var asked: [CardLine] { lines.filter { !$0.isContext } }
    private var done: Bool { attempt != nil || selfGraded }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if hideLinesUntilDone, !done {
                        Text(poem.title).font(.system(.title2, design: .serif)).italic().foregroundStyle(.secondary)
                        Text("Recite the whole poem from memory.").font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        linesBlock
                    }
                    if mode == .speech, !speech.transcript.isEmpty, attempt == nil {
                        Text(speech.transcript).font(.callout).foregroundStyle(.secondary).padding(.top, 12)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(24)
            }
            Divider()
            controls.padding(16).frame(maxWidth: .infinity)
        }
        .onChange(of: mode) { _, _ in reset() }
        .onAppear { if mode == .speech { Task { await speech.prepare() } } }
    }

    // MARK: Lines

    private var linesBlock: some View {
        var offset = 0
        return ForEach(lines, id: \.order) { line in
            let firstExpected = offset
            let _ = { if !line.isContext { offset += line.tokens.filter(\.isWord).count } }()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(line.order + 1)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
                if line.isContext {
                    Text(line.text).font(.system(.title3, design: .serif)).italic().foregroundStyle(.tertiary)
                } else if let attempt {
                    DiffLineView(line: line, attempt: attempt, firstExpectedIndex: firstExpected) { attemptToggle($0) }
                } else if done || peeked {
                    Text(line.text).font(.system(.title3, design: .serif))
                } else {
                    cue(for: line)
                }
                if done, !line.isContext, mode == .selfGrade {
                    Spacer()
                    Picker("", selection: Binding(get: { selfGrades[line.order] ?? 0 }, set: { selfGrades[line.order] = $0 })) {
                        Image(systemName: "checkmark").tag(0)
                        Image(systemName: "tilde").tag(1)
                        Image(systemName: "xmark").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 120)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private func cue(for line: CardLine) -> some View {
        let rung = rungs[line.order] ?? .full
        if rung == .blank {
            Rectangle().fill(.tertiary).frame(height: 1).padding(.top, 14)
        } else {
            Text(CueRenderer.render(line, rung: rung)).font(.system(.title3, design: .serif))
        }
    }

    private func attemptToggle(_ expectedIndex: Int) {
        attempt?.toggleCorrection(expectedIndex: expectedIndex)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            if !done {
                Picker("Mode", selection: $mode) {
                    Text("Speak").tag(InputMode.speech)
                    Text("Type").tag(InputMode.firstLetterTyping)
                    Text("Self-grade").tag(InputMode.selfGrade)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            }
            if done {
                HStack {
                    if let attempt {
                        Text(String(format: "%.0f%% · %d errors · %d extra", attempt.accuracy * 100, attempt.errors, attempt.alignment.insertions))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if peeked {
                        Text("Peeked: no rung steps down this time").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Try again") { reset() }.keyboardShortcut("r", modifiers: [])
                    Button("Apply") { apply() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            } else {
                switch mode {
                case .speech: speechControls
                case .firstLetterTyping: typingControls
                case .selfGrade:
                    HStack {
                        peekButton
                        Spacer()
                        Button("I've recited it") { selfGraded = true }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.space, modifiers: [])
                    }
                }
            }
        }
    }

    private var peekButton: some View {
        Button { peeked = true } label: { Label(peeked ? "Peeking" : "Peek", systemImage: "eye") }
            .disabled(peeked || hideLinesUntilDone)
            .keyboardShortcut("p", modifiers: [])
    }

    @ViewBuilder private var speechControls: some View {
        HStack(spacing: 12) {
            switch speech.status {
            case .unavailable(let message):
                Text(message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Type instead") { mode = .firstLetterTyping }
            case .preparing:
                ProgressView().controlSize(.small)
                Text("Preparing speech…").font(.caption).foregroundStyle(.secondary)
                Spacer()
            default:
                peekButton
                Spacer()
                Button {
                    speech.toggle()
                } label: {
                    Label(speech.isRecording ? "Stop" : "Record", systemImage: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(speech.isRecording ? .red : .accentColor)
                .disabled(speech.status == .idle)
                .keyboardShortcut("r", modifiers: [])
            }
        }
        .onChange(of: speech.status) { _, status in
            if status == .finished, let a = speech.attempt { attempt = a }
        }
    }

    @ViewBuilder private var typingControls: some View {
        VStack(spacing: 8) {
            TextEditor(text: $typed)
                .font(.system(.body, design: .serif))
                .frame(minHeight: 60, maxHeight: 140)
                .focused($typingFocused)
                .autocorrectionDisabled()
                .overlay(alignment: .topLeading) {
                    if typed.isEmpty {
                        Text("Type the lines from memory").foregroundStyle(.tertiary).padding(8).allowsHitTesting(false)
                    }
                }
            HStack {
                peekButton
                Spacer()
                Button("Check") {
                    attempt = SpeechAttempt(lines: asked.map { ($0.order, $0.tokens) }, transcript: typed, locale: poem.locale)
                }
                .buttonStyle(.borderedProminent)
                .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear { typingFocused = true }
    }

    private func apply() {
        var results: [Int: LineResult] = [:]
        if let attempt {
            for line in attempt.perLine() {
                results[line.lineOrder] = LineResult(accuracy: line.accuracy, hintUsed: peeked)
            }
        } else {
            for line in asked {
                let g = selfGrades[line.order] ?? 0
                results[line.order] = LineResult(accuracy: Self.selfGradeAccuracy[g], hintUsed: peeked)
            }
        }
        let mode: InputMode = attempt == nil ? .selfGrade : (self.mode == .speech ? .speech : .firstLetterTyping)
        onApply(Result(lineResults: results, mode: mode, attempt: attempt))
    }

    private func reset() {
        attempt = nil
        selfGraded = false
        selfGrades = [:]
        peeked = false
        typed = ""
        if mode == .speech { Task { await speech.prepare() } }
        if mode == .firstLetterTyping { typingFocused = true }
    }
}
