import Foundation

/// Creates the review items for a poem (§5.5). Also used to skip acquisition
/// for a poem the user already knows.
public enum Handoff {
    /// Creates one `TransitionItem` per asked line that lacks one, seeds each
    /// with `seedGrades[lineOrder]` when given, and marks the poem `.reviewing`.
    @discardableResult
    public static func perform<S: Scheduler>(poem: Poem, engine: ReviewEngine<S>, seedGrades: [Int: Grade] = [:],
                                             now: Date = Date()) -> [TransitionItem] {
        var items = poem.items ?? []
        let existing = Set(items.map(\.targetLineOrder))
        var created: [TransitionItem] = []
        for line in poem.askedLines where !existing.contains(line.order) {
            let item = TransitionItem(targetLineOrder: line.order, due: now)
            item.poem = poem
            if let grade = seedGrades[line.order] {
                engine.apply(grade: grade, to: item, now: now, source: .acquisition, mode: .speech)
            }
            items.append(item)
            created.append(item)
        }
        poem.items = items
        poem.status = .reviewing
        poem.updatedAt = now
        return created
    }
}
