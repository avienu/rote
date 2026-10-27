import Foundation

/// The order in which drafts are meant to be learned. The first draft is the
/// suggested next poem; nothing stops the user starting another one.
/// Poems with an explicit `queueOrder` come first in that order; unplaced
/// poems (nil) follow, alphabetically by title.
public enum LearningQueue {
    public static func ordered(_ drafts: [Poem]) -> [Poem] {
        drafts.sorted { a, b in
            switch (a.queueOrder, b.queueOrder) {
            case let (x?, y?) where x != y: x < y
            case (.some, .none): true
            case (.none, .some): false
            default: a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
    }

    /// The suggested next poem.
    public static func next(in drafts: [Poem]) -> Poem? { ordered(drafts).first }

    /// Applies a list reorder (as `onMove` reports it) and renumbers every
    /// draft so each has an explicit position.
    @discardableResult
    public static func move(_ drafts: [Poem], fromOffsets: IndexSet, toOffset: Int) -> [Poem] {
        let current = ordered(drafts)
        let moving = fromOffsets.map { current[$0] }
        var list = current.enumerated().filter { !fromOffsets.contains($0.offset) }.map(\.element)
        let removedBefore = fromOffsets.filter { $0 < toOffset }.count
        list.insert(contentsOf: moving, at: toOffset - removedBefore)
        renumber(list)
        return list
    }

    /// Makes `poem` the suggested next one.
    @discardableResult
    public static func moveToFront(_ poem: Poem, in drafts: [Poem]) -> [Poem] {
        var list = ordered(drafts).filter { $0 !== poem }
        list.insert(poem, at: 0)
        renumber(list)
        return list
    }

    static func renumber(_ list: [Poem]) {
        for (index, poem) in list.enumerated() where poem.queueOrder != index {
            poem.queueOrder = index
        }
    }
}
