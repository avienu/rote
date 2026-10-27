import Foundation

/// Turns pasted text into stanzas and lines, and back. Never alters text:
/// trailing whitespace is trimmed, leading whitespace is kept, blank lines mark
/// stanza breaks, and a leading `@` marks a context line.
public enum PoemParser {
    public static let contextMarker: Character = "@"

    public static func parse(_ input: String) -> ParsedPoem {
        let rawLines = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimTrailingWhitespace(String($0)) }

        var stanzas: [ParsedStanza] = []
        var current: [ParsedLine] = []
        var order = 0

        func closeStanza() {
            guard !current.isEmpty else { return }
            stanzas.append(ParsedStanza(order: stanzas.count, lines: current))
            current = []
        }

        for raw in rawLines {
            if raw.isEmpty {
                closeStanza()
                continue
            }
            let (text, isContext) = stripContextMarker(raw)
            current.append(ParsedLine(order: order, stanzaIndex: stanzas.count, text: text, isContext: isContext))
            order += 1
        }
        closeStanza()
        return ParsedPoem(stanzas: stanzas)
    }

    /// Plain-text export. Context lines get their `@` back. Round-trips any
    /// input that has single blank lines between stanzas and no trailing spaces.
    public static func export(_ poem: ParsedPoem) -> String {
        poem.stanzas
            .map { stanza in
                stanza.lines
                    .map { $0.isContext ? String(contextMarker) + $0.text : $0.text }
                    .joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    // MARK: - Helpers

    static func trimTrailingWhitespace(_ s: String) -> String {
        var scalars = Substring(s)
        while let last = scalars.last, last.isWhitespace {
            scalars.removeLast()
        }
        return String(scalars)
    }

    /// Splits off a leading `@` (after any indentation). The indentation is kept.
    static func stripContextMarker(_ line: String) -> (text: String, isContext: Bool) {
        guard let firstNonSpace = line.firstIndex(where: { !$0.isWhitespace }),
              line[firstNonSpace] == contextMarker
        else { return (line, false) }
        var text = line
        text.remove(at: firstNonSpace)
        return (text, true)
    }
}
