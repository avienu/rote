import Testing
@testable import RoteCore

@Suite struct PoemFileTests {
    let headed = "The Lamp\nA. N. Other\n\nA lamp sat on the sill,\n  and burned.\n\nThe night went still.\n"

    @Test func headerIsSplitOff() {
        let file = PoemFile.parse(headed)
        #expect(file.title == "The Lamp")
        #expect(file.author == "A. N. Other")
        #expect(file.body == "A lamp sat on the sill,\n  and burned.\n\nThe night went still.\n")
    }

    @Test func bodySurvivesParsingUnchanged() {
        let body = PoemFile.parse(headed).body
        let parsed = PoemParser.parse(body)
        #expect(parsed.stanzas.count == 2)
        #expect(parsed.lines.map(\.text) == ["A lamp sat on the sill,", "  and burned.", "The night went still."])
        #expect(PoemParser.export(parsed) + "\n" == body)
    }

    @Test func punctuatedCoupletIsNotAHeader() {
        let couplet = "The cat sat on the mat,\nand that was that.\n\nA second stanza follows here.\n"
        let file = PoemFile.parse(couplet)
        #expect(file.title == nil)
        #expect(file.author == nil)
        #expect(file.body == couplet)
    }

    @Test func noBlankThirdLineMeansNoHeader() {
        let poem = "Shall I compare\nthee to a day\nof summer\n\nmore"
        #expect(PoemFile.parse(poem) == PoemFile(body: poem))
    }

    @Test func indentedContextOrLongSecondLineIsNotAHeader() {
        #expect(PoemFile.parse("  Indented\nName\n\nbody").title == nil)
        #expect(PoemFile.parse("@Speaker\nName\n\nbody").title == nil)
        #expect(PoemFile.parse("Title\none two three four five six seven eight nine\n\nbody").title == nil)
        #expect(PoemFile.parse("Title\nName\n\n\nbody").title == nil)
    }

    @Test func lineEndingsAreNormalisedAndTrailingSpaceTrimmedFromHeader() {
        let file = PoemFile.parse("Title  \r\nName\r\n\r\nline one\r\nline two")
        #expect(file.title == "Title")
        #expect(file.author == "Name")
        #expect(file.body == "line one\nline two")
    }

    @Test func libraryFixtureParsesWithHeader() {
        let file = PoemFile.parse("Ozymandias\nPercy Bysshe Shelley\n\nI met a traveller from an antique land,\nWho said—")
        #expect(file.title == "Ozymandias")
        #expect(file.author == "Percy Bysshe Shelley")
        #expect(PoemParser.parse(file.body).lines.count == 2)
    }
}
