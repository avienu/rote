import Foundation
import RoteCore
import SwiftData

#if DEBUG
/// Public-domain sample poems for previews and screenshots.
/// Seeded when the app launches with `ROTE_SEED_FIXTURES=1` and the store is empty.
enum SampleData {
    static let sonnet30 = """
    When to the sessions of sweet silent thought
    I summon up remembrance of things past,
    I sigh the lack of many a thing I sought,
    And with old woes new wail my dear time's waste:
    Then can I drown an eye, unused to flow,
    For precious friends hid in death's dateless night,
    And weep afresh love's long since cancell'd woe,
    And moan the expense of many a vanish'd sight:
    Then can I grieve at grievances foregone,
    And heavily from woe to woe tell o'er
    The sad account of fore-bemoaned moan,
    Which I new pay as if not paid before.
    But if the while I think on thee, dear friend,
    All losses are restor'd and sorrows end.
    """

    static let tyger = """
    Tyger Tyger, burning bright,
    In the forests of the night;
    What immortal hand or eye,
    Could frame thy fearful symmetry?

    In what distant deeps or skies.
    Burnt the fire of thine eyes?
    On what wings dare he aspire?
    What the hand, dare seize the fire?

    And what shoulder, & what art,
    Could twist the sinews of thy heart?
    And when thy heart began to beat,
    What dread hand? & what dread feet?

    What the hammer? what the chain,
    In what furnace was thy brain?
    What the anvil? what dread grasp,
    Dare its deadly terrors clasp!

    When the stars threw down their spears
    And water'd heaven with their tears:
    Did he smile his work to see?
    Did he who made the Lamb make thee?

    Tyger Tyger burning bright,
    In the forests of the night:
    What immortal hand or eye,
    Dare frame thy fearful symmetry?
    """

    @MainActor
    static func seedIfRequested(into context: ModelContext) {
        guard ProcessInfo.processInfo.environment["ROTE_SEED_FIXTURES"] != nil else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Poem>())) ?? 0
        guard count == 0 else { return }
        context.insert(Poem.make(title: "Sonnet 30", author: "William Shakespeare", rawText: sonnet30))
        context.insert(Poem.make(title: "The Tyger", author: "William Blake", rawText: tyger))
        try? context.save()
    }
}
#endif
