import RoteCore
import SwiftData
import SwiftUI

/// Steps through the due transition cards of the given poems.
struct ReviewSessionView: View {
    let poems: [Poem]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("desiredRetention") private var desiredRetention = FSRSScheduler.defaultRetention
    @AppStorage("defaultInputMode") private var defaultModeRaw = InputMode.selfGrade.rawValue

    private struct Entry {
        let poem: Poem
        let item: TransitionItem
        let card: TransitionCard
    }

    @State private var queue: [QueueCard] = []
    @State private var entries: [UUID: Entry] = [:]
    @State private var index = 0
    @State private var mode: InputMode = .selfGrade
    @State private var reviewed = 0

    var body: some View {
        NavigationStack {
            Group {
                if index < queue.count, let entry = entries[queue[index].itemID] {
                    TransitionCardView(poem: entry.poem, item: entry.item, card: entry.card, mode: $mode) { grade, result in
                        apply(grade: grade, result: result, entry: entry)
                    }
                    .id(entry.item.id)
                } else {
                    ContentUnavailableView {
                        Label(reviewed == 0 ? "Nothing due" : "All caught up", systemImage: "checkmark.circle")
                    } description: {
                        Text(reviewed == 0 ? "Come back when a line falls due." : "\(reviewed) cards reviewed.")
                    } actions: {
                        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                    }
                }
            }
            .navigationTitle("Review")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stop") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .principal) {
                    if index < queue.count {
                        Text("\(index + 1) of \(queue.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear(perform: build)
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 540)
        #endif
    }

    private func build() {
        let now = Date()
        mode = InputMode(rawValue: defaultModeRaw).flatMap { $0 == .speech ? nil : $0 } ?? .selfGrade
        var cards: [QueueCard] = []
        var map: [UUID: Entry] = [:]
        for poem in poems where poem.status == .reviewing {
            for item in poem.dueItems(now: now) {
                guard let card = TransitionCard.make(poem: poem, targetOrder: item.targetLineOrder) else { continue }
                cards.append(QueueCard(itemID: item.id, poemID: poem.id, lineOrder: item.targetLineOrder, contextOrders: card.contextOrders))
                map[item.id] = Entry(poem: poem, item: item, card: card)
            }
        }
        queue = ReviewQueue.order(cards)
        entries = map
        index = 0
    }

    private func apply(grade: Grade, result: CardResult, entry: Entry) {
        let retention = entry.poem.settings.desiredRetention ?? desiredRetention
        let engine = ReviewEngine(scheduler: FSRSScheduler(desiredRetention: retention))
        engine.apply(grade: grade, to: entry.item, now: Date(), source: .transitionCard, mode: result.mode,
                     wordErrors: result.wordErrors, wordCount: result.wordCount, elapsedMs: result.elapsedMs,
                     hintsUsed: result.hintsUsed)
        try? context.save()
        reviewed += 1
        index += 1
    }
}

/// What the card learned about the attempt, for the review log.
struct CardResult {
    var mode: InputMode
    var wordErrors: Int?
    var wordCount: Int?
    var elapsedMs: Int
    var hintsUsed: Int
}
