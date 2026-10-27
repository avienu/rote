import RoteCore
import SwiftUI

/// One transition card: context lines, the target line at its cue level, the
/// input mode, hints and the grade bar. Keyboard: space reveals, 1–4 grade.
struct TransitionCardView: View {
    let poem: Poem
    let item: TransitionItem
    let card: TransitionCard
    @Binding var mode: InputMode
    let onGrade: (Grade, CardResult) -> Void

    @State private var revealed = false
    @State private var hint: HintState
    @State private var typing: FirstLetterSession
    @State private var typedText = ""
    @State private var startedAt = Date()
    @FocusState private var typingFocused: Bool

    init(poem: Poem, item: TransitionItem, card: TransitionCard, mode: Binding<InputMode>, onGrade: @escaping (Grade, CardResult) -> Void) {
        self.poem = poem
        self.item = item
        self.card = card
        self._mode = mode
        self.onGrade = onGrade
        _hint = State(initialValue: item.opensWithFirstLetters ? .firstLettersOpening() : HintState())
        _typing = State(initialValue: FirstLetterSession(tokens: card.target.tokens))
    }

    private var capAtGood: Bool { item.opensWithFirstLetters }
    private var maxGrade: Grade { GradeProposal.maxGrade(hint: hint.level, capAtGood: capAtGood) }
    private var typingDone: Bool { mode == .firstLetterTyping && typing.isComplete }
    private var showsGrades: Bool { revealed || typingDone }

    private var proposal: Grade? {
        guard typingDone else { return nil }
        return GradeProposal.forCard(accuracy: typing.accuracy, hint: hint.level, capAtGood: capAtGood)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(poem.title).font(.caption).foregroundStyle(.tertiary).padding(.bottom, 16)
                    contextBlock
                    targetBlock
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(24)
            }
            Divider()
            controls.padding(16)
        }
        .onChange(of: mode) { _, _ in resetForMode() }
        .onAppear { if mode == .firstLetterTyping { typingFocused = true } }
    }

    // MARK: Text

    @ViewBuilder private var contextBlock: some View {
        if card.showsTitleAsContext {
            Text(poem.title)
                .font(.system(.title3, design: .serif)).italic()
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        } else {
            ForEach(card.context, id: \.order) { line in
                if card.hasStanzaBreak(before: line) { Spacer().frame(height: 18) }
                Text(line.text)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(line.isContext ? .tertiary : .secondary)
                    .italic(line.isContext)
                    .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder private var targetBlock: some View {
        if card.hasStanzaBreak(before: card.target) { Spacer().frame(height: 18) }
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(card.target.order + 1)")
                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
            if showsGrades {
                MaskedLineText(line: card.target, reveal: { _ in .full }, errorWords: typing.revealed)
            } else if mode == .firstLetterTyping {
                MaskedLineText(line: card.target, reveal: typing.reveal(wordIndex:), errorWords: typing.revealed)
            } else if hint.level == .none, !item.opensWithFirstLetters {
                Rectangle().fill(.tertiary).frame(height: 1).padding(.top, 14)
            } else {
                Text(hint.render(card.target)).font(.system(.title3, design: .serif))
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            if !showsGrades {
                Picker("Mode", selection: $mode) {
                    Text("Self-grade").tag(InputMode.selfGrade)
                    Text("Type").tag(InputMode.firstLetterTyping)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
            }
            if showsGrades {
                gradeBar
            } else if mode == .firstLetterTyping {
                typingControls
            } else {
                HStack {
                    Button {
                        hint.next(wordCount: card.target.tokens.filter(\.isWord).count)
                    } label: { Label(hintLabel, systemImage: "lightbulb") }
                        .disabled(hint.level == .wholeLine)
                        .keyboardShortcut("h", modifiers: [])
                    Spacer()
                    Button("Reveal") { revealed = true }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.space, modifiers: [])
                }
            }
        }
    }

    private var hintLabel: String {
        switch hint.level {
        case .none: "Hint: first letter"
        case .nextLetter: "Hint: next word"
        case .nextWord: "Hint: whole line"
        case .wholeLine: "No more hints"
        }
    }

    @ViewBuilder private var typingControls: some View {
        HStack {
            TextField("Type the first letter of each word", text: $typedText)
                .textFieldStyle(.roundedBorder)
                .focused($typingFocused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .onChange(of: typedText) { old, new in
                    guard new.count > old.count else { return }
                    for ch in new.dropFirst(old.count) { typing.type(ch) }
                }
            Text("\(typing.position)/\(typing.wordCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var gradeBar: some View {
        HStack(spacing: 8) {
            if typingDone {
                Text(String(format: "%.0f%% · %d errors", typing.accuracy * 100, typing.errors))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(Grade.allCases, id: \.self) { grade in
                Button {
                    finish(grade)
                } label: {
                    Text(label(for: grade)).frame(minWidth: 64)
                }
                .buttonStyle(.bordered)
                .tint(grade == proposal ? .accentColor : nil)
                .disabled(grade.number > maxGrade.number)
                .keyboardShortcut(KeyEquivalent(Character(String(grade.number))), modifiers: [])
            }
        }
    }

    private func label(for grade: Grade) -> String {
        switch grade {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    private func finish(_ grade: Grade) {
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        let result = CardResult(mode: mode,
                                wordErrors: typingDone ? typing.errors : nil,
                                wordCount: typingDone ? typing.wordCount : nil,
                                elapsedMs: elapsed, hintsUsed: hint.hintsUsed)
        onGrade(Grade.min(grade, maxGrade), result)
    }

    private func resetForMode() {
        revealed = false
        typedText = ""
        typing = FirstLetterSession(tokens: card.target.tokens)
        if mode == .firstLetterTyping { typingFocused = true }
    }
}

/// A line with per-word reveal state and error coloring, built from its tokens
/// so indentation and punctuation are kept.
struct MaskedLineText: View {
    let line: CardLine
    let reveal: (Int) -> WordReveal
    var errorWords: Set<Int> = []

    var body: some View {
        text.font(.system(.title3, design: .serif))
    }

    private var text: Text {
        var result = Text("")
        var cursor = 0
        var wordIndex = 0
        let utf16 = line.text.utf16
        func slice(_ r: Range<Int>) -> String {
            let s = utf16.index(utf16.startIndex, offsetBy: r.lowerBound)
            let e = utf16.index(utf16.startIndex, offsetBy: r.upperBound)
            return String(utf16[s..<e]) ?? ""
        }
        for token in line.tokens {
            if token.range.lowerBound > cursor { result = result + Text(slice(cursor..<token.range.lowerBound)) }
            if token.isWord {
                let s = LineMask.render(word: token.surface, reveal: reveal(wordIndex), style: .underscores)
                var piece = Text(s)
                if errorWords.contains(wordIndex) { piece = piece.foregroundColor(.red) }
                result = result + piece
                wordIndex += 1
            } else {
                result = result + Text(token.surface)
            }
            cursor = token.range.upperBound
        }
        if cursor < utf16.count { result = result + Text(slice(cursor..<utf16.count)) }
        return result
    }
}
