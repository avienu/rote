import RoteCore
import SwiftData
import SwiftUI

/// A run (§6.4): title only, full recitation of a stanza or the whole poem,
/// then the per-line result with the propagated grades. Applied on "Done".
struct RunView: View {
    let poem: Poem
    let run: RunItem
    @Binding var mode: InputMode
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @AppStorage("desiredRetention") private var desiredRetention = FSRSScheduler.defaultRetention
    @State private var report: PropagationReport?
    @State private var attempt: SpeechAttempt?

    private var orders: [Int] { RunScheduling.askedOrders(poem: poem, scope: run.scope) }
    private var scopeLabel: String {
        switch run.scope {
        case .wholePoem: "Whole poem"
        case .stanza(let o): "Stanza \(o + 1)"
        }
    }

    var body: some View {
        if let report, let attempt {
            summary(report, attempt)
        } else {
            VStack(spacing: 0) {
                Text(scopeLabel).font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                RecitationView(poem: poem, lines: cardLines, rungs: [:], hideLinesUntilDone: true, allowSelfGrade: false, mode: $mode) { result in
                    guard let a = result.attempt else { return }
                    let engine = ReviewEngine(scheduler: FSRSScheduler(desiredRetention: poem.settings.desiredRetention ?? desiredRetention))
                    let source: ReviewSource = run.scope == .wholePoem ? .fullRecitation : .stanzaRun
                    report = Propagation.apply(attempt: a, to: poem, engine: engine, source: source, mode: result.mode)
                    attempt = a
                    RunScheduling.complete(run: run, poem: poem, now: Date())
                    try? context.save()
                }
            }
        }
    }

    private func summary(_ report: PropagationReport, _ attempt: SpeechAttempt) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(format: "%@ · %.0f%% overall · %d lines updated", scopeLabel, report.overallAccuracy * 100, report.grades.count))
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(report.grades, id: \.lineOrder) { g in
                        if let line = cardLines.first(where: { $0.order == g.lineOrder }) {
                            let diff = DiffLineView(line: line, attempt: attempt, firstExpectedIndex: firstExpected(for: g.lineOrder)) { _ in }
                            let chip = gradeChip(g, capped: report.cappedLines.contains(g.lineOrder))
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(g.lineOrder + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 28, alignment: .trailing)
                                #if os(iOS)
                                VStack(alignment: .leading, spacing: 4) { diff; chip }
                                #else
                                diff
                                Spacer(minLength: 8)
                                chip
                                #endif
                            }
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                Text("Grades applied to every line. Skipped lines count as Again; the line after a skip is capped at Hard.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { onDone() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    private func gradeChip(_ g: PropagatedGrade, capped: Bool) -> some View {
        HStack(spacing: 4) {
            Text(String(format: "%.0f%%", g.accuracy * 100)).monospacedDigit()
            Text(g.grade.rawValue.capitalized).bold()
            if g.reasons.contains(.hesitation) { Image(systemName: "pause.circle") }
            if g.reasons.contains(.skipped) { Image(systemName: "arrow.turn.down.right") }
            if capped { Image(systemName: "shield") }
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color(g.grade).opacity(0.15), in: Capsule())
    }

    private func color(_ grade: Grade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    private var cardLines: [CardLine] {
        orders.compactMap { order in
            poem.line(order: order).map { CardLine(order: $0.order, stanzaIndex: $0.stanza?.order ?? 0, text: $0.text, isContext: $0.isContext, tokens: $0.tokens) }
        }
    }

    private func firstExpected(for order: Int) -> Int {
        var offset = 0
        for line in cardLines {
            if line.order == order { return offset }
            offset += line.tokens.filter(\.isWord).count
        }
        return offset
    }
}
