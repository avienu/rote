import Foundation
import SwiftData

extension Poem {
    /// Builds a poem from raw text. The text is stored exactly; structure is derived.
    public static func make(title: String, author: String?, rawText: String, locale: String = "en-US") -> Poem {
        let poem = Poem(title: title, author: author, rawText: rawText, locale: locale)
        poem.rebuildStructure(from: rawText)
        if poem.title.isEmpty, let suggested = PoemParser.parse(rawText).suggestedTitle {
            poem.title = suggested
        }
        return poem
    }

    /// Replaces the text and rebuilds stanzas, lines and tokens.
    ///
    /// Lines whose text changed get fresh tokens and their `WordStat` rows reset.
    /// `TransitionItem`s survive (keyed by line order); items for lines that no
    /// longer exist or became context are removed, and new asked lines get a
    /// fresh item when the poem is already reviewing.
    public func rebuildStructure(from newRawText: String) {
        let parsed = PoemParser.parse(newRawText)
        let oldLines = Dictionary(uniqueKeysWithValues: orderedLines.map { ($0.order, $0) })

        rawText = newRawText
        updatedAt = Date()

        var newStanzas: [Stanza] = []
        var changedOrders: Set<Int> = []
        for ps in parsed.stanzas {
            let stanza = Stanza(order: ps.order)
            stanza.lines = ps.lines.map { pl in
                let line = Line(order: pl.order, text: pl.text, isContext: pl.isContext, locale: locale)
                if let old = oldLines[pl.order] {
                    if old.text == pl.text, old.isContext == pl.isContext {
                        line.ladderRung = old.ladderRung
                    } else {
                        changedOrders.insert(pl.order)
                    }
                } else {
                    changedOrders.insert(pl.order)
                }
                return line
            }
            newStanzas.append(stanza)
        }
        stanzas = newStanzas

        // Reset heat-map rows for changed lines.
        let stats = wordStats ?? []
        wordStats = stats.filter { !changedOrders.contains($0.lineOrder) && oldLines[$0.lineOrder] != nil }

        // Reconcile transition items.
        let askedOrders = Set(parsed.askedLines.map(\.order))
        var items = self.items ?? []
        items.removeAll { !askedOrders.contains($0.targetLineOrder) }
        if status == .reviewing {
            let existing = Set(items.map(\.targetLineOrder))
            for order in askedOrders.subtracting(existing).sorted() {
                items.append(TransitionItem(targetLineOrder: order))
            }
        }
        self.items = items
    }

    /// Tokenized lines as the aligner wants them.
    public func tokenizedLines(orders: [Int]? = nil) -> [(order: Int, tokens: [Token])] {
        orderedLines
            .filter { line in orders?.contains(line.order) ?? true }
            .map { ($0.order, $0.tokens) }
    }

    /// Unique normalized words, for speech biasing.
    public var vocabulary: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for line in orderedLines {
            for token in line.tokens where token.isWord && !token.normalized.isEmpty && seen.insert(token.normalized).inserted {
                out.append(token.surface.trimmingCharacters(in: .punctuationCharacters))
            }
        }
        return out
    }

    /// Plain-text export with `@` restored on context lines.
    public var exportText: String {
        PoemParser.export(PoemParser.parse(rawText))
    }
}
