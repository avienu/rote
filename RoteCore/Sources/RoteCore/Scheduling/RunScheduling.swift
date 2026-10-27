import Foundation

/// Run items (§6.4): stanza runs and the whole-poem run, chained off the
/// transition items' due dates.
public enum RunScheduling {
    public static let stanzaLag: TimeInterval = 1 * 86_400
    public static let wholePoemLag: TimeInterval = 2 * 86_400
    public static let wholePoemFloor: TimeInterval = 3 * 86_400
    /// §14: single-stanza poems get no stanza runs.
    public static let minimumStanzasForStanzaRuns = 2

    /// Creates missing run items for a reviewing poem and schedules them.
    public static func ensureRunItems(poem: Poem, now: Date) {
        var runs = poem.runItems ?? []
        let stanzas = poem.orderedStanzas.filter { $0.orderedLines.contains { !$0.isContext } }
        if stanzas.count >= minimumStanzasForStanzaRuns {
            for stanza in stanzas where !runs.contains(where: { $0.scope == .stanza(stanza.order) }) {
                let run = RunItem(scope: .stanza(stanza.order), due: now)
                run.poem = poem
                runs.append(run)
            }
        }
        if !runs.contains(where: { $0.scope == .wholePoem }) {
            let run = RunItem(scope: .wholePoem, due: now)
            run.poem = poem
            runs.append(run)
        }
        poem.runItems = runs
        recompute(poem: poem, now: now)
    }

    /// Stanza run due = min(due of its transitions) + 1 day. Whole-poem run
    /// due = earliest stanza-run due + 2 days, never earlier than 3 days
    /// after the last whole-poem run.
    public static func recompute(poem: Poem, now: Date) {
        let runs = poem.runItems ?? []
        let items = poem.items ?? []
        var stanzaDues: [Date] = []

        for stanza in poem.orderedStanzas {
            let orders = Set(stanza.orderedLines.filter { !$0.isContext }.map(\.order))
            guard let earliest = items.filter({ orders.contains($0.targetLineOrder) }).map(\.due).min() else { continue }
            let due = earliest.addingTimeInterval(stanzaLag)
            stanzaDues.append(due)
            if let run = runs.first(where: { $0.scope == .stanza(stanza.order) }) {
                run.due = due
            }
        }
        if let whole = runs.first(where: { $0.scope == .wholePoem }) {
            let base = (stanzaDues.min() ?? items.map(\.due).min()?.addingTimeInterval(stanzaLag) ?? now).addingTimeInterval(wholePoemLag)
            let floor = whole.lastRunAt.map { $0.addingTimeInterval(wholePoemFloor) } ?? .distantPast
            whole.due = max(base, floor)
        }
    }

    /// Lines a run asks for.
    public static func askedOrders(poem: Poem, scope: RunScope) -> [Int] {
        switch scope {
        case .wholePoem:
            return poem.askedLines.map(\.order)
        case .stanza(let order):
            return poem.orderedStanzas.first { $0.order == order }?.orderedLines.filter { !$0.isContext }.map(\.order) ?? []
        }
    }

    public static func dueRuns(poem: Poem, now: Date) -> [RunItem] {
        (poem.runItems ?? []).filter { $0.due <= now }.sorted { $0.due < $1.due }
    }

    /// Marks a run done and reschedules the chain.
    public static func complete(run: RunItem, poem: Poem, now: Date) {
        run.lastRunAt = now
        recompute(poem: poem, now: now)
    }
}
