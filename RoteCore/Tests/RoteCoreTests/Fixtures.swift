import Foundation
@testable import RoteCore

enum Fixture: String, CaseIterable {
    case sonnet30 = "sonnet-30"
    case tyger = "the-tyger"
    case upHill = "up-hill"
    case toAMouse = "to-a-mouse"

    var text: String {
        let url = Bundle.module.url(forResource: rawValue, withExtension: "txt", subdirectory: "Fixtures")!
        var s = try! String(contentsOf: url, encoding: .utf8)
        while s.hasSuffix("\n") { s.removeLast() }
        return s
    }

    var poem: ParsedPoem { PoemParser.parse(text) }

    /// Tokenized asked+context lines as (order, tokens) pairs.
    var tokenizedLines: [(order: Int, tokens: [Token])] {
        poem.lines.map { ($0.order, Tokenizer.tokenize($0.text)) }
    }
}
