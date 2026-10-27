import Foundation

/// What a scheduler proposes after one review.
public struct ScheduleOutcome<State: Codable & Sendable>: Sendable {
    public var state: State
    public var due: Date
    public var stability: Double
    public var difficulty: Double
    /// Interval scheduled by this review, in days.
    public var scheduledDays: Double
    /// Days since the previous review.
    public var elapsedDays: Double
    public var lapses: Int
    public var reps: Int

    public init(state: State, due: Date, stability: Double, difficulty: Double,
                scheduledDays: Double, elapsedDays: Double, lapses: Int, reps: Int) {
        self.state = state
        self.due = due
        self.stability = stability
        self.difficulty = difficulty
        self.scheduledDays = scheduledDays
        self.elapsedDays = elapsedDays
        self.lapses = lapses
        self.reps = reps
    }
}

/// Spaced-repetition engine boundary (§6.1). `FSRSScheduler` is the v1 implementation.
public protocol Scheduler: Sendable {
    associatedtype State: Codable & Sendable
    func newState(now: Date) -> State
    func review(_ state: State, grade: Grade, now: Date) -> ScheduleOutcome<State>
    /// Probability of recall right now, 0…1.
    func retrievability(_ state: State, now: Date) -> Double
}
