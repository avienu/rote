import Foundation
import Testing
@testable import RoteCore

@Suite @MainActor struct LearningQueueTests {
    func poem(_ title: String, order: Int? = nil) -> Poem {
        let p = Poem.make(title: title, author: nil, rawText: "one\ntwo")
        p.queueOrder = order
        return p
    }

    @Test func placedFirstThenUnplacedByTitle() {
        let drafts = [poem("Zebra"), poem("Beta", order: 1), poem("Apple"), poem("Gamma", order: 0)]
        #expect(LearningQueue.ordered(drafts).map(\.title) == ["Gamma", "Beta", "Apple", "Zebra"])
        #expect(LearningQueue.next(in: drafts)?.title == "Gamma")
    }

    @Test func moveRenumbersEveryDraft() {
        let drafts = [poem("A", order: 0), poem("B", order: 1), poem("C"), poem("D")]
        let moved = LearningQueue.move(drafts, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(moved.map(\.title) == ["D", "A", "B", "C"])
        #expect(moved.map(\.queueOrder) == [0, 1, 2, 3])
        #expect(LearningQueue.ordered(drafts).map(\.title) == ["D", "A", "B", "C"])
    }

    @Test func moveToFrontMakesItNext() {
        let drafts = [poem("A", order: 0), poem("B", order: 1), poem("C", order: 2)]
        LearningQueue.moveToFront(drafts[2], in: drafts)
        #expect(LearningQueue.next(in: drafts)?.title == "C")
        #expect(LearningQueue.ordered(drafts).map(\.queueOrder) == [0, 1, 2])
    }

    @Test func emptyQueueHasNoNext() {
        #expect(LearningQueue.next(in: []) == nil)
    }

    @Test func archiveCarriesQueueOrderAndOldArchivesDecode() throws {
        let p = poem("Queued", order: 4)
        let data = try PoemArchive.jsonData(PoemArchive.export([p]))
        #expect(try PoemArchive.decode(data).poems[0].queueOrder == 4)
        let old = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"queueOrder\" : 4,", with: "")
        #expect(try PoemArchive.decode(Data(old.utf8)).poems[0].queueOrder == nil)
    }
}

extension LearningQueueTests {
    @Test func moveDownUsesListSemantics() {
        // SwiftUI reports `toOffset` against the list before removal: moving A to index 3 puts it after C.
        let drafts = [poem("A", order: 0), poem("B", order: 1), poem("C", order: 2), poem("D", order: 3)]
        let moved = LearningQueue.move(drafts, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(moved.map(\.title) == ["B", "C", "A", "D"])
    }
}
