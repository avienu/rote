import RoteCore
import SwiftData
import SwiftUI

/// Acquisition (§5): reading → windowing → sleep gate → consolidating → hand-off.
/// All rules live in `AcquisitionMachine`; this view persists state and rungs.
struct AcquisitionSessionView: View {
    @Bindable var poem: Poem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("desiredRetention") private var desiredRetention = FSRSScheduler.defaultRetention
    @AppStorage("defaultInputMode") private var defaultModeRaw = InputMode.selfGrade.rawValue

    @State private var state: AcquisitionState
    @State private var lines: [AcquisitionLine]
    @State private var mode: InputMode = .selfGrade
    @State private var sessionStart = Date()
    @State private var banner: String?
    @State private var attemptCounter = 0
    @State private var drill: [Int]?            // stumble-drill queue of line orders
    @State private var consolidationNote: String?
    @State private var timeUp = false

    init(poem: Poem) {
        self.poem = poem
        _state = State(initialValue: poem.acquisition ?? AcquisitionMachine.start())
        _lines = State(initialValue: poem.orderedLines.map { AcquisitionLine(order: $0.order, isContext: $0.isContext, rung: $0.ladderRung) })
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(poem.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Stop") { endSession() }.keyboardShortcut(.cancelAction)
                    }
                    ToolbarItem(placement: .principal) { progressLabel }
                }
                .safeAreaInset(edge: .top) {
                    if let banner {
                        Text(banner)
                            .font(.callout)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(.thinMaterial)
                            .onTapGesture { self.banner = nil }
                    }
                }
        }
        .onAppear {
            mode = InputMode(rawValue: defaultModeRaw) ?? .selfGrade
            AcquisitionMachine.openGateIfDue(&state, settings: poem.settings, now: Date())
            showFirstWindowHintIfNeeded()
            persist()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Date().timeIntervalSince(sessionStart) > AcquisitionMachine.sessionCap, state.phase == .windowing {
                    timeUp = true
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 560)
        #endif
    }

    @ViewBuilder private var progressLabel: some View {
        if state.phase == .windowing, drill == nil, let w = AcquisitionMachine.currentWindow(state: state, lines: lines) {
            Text("Window \(w.index + 1) of \(w.count) · size \(state.windowSize) · pass \(state.completedPasses + 1)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        } else if drill != nil {
            Text("Stumble drill").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Phases

    @ViewBuilder private var content: some View {
        if timeUp {
            ContentUnavailableView {
                Label("That's twenty minutes", systemImage: "moon.zzz")
            } description: {
                Text("Enough for one sitting. Your place is saved.")
            } actions: {
                Button("Done") { endSession() }.keyboardShortcut(.defaultAction)
            }
        } else if let drill, let first = drill.first {
            stumbleDrill(order: first)
        } else {
            switch state.phase {
            case .reading: reading
            case .windowing: windowing
            case .sleepGate: sleepGate
            case .consolidating: consolidating
            case .handedOff: handedOff
            }
        }
    }

    private var reading: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Read it through once, slowly.").font(.callout).foregroundStyle(.secondary)
                    PoemTextView(poem: poem)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("I've read it") {
                    AcquisitionMachine.finishReading(&state)
                    showFirstWindowHintIfNeeded()
                    persist()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    @ViewBuilder private var windowing: some View {
        if let window = AcquisitionMachine.currentWindow(state: state, lines: lines) {
            RecitationView(poem: poem, lines: cardLines(window.orders), rungs: rungMap, mode: $mode) { result in
                applyWindow(window, result: result)
            }
            .id("\(window.index)-\(state.windowSize)-\(attemptCounter)")
        } else {
            ContentUnavailableView("Nothing to learn", systemImage: "text.quote", description: Text("This poem has no asked lines."))
        }
    }

    private var sleepGate: some View {
        ContentUnavailableView {
            Label("Come back after you've slept", systemImage: "moon.stars")
        } description: {
            if let opens = state.sleepGateOpensAt {
                Text("Sleep consolidates what you just learned. This poem opens again \(opens.formatted(date: .abbreviated, time: .shortened)).")
            }
        } actions: {
            Button("Done") { endSession() }.keyboardShortcut(.defaultAction)
            if !poem.settings.sleepGateEnabled {
                Button("Skip gate (testing)") {
                    AcquisitionMachine.openGateIfDue(&state, settings: poem.settings, now: Date())
                    persist()
                }
            }
        }
    }

    @ViewBuilder private var consolidating: some View {
        let asked = cardLines(lines.filter { !$0.isContext }.map(\.order))
        VStack(spacing: 0) {
            if let note = consolidationNote {
                Text(note).font(.callout).padding(12).frame(maxWidth: .infinity).background(.thinMaterial)
            }
            RecitationView(poem: poem, lines: asked, rungs: [:], hideLinesUntilDone: true, mode: $mode) { result in
                applyConsolidation(result)
            }
            .id("consolidation-\(state.consolidationPasses.count)-\(attemptCounter)")
        }
    }

    private var handedOff: some View {
        ContentUnavailableView {
            Label("Ready for review", systemImage: "checkmark.seal")
        } description: {
            Text("Every line now has its own schedule. Lines you found hard come back sooner.")
        } actions: {
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }

    private func stumbleDrill(order: Int) -> some View {
        RecitationView(poem: poem, lines: cardLines([order]), rungs: [order: .blank], mode: $mode) { result in
            let acc = result.lineResults[order]?.accuracy ?? 0
            if acc >= AcquisitionMachine.stumbleThreshold {
                drill?.removeFirst()
                if drill?.isEmpty == true { drill = nil; banner = "Drill done. Recite again after a break of at least four hours." }
            } else {
                banner = "Once more on line \(order + 1)."
            }
            attemptCounter += 1
        }
        .id("drill-\(order)-\(attemptCounter)")
    }

    /// One-time hint on the very first window of a poem; the banner is tap-to-dismiss.
    private func showFirstWindowHintIfNeeded() {
        guard state.phase == .windowing, state.windowSize == 1, state.cursor == 0, state.completedPasses == 0, banner == nil else { return }
        banner = "Look away and say the shown lines from memory, then check. Cues fade as you get them right. Tap to dismiss."
    }

    // MARK: Actions

    private func applyWindow(_ window: AcquisitionWindow, result: RecitationView.Result) {
        let outcome = AcquisitionMachine.apply(window: window, results: result.lineResults, state: &state, lines: &lines,
                                               settings: poem.settings, now: Date())
        switch outcome {
        case .repeatWindow: banner = "Not yet. Same window again."
        case .nextWindow: banner = nil
        case .passComplete(let size): banner = "Whole poem passed. Windows of \(size) now."
        case .sleepGate: banner = nil
        }
        attemptCounter += 1
        persist()
    }

    private func applyConsolidation(_ result: RecitationView.Result) {
        let accs = result.lineResults.mapValues(\.accuracy)
        let overall = result.attempt?.accuracy ?? (accs.isEmpty ? 0 : accs.values.reduce(0, +) / Double(accs.count))
        let outcome = AcquisitionMachine.recordConsolidation(&state, accuracy: overall, lineAccuracy: accs, now: Date())
        switch outcome {
        case .belowThreshold(let acc, let weak):
            consolidationNote = String(format: "%.0f%% — needs 85%%. Weak lines: %@", acc * 100, weak.map { "\($0 + 1)" }.joined(separator: ", "))
            if !weak.isEmpty { drill = weak }
        case .tooSoon(let next):
            consolidationNote = "Second recitation must be a separate session, at least four hours later (after \(next.formatted(date: .omitted, time: .shortened)))."
        case .firstPassDone(let weak):
            state.stumbleDrillOffered = true
            consolidationNote = weak.isEmpty ? "First pass done. Recite once more after a break of at least four hours."
                : "First pass done. Drill lines \(weak.map { "\($0 + 1)" }.joined(separator: ", ")), then recite again after four hours."
            if !weak.isEmpty { drill = weak }
        case .readyForHandoff(let seeds):
            let engine = ReviewEngine(scheduler: FSRSScheduler(desiredRetention: poem.settings.desiredRetention ?? desiredRetention))
            Handoff.perform(poem: poem, engine: engine, seedGrades: seeds)
        }
        attemptCounter += 1
        persist()
    }

    private func endSession() {
        AcquisitionMachine.endSession(&state, now: Date())
        persist()
        dismiss()
    }

    private func persist() {
        poem.acquisition = state
        for l in lines { poem.line(order: l.order)?.ladderRung = l.rung }
        if poem.status == .draft { poem.status = .acquiring }
        poem.updatedAt = Date()
        try? context.save()
    }

    private var rungMap: [Int: LadderRung] {
        Dictionary(uniqueKeysWithValues: lines.map { ($0.order, $0.rung) })
    }

    private func cardLines(_ orders: [Int]) -> [CardLine] {
        orders.compactMap { order in
            poem.line(order: order).map {
                CardLine(order: $0.order, stanzaIndex: $0.stanza?.order ?? 0, text: $0.text, isContext: $0.isContext, tokens: $0.tokens)
            }
        }
    }
}
