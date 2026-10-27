import Testing
@testable import RoteCore

@Suite struct PoemParserTests {
    @Test func sonnetIsOneStanzaOfFourteen() {
        let poem = Fixture.sonnet30.poem
        #expect(poem.stanzas.count == 1)
        #expect(poem.lines.count == 14)
        #expect(poem.lines.map(\.order) == Array(0..<14))
    }

    @Test func tygerHasSixStanzas() {
        let poem = Fixture.tyger.poem
        #expect(poem.stanzas.count == 6)
        #expect(poem.lines.count == 24)
        #expect(poem.stanzas[2].lines.first?.order == 8)
        #expect(poem.stanzas[2].lines.first?.stanzaIndex == 2)
    }

    @Test func consecutiveBlankLinesCollapse() {
        let poem = PoemParser.parse("\n\nA\nB\n\n\n\nC\n\n")
        #expect(poem.stanzas.count == 2)
        #expect(poem.lines.map(\.text) == ["A", "B", "C"])
    }

    @Test func contextLinesAreMarkedAndStripped() {
        let poem = Fixture.upHill.poem
        let context = poem.lines.filter(\.isContext)
        #expect(context.map(\.order) == [0, 9])
        #expect(context[0].text == "The traveller asks; the indented lines answer.")
        #expect(poem.askedLines.count == 16)
    }

    @Test func indentationPreservedTrailingWhitespaceTrimmed() {
        let poem = PoemParser.parse("  indented   \n\tTabbed\t\n")
        #expect(poem.lines[0].text == "  indented")
        #expect(poem.lines[1].text == "\tTabbed")
        let burns = Fixture.toAMouse.poem
        #expect(burns.lines[3].text == "          Wi' bickering brattle!")
    }

    @Test func contextMarkerAfterIndentKeepsIndent() {
        let poem = PoemParser.parse("   @Chorus:")
        #expect(poem.lines[0].isContext)
        #expect(poem.lines[0].text == "   Chorus:")
    }

    @Test func windowsLineEndings() {
        let poem = PoemParser.parse("A\r\nB\r\n\r\nC")
        #expect(poem.stanzas.count == 2)
        #expect(poem.lines.map(\.text) == ["A", "B", "C"])
    }

    @Test func suggestedTitleIsFirstLine() {
        #expect(Fixture.sonnet30.poem.suggestedTitle == "When to the sessions of sweet silent thought")
    }

    @Test(arguments: Fixture.allCases)
    func exportRoundTrips(fixture: Fixture) {
        #expect(PoemParser.export(fixture.poem) == fixture.text)
    }
}
