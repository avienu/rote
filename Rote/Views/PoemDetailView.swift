import RoteCore
import SwiftData
import SwiftUI

/// Poem text with status and editing. Heat map and stats arrive in later milestones.
struct PoemDetailView: View {
    @Bindable var poem: Poem
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var reviewing = false
    @State private var learning = false
    @State private var drilling = false
    @State private var showingSettings = false
    @State private var selectedLine: Int?
    @AppStorage("desiredRetention") private var desiredRetention = FSRSScheduler.defaultRetention

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                learnBox
                reviewBox
                if poem.status == .reviewing {
                    statsBox
                    HeatMapView(poem: poem, stats: lineStats, selectedLine: $selectedLine)
                } else {
                    PoemTextView(poem: poem)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle(poem.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    .keyboardShortcut("e", modifiers: .command)
            }
            ToolbarItem {
                Menu {
                    Button("Poem settings…") { showingSettings = true }
                    Divider()
                    if poem.status == .draft {
                        Button("Review now (skip learning)") { skipToReview() }
                    }
                    if poem.status == .retired {
                        Button("Unretire") { poem.status = .draft }
                    } else {
                        Button("Retire", role: .destructive) { poem.status = .retired }
                    }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editing) { PoemEditorView(poem: poem) }
        .sheet(isPresented: $reviewing) { ReviewSessionView(poems: [poem]) }
        .sheet(isPresented: $learning) { AcquisitionSessionView(poem: poem) }
        .sheet(isPresented: $showingSettings) { PoemSettingsView(poem: poem) }
        .sheet(isPresented: $drilling) {
            ReviewSessionView(poems: [poem], drillItems: HeatMap.drillLines(lineStats).compactMap { poem.item(forLine: $0) })
        }
        .popover(item: Binding(get: { selectedLine.flatMap { o in lineStats.first { $0.lineOrder == o } } },
                               set: { selectedLine = $0?.lineOrder })) { stat in
            LineDetailView(poem: poem, stat: stat)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["ROTE_AUTO_LEARN"] != nil, poem.status == .acquiring { learning = true }
        }
        #endif
    }

    @ViewBuilder private var learnBox: some View {
        let now = Date()
        if poem.status == .draft {
            Button { startLearning() } label: { Label("Start learning", systemImage: "graduationcap") }
                .buttonStyle(.borderedProminent)
        } else if poem.status == .acquiring, let acq = poem.acquisition {
            HStack(spacing: 16) {
                let gated = AcquisitionMachine.isGated(acq, settings: poem.settings, now: now)
                Button { learning = true } label: { Label("Continue learning", systemImage: "graduationcap") }
                    .buttonStyle(.borderedProminent)
                    .disabled(gated)
                if gated, let opens = acq.sleepGateOpensAt {
                    Text("Sleeping. Opens \(opens.formatted(.relative(presentation: .named))).").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(phaseLabel(acq)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func phaseLabel(_ acq: AcquisitionState) -> String {
        switch acq.phase {
        case .reading: "Reading"
        case .windowing: "Windows of \(acq.windowSize), pass \(acq.completedPasses + 1)"
        case .sleepGate: "Sleep gate"
        case .consolidating: "Consolidating: \(acq.consolidationPasses.count) of \(AcquisitionMachine.consolidationPassesRequired) recitations"
        case .handedOff: "Handed off"
        }
    }

    private func startLearning() {
        poem.acquisition = AcquisitionMachine.start()
        poem.status = .acquiring
        poem.updatedAt = Date()
        try? context.save()
        learning = true
    }

    private var engine: ReviewEngine<FSRSScheduler> {
        ReviewEngine(scheduler: FSRSScheduler(desiredRetention: poem.settings.desiredRetention ?? desiredRetention))
    }

    private var lineStats: [LineStats] {
        HeatMap.lineStats(poem: poem, engine: engine, now: Date())
    }

    @ViewBuilder private var statsBox: some View {
        let stats = lineStats
        let weak = HeatMap.drillLines(stats)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                if let forecast = HeatMap.retentionForecast(stats) {
                    Label(String(format: "%.0f%% retention forecast", forecast * 100), systemImage: "brain")
                }
                Button {
                    drilling = true
                } label: {
                    Label(weak.isEmpty ? "No weak spots" : "Drill \(weak.count) weak \(weak.count == 1 ? "line" : "lines")", systemImage: "scope")
                }
                .disabled(weak.isEmpty)
            }
            .font(.callout)
            let weakest = HeatMap.weakestLines(stats)
            if !weakest.isEmpty {
                Text("Weakest: " + weakest.map { String(format: "%d (%.0f%%)", $0.lineOrder + 1, $0.retrievability * 100) }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Words tinted by error rate. Gutter bar = stability; red when recall is under 70%. Tap a line for its history.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func skipToReview() {
        Handoff.perform(poem: poem, engine: ReviewEngine(scheduler: FSRSScheduler(desiredRetention: poem.settings.desiredRetention ?? desiredRetention)))
        try? context.save()
    }

    @ViewBuilder private var reviewBox: some View {
        if poem.status == .reviewing {
            let now = Date()
            let dueCards = poem.dueItems(now: now).count
            let dueRuns = RunScheduling.dueRuns(poem: poem, now: now).count
            let due = dueCards + dueRuns
            let next = ((poem.items ?? []).map(\.due) + (poem.runItems ?? []).map(\.due)).min()
            let nextRun = (poem.runItems ?? []).map(\.due).min()
            HStack(spacing: 16) {
                Button {
                    reviewing = true
                } label: {
                    Label(due > 0 ? "Review \(due) due" : "Nothing due", systemImage: "rectangle.stack")
                }
                .buttonStyle(.borderedProminent)
                .disabled(due == 0)
                VStack(alignment: .leading, spacing: 2) {
                    if dueRuns > 0 {
                        Text("\(dueCards) lines, \(dueRuns) runs")
                    } else if due == 0, let next {
                        Text("Next due \(next.formatted(.relative(presentation: .named)))")
                    }
                    if let nextRun, nextRun > now {
                        Text("Next run \(nextRun.formatted(.relative(presentation: .named)))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let author = poem.author, !author.isEmpty {
                Text(author).font(.title3).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(poem.status.rawValue.capitalized)
                Text("^[\(poem.askedLines.count) line](inflect: true), ^[\(poem.orderedStanzas.count) stanza](inflect: true)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Renders the stored lines exactly, with stanza spacing. Context lines dimmed.
struct PoemTextView: View {
    let poem: Poem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(poem.orderedStanzas) { stanza in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(stanza.orderedLines) { line in
                        Text(line.text)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(line.isContext ? .secondary : .primary)
                            .italic(line.isContext)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}
