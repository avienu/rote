import RoteCore
import SwiftUI

/// The target line after a recitation: each word tinted by its alignment op.
/// Tapping a red word marks it "I actually said this" (an ASR correction).
struct DiffLineView: View {
    let line: CardLine
    let attempt: SpeechAttempt
    /// Expected index of the line's first word within the attempt.
    var firstExpectedIndex = 0
    let onTap: (Int) -> Void

    private struct Chunk: Identifiable {
        let id: Int
        var pieces: [(token: Token, wordIndex: Int?)]
    }

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(chunks) { chunk in
                HStack(spacing: 0) {
                    ForEach(Array(chunk.pieces.enumerated()), id: \.offset) { _, piece in
                        if let w = piece.wordIndex {
                            let expected = firstExpectedIndex + w
                            let op = attempt.op(expectedIndex: expected)
                            Text(piece.token.surface)
                                .foregroundStyle(color(op, corrected: attempt.corrections.contains(expected)))
                                .strikethrough(op == .deletion && !attempt.corrections.contains(expected), color: .red)
                                .onTapGesture {
                                    if attempt.rawAlignment.steps.contains(where: { $0.expectedIndex == expected && $0.op.isError }) {
                                        onTap(expected)
                                    }
                                }
                        } else {
                            Text(piece.token.surface).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .font(.system(.title3, design: .serif))
    }

    private var chunks: [Chunk] {
        var result: [Chunk] = []
        var wordIndex = 0
        var lastEnd = -1
        for token in line.tokens {
            let w: Int? = token.isWord ? wordIndex : nil
            if token.isWord { wordIndex += 1 }
            if token.range.lowerBound == lastEnd, !result.isEmpty {
                result[result.count - 1].pieces.append((token, w))
            } else {
                result.append(Chunk(id: result.count, pieces: [(token, w)]))
            }
            lastEnd = token.range.upperBound
        }
        return result
    }

    private func color(_ op: AlignmentOp?, corrected: Bool) -> Color {
        if corrected { return .green }
        switch op {
        case .match, nil: return .primary
        case .equivalent: return .orange
        case .substitution, .deletion, .insertion: return .red
        }
    }
}

/// Minimal wrapping layout for word chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
