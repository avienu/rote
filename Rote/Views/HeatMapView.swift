import RoteCore
import SwiftData
import SwiftUI

/// The poem with every word tinted by its error rate and a left gutter bar for
/// transition stability. Tap a line for its history.
struct HeatMapView: View {
    let poem: Poem
    let stats: [LineStats]
    @Binding var selectedLine: Int?

    private var byOrder: [Int: LineStats] { Dictionary(uniqueKeysWithValues: stats.map { ($0.lineOrder, $0) }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(poem.orderedStanzas) { stanza in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(stanza.orderedLines) { line in
                        row(line)
                    }
                }
            }
        }
    }

    private func row(_ line: Line) -> some View {
        let stat = byOrder[line.order]
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(stat.map { $0.retrievability < HeatMap.drillRetrievability ? Color.red : Color.accentColor } ?? Color.clear)
                .frame(width: 3, height: 4 + 16 * (stat.map { HeatMap.stabilityFraction($0, among: stats) } ?? 0))
                .offset(y: -2)
            Text(attributed(line, stat: stat))
                .font(.system(.body, design: .serif))
                .foregroundStyle(line.isContext ? .secondary : .primary)
                .italic(line.isContext)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !line.isContext { selectedLine = line.order } }
        .background(selectedLine == line.order ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private func attributed(_ line: Line, stat: LineStats?) -> AttributedString {
        var result = AttributedString(line.text)
        guard let stat else { return result }
        for (index, token) in line.tokens.enumerated() where token.isWord {
            guard let level = stat.heat[index], level != .none,
                  let start = result.index(result.startIndex, offsetByCharacters: 0) as AttributedString.Index?,
                  let (lo, hi) = Self.range(in: line.text, utf16: token.range)
            else { continue }
            _ = start
            let s = result.index(result.startIndex, offsetByCharacters: lo)
            let e = result.index(result.startIndex, offsetByCharacters: hi)
            result[s..<e].backgroundColor = Self.color(level)
        }
        return result
    }

    /// UTF-16 token range → character offsets.
    private static func range(in text: String, utf16: Range<Int>) -> (Int, Int)? {
        let utf16View = text.utf16
        guard let s = utf16View.index(utf16View.startIndex, offsetBy: utf16.lowerBound, limitedBy: utf16View.endIndex),
              let e = utf16View.index(utf16View.startIndex, offsetBy: utf16.upperBound, limitedBy: utf16View.endIndex)
        else { return nil }
        return (text.distance(from: text.startIndex, to: s), text.distance(from: text.startIndex, to: e))
    }

    static func color(_ level: HeatLevel) -> Color {
        switch level {
        case .none: .clear
        case .low: .red.opacity(0.15)
        case .mid: .red.opacity(0.35)
        case .high: .red.opacity(0.6)
        }
    }
}

/// History and schedule for one line.
struct LineDetailView: View {
    let poem: Poem
    let stat: LineStats

    private var logs: [ReviewLog] {
        (poem.item(forLine: stat.lineOrder)?.logs ?? []).sorted { $0.reviewedAt > $1.reviewedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let line = poem.line(order: stat.lineOrder) {
                Text(line.text).font(.system(.title3, design: .serif))
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow { Text("Recall now").foregroundStyle(.secondary); Text(String(format: "%.0f%%", stat.retrievability * 100)) }
                GridRow { Text("Stability").foregroundStyle(.secondary); Text(String(format: "%.1f days", stat.stability)) }
                GridRow { Text("Difficulty").foregroundStyle(.secondary); Text(String(format: "%.1f", stat.difficulty)) }
                GridRow { Text("Next due").foregroundStyle(.secondary); Text(stat.due.map { $0.formatted(.relative(presentation: .named)) } ?? "—") }
                GridRow { Text("Reviews").foregroundStyle(.secondary); Text("\(stat.reps), \(stat.lapses) lapses") }
            }
            .font(.callout)
            if !logs.isEmpty {
                Divider()
                Text("History").font(.caption).foregroundStyle(.secondary)
                ForEach(logs.prefix(12)) { log in
                    HStack(spacing: 8) {
                        Text(log.reviewedAt.formatted(date: .abbreviated, time: .shortened)).monospacedDigit()
                        Text(log.grade.rawValue.capitalized).bold()
                        Text(label(log.source)).foregroundStyle(.secondary)
                        if let e = log.wordErrors, let n = log.wordCount { Text("\(e)/\(n) wrong").foregroundStyle(.secondary) }
                        if log.hintsUsed > 0 { Text("\(log.hintsUsed) hints").foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 320, alignment: .leading)
    }

    private func label(_ source: ReviewSource) -> String {
        switch source {
        case .transitionCard: "card"
        case .fullRecitation: "run"
        case .stanzaRun: "stanza run"
        case .acquisition: "learning"
        }
    }
}
