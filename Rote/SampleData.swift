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

    static let upHill = """
    @The traveller asks; the indented lines answer.
    Does the road wind up-hill all the way?
       Yes, to the very end.
    Will the day's journey take the whole long day?
       From morn to night, my friend.

    But is there for the night a resting-place?
       A roof for when the slow dark hours begin.
    May not the darkness hide it from my face?
       You cannot miss that inn.

    @Later, the same voices:
    Shall I meet other wayfarers at night?
       Those who have gone before.
    Then must I knock, or call when just in sight?
       They will not keep you standing at that door.

    Shall I find comfort, travel-sore and weak?
       Of labour you shall find the sum.
    Will there be beds for me and all who seek?
       Yea, beds for all who come.
    """

    @MainActor
    static func seedIfRequested(into context: ModelContext) {
        guard ProcessInfo.processInfo.environment["ROTE_SEED_FIXTURES"] != nil else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Poem>())) ?? 0
        guard count == 0 else { return }
        let sonnet = Poem.make(title: "Sonnet 30", author: "William Shakespeare", rawText: sonnet30)
        context.insert(sonnet)
        context.insert(Poem.make(title: "The Tyger", author: "William Blake", rawText: tyger))
        Handoff.perform(poem: sonnet, engine: ReviewEngine(scheduler: FSRSScheduler()))
        if ProcessInfo.processInfo.environment["ROTE_AUTO_RUN"] != nil {
            sonnet.runItems?.forEach { $0.due = Date().addingTimeInterval(-60) }
        }
        let upHill = Poem.make(title: "Up-Hill", author: "Christina Rossetti", rawText: upHill)
        context.insert(upHill)
        var acq = AcquisitionMachine.start()
        AcquisitionMachine.finishReading(&acq)
        acq.windowSize = 2
        acq.cursor = 3
        upHill.acquisition = acq
        upHill.status = .acquiring
        let rungs: [Int: LadderRung] = [1: .blank, 2: .blank, 3: .firstLetters, 4: .faded, 5: .full]
        for (order, rung) in rungs { upHill.line(order: order)?.ladderRung = rung }
        try? context.save()
    }
}
#endif
