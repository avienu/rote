import Testing
@testable import RoteCore

@Suite struct TokenizerTests {
    @Test func splitsLeadingAndTrailingPunctuation() {
        let tokens = Tokenizer.tokenize("Tyger Tyger, burning bright,")
        #expect(tokens.map(\.surface) == ["Tyger", "Tyger", ",", "burning", "bright", ","])
        #expect(tokens.map(\.isWord) == [true, true, false, true, true, false])
        #expect(tokens.map(\.normalized) == ["tyger", "tyger", "", "burning", "bright", ""])
    }

    @Test func rangesAreUTF16Offsets() {
        let line = "  O, what a panic's"
        let tokens = Tokenizer.tokenize(line)
        for t in tokens {
            let start = String.Index(utf16Offset: t.range.lowerBound, in: line)
            let end = String.Index(utf16Offset: t.range.upperBound, in: line)
            #expect(String(line[start..<end]) == t.surface)
        }
        #expect(tokens[0].range == 2..<3)
    }

    @Test func internalApostrophesAndHyphensStay() {
        let tokens = Tokenizer.tokenize("tell o'er the well-nigh cancell'd woe")
        #expect(tokens.map(\.surface) == ["tell", "o'er", "the", "well-nigh", "cancell'd", "woe"])
        #expect(tokens[1].normalized == "o'er")
        #expect(tokens[3].normalized == "wellnigh")
        #expect(tokens[4].normalized == "cancell'd")
    }

    @Test func leadingAndTrailingApostrophesSplitOff() {
        let tis = Tokenizer.tokenize("'Tis wi' thee")
        #expect(tis.map(\.surface) == ["'", "Tis", "wi", "'", "thee"])
        #expect(tis.filter(\.isWord).map(\.normalized) == ["tis", "wi", "thee"])
    }

    @Test func curlyQuotesAndDashesFold() {
        let tokens = Tokenizer.tokenize("“o’er” — said he…")
        #expect(tokens.map(\.surface) == ["“", "o’er", "”", "—", "said", "he", "…"])
        #expect(tokens[1].normalized == "o'er")
    }

    @Test func nfkcAndCase() {
        #expect(Normalizer.normalize("ﬁre") == "fire")
        #expect(Normalizer.normalize("Ｆull") == "full")
        #expect(Normalizer.normalize("HEART") == "heart")
    }

    @Test func diacriticsFoldOnlyForEnglish() {
        #expect(Normalizer.normalize("café", locale: "en-GB") == "cafe")
        #expect(Normalizer.normalize("café", locale: "fr-FR") == "café")
    }

    @Test func digitsKept() {
        #expect(Tokenizer.tokenize("in 1819,").map(\.normalized) == ["in", "1819", ""])
    }

    @Test func symbolsAreNotWords() {
        let tokens = Tokenizer.tokenize("And what shoulder, & what art,")
        #expect(tokens.filter(\.isWord).map(\.normalized) == ["and", "what", "shoulder", "what", "art"])
        #expect(tokens[4].surface == "&")
    }

    @Test func equivalenceTable() {
        #expect(Equivalence.areEquivalent("o'er", "over"))
        #expect(Equivalence.areEquivalent("never", "ne'er"))
        #expect(Equivalence.areEquivalent("tis", "tis"))
        #expect(!Equivalence.areEquivalent("tis", "it's"))
        #expect(!Equivalence.areEquivalent("o'er", "over", locale: "de-DE"))
    }

    @Test func burnsFixtureTokenizesWithoutLosingText() {
        for line in Fixture.toAMouse.poem.lines {
            let tokens = Tokenizer.tokenize(line.text)
            let rebuilt = tokens.map(\.surface).joined()
            #expect(rebuilt == line.text.filter { !$0.isWhitespace })
        }
    }
}
