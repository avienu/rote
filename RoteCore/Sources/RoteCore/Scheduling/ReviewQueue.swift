import Foundation

/// A due card as the queue sees it: enough to apply spacing rules.
public struct QueueCard: Hashable, Sendable {
    public var itemID: UUID
    public var poemID: UUID
    public var lineOrder: Int
    /// Orders of the lines shown as context on this card.
    public var contextOrders: [Int]

    public init(itemID: UUID, poemID: UUID, lineOrder: Int, contextOrders: [Int]) {
        self.itemID = itemID
        self.poemID = poemID
        self.lineOrder = lineOrder
        self.contextOrders = contextOrders
    }
}

/// Deterministic generator so queue tests are reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// §6.3: shuffle due cards, never put two cards of the same poem next to each
/// other when an alternative exists, and never ask a line within three cards
/// of it being shown as context.
public enum ReviewQueue {
    public static let contextSpacing = 3

    public static func order(_ cards: [QueueCard], seed: UInt64? = nil) -> [QueueCard] {
        var rng = SplitMix64(seed: seed ?? UInt64.random(in: 0...UInt64.max))
        return order(cards, using: &rng)
    }

    public static func order<G: RandomNumberGenerator>(_ cards: [QueueCard], using rng: inout G) -> [QueueCard] {
        var pool = cards.shuffled(using: &rng)
        var result: [QueueCard] = []
        result.reserveCapacity(pool.count)

        while !pool.isEmpty {
            let previousPoem = result.last?.poemID
            // Lines used as context in the last `contextSpacing` cards, per poem.
            let recentContext: [UUID: Set<Int>] = result.suffix(contextSpacing).reduce(into: [:]) { acc, card in
                acc[card.poemID, default: []].formUnion(card.contextOrders)
            }
            func violatesContext(_ c: QueueCard) -> Bool { recentContext[c.poemID]?.contains(c.lineOrder) ?? false }

            // Prefer the poem with the most cards left so alternatives never run
            // out early (the usual "no two adjacent equal" greedy).
            var remaining: [UUID: Int] = [:]
            for c in pool { remaining[c.poemID, default: 0] += 1 }
            func best(_ allowed: (QueueCard) -> Bool) -> Int? {
                var bestIndex: Int?
                var bestCount = -1
                for (i, c) in pool.enumerated() where allowed(c) {
                    let count = remaining[c.poemID] ?? 0
                    if count > bestCount { bestCount = count; bestIndex = i }
                }
                return bestIndex
            }
            let pick = best { $0.poemID != previousPoem && !violatesContext($0) }
                ?? best { $0.poemID != previousPoem }
                ?? best { !violatesContext($0) }
                ?? 0
            result.append(pool.remove(at: pick))
        }
        return result
    }
}
