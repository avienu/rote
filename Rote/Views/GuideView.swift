import RoteCore
import SwiftUI

/// "How Rote works": shown once on first launch and available any time from
/// Help (Mac), the More menu (iOS), Settings and the empty detail pane.
/// Plain prose that matches the rules in RoteCore; no new behaviour lives here.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenGuide") private var hasSeenGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    intro
                    ForEach(Self.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(section.title, systemImage: section.symbol)
                                .font(.headline)
                            ForEach(section.points, id: \.self) { point in
                                Text(point)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("Ten minutes a day beats an hour on Sunday. Keep one poem in Learning at a time and let Review carry the rest.")
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("How Rote works")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasSeenGuide ? "Done" : "Get started") {
                        hasSeenGuide = true
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 620, idealHeight: 760)
        #endif
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rote gets a poem into memory word for word, then keeps it there.")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Learning a poem is a few short sittings: you recite small groups of lines while the cues fade, sleep on it, then recite the whole thing twice. After that every line has its own review schedule, and Review asks for the lines just before they would slip.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    struct Section: Identifiable {
        let title: String
        let symbol: String
        let points: [String]
        var id: String { title }
    }

    #if os(macOS)
    static let addHint = "Press ⌘N or drop a text file on the editor. You can also open a .txt or a Rote export with the app."
    static let reorderHint = "Drag drafts to reorder them, or right-click one and choose Learn next."
    static let cardKeys = "Keys: space reveals, H hints, R records, 1–4 grade, P peeks."
    static let helpPlace = "This guide lives in the Help menu."
    #else
    static let addHint = "Tap + to type or paste a poem, or share a .txt or a Rote export to Rote."
    static let reorderHint = "Tap Edit above Drafts to drag them into order, or long-press one and choose Learn next."
    static let cardKeys = ""
    static let helpPlace = "This guide lives under the ⋯ menu in the library."
    #endif

    static let sections: [Section] = [
        Section(title: "Add a poem", symbol: "plus.circle", points: [
            addHint,
            "Paste the text exactly as printed. Blank lines are stanza breaks and indentation is kept; Rote never changes a poem's text.",
            "Start a line with @ to mark context, such as a speaker's name: it is shown but never asked.",
        ]),
        Section(title: "Drafts are a queue", symbol: "list.number", points: [
            "The top draft is marked Up next. It is a suggestion, not a rule: Start learning works on any poem. " + reorderHint,
            "Already know a poem? Use Review now (skip learning) from its ⋯ menu to go straight to review.",
        ]),
        Section(title: "Learning: windows and fading cues", symbol: "graduationcap", points: [
            "Press Start learning on a poem. First you read it through once. Then Rote shows a window of lines, one line at first, and you look away and say them from memory.",
            "Answer by speaking, by typing the first letter of each word, or by grading yourself after a reveal. Switch modes on any card; set your usual one in Settings.",
            "Each line has a cue level: full text, faded words, first letters, first word, blank. Get a line right (90% of words or better) and its cue fades a step; stumble (under 70%) and it comes back a step. Peek shows the line without stepping it down.",
            "When every line in a window is down to first letters, the window passes. When all windows pass, the window grows, up to six lines. A sitting stops after twenty minutes; your place is saved.",
        ]),
        Section(title: "Sleep on it", symbol: "moon.stars", points: [
            "After the windowing passes, the poem locks until after you have slept (the next early morning). This is deliberate: sleep does the consolidating. Nothing else in Rote is blocked.",
        ]),
        Section(title: "Two full recitations", symbol: "text.alignleft", points: [
            "When the poem opens again, recite the whole thing with nothing shown. Two recitations at 85% or better, at least four hours apart, finish learning.",
            "After the first, Rote shows a heat map of the lines that went wrong and offers a short stumble drill on the weakest.",
        ]),
        Section(title: "Review", symbol: "rectangle.stack", points: [
            "Once learned, every line gets its own schedule. A card shows the two lines before and asks for the next one, because that join is what fails in a recitation. Review is due when the count shows next to a poem or on the Review button.",
            "Grade honestly: Again, Hard, Good, Easy. Hints are allowed and simply cap the grade. " + cardKeys,
            "Now and then a card asks for a whole stanza or the whole poem with nothing shown. That one recitation grades every line in it at once; lines you skipped count as Again.",
        ]),
        Section(title: "Speaking", symbol: "mic", points: [
            "Speech is recognised on the device. Rote never passes you on the transcript alone: it shows the diff, and you can tap a red word to say you did get it right and it was misheard.",
            "Old spellings such as o'er and 'tis are accepted for their modern forms and shown in amber.",
        ]),
        Section(title: "Heat map and drills", symbol: "scope", points: [
            "A reviewing poem shows each word tinted by how often you miss it. Tap a line for its history and next due date. Drill weak lines runs a quick session on the ones most likely to slip.",
        ]),
        Section(title: "Finding this again", symbol: "questionmark.circle", points: [
            helpPlace + " It is also in Settings.",
        ]),
    ]
}

#Preview { GuideView() }
