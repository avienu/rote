import Foundation
import SwiftFSRS

/// FSRS v5 via `4rays/swift-fsrs`, long-term scheduling (no intra-day steps).
public struct FSRSScheduler: Scheduler {
    public typealias State = SwiftFSRS.Card

    public static let retentionRange: ClosedRange<Double> = 0.80...0.97
    public static let defaultRetention = 0.90

    public var algorithm: FSRSAlgorithm

    public init(desiredRetention: Double = FSRSScheduler.defaultRetention) {
        var a = FSRSAlgorithm.v5
        a.requestRetention = Swift.min(Swift.max(desiredRetention, Self.retentionRange.lowerBound), Self.retentionRange.upperBound)
        algorithm = a
    }

    public var desiredRetention: Double { algorithm.requestRetention }

    public func newState(now: Date) -> Card {
        Card(due: now)
    }

    public func review(_ state: Card, grade: Grade, now: Date) -> ScheduleOutcome<Card> {
        let review = SchedulerType.longTerm.implementation.schedule(card: state, algorithm: algorithm,
                                                  reviewRating: Self.rating(grade), reviewTime: now)
        let card = review.postReviewCard
        return ScheduleOutcome(state: card, due: card.due, stability: card.stability, difficulty: card.difficulty,
                               scheduledDays: card.scheduledDays, elapsedDays: card.elapsedDays,
                               lapses: card.lapses, reps: card.reps)
    }

    public func retrievability(_ state: Card, now: Date) -> Double {
        guard let last = state.lastReview, state.stability > 0 else { return 0 }
        let elapsed = Swift.max(0, now.timeIntervalSince(last) / 86_400)
        return pow(1 + algorithm.factor * elapsed / state.stability, algorithm.decay)
    }

    static func rating(_ grade: Grade) -> Rating {
        switch grade {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}
