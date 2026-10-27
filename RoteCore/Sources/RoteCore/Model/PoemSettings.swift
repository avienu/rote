import Foundation

/// Per-poem settings. Stored as JSON on `Poem`.
public struct PoemSettings: Codable, Hashable, Sendable {
    /// Non-hidden lines shown before the target on a transition card.
    public var contextLines: Int = 2
    /// Overrides the app-wide desired retention when set (0.80…0.97).
    public var desiredRetention: Double?
    /// Testing only: the sleep gate is non-negotiable in normal use.
    public var sleepGateEnabled: Bool = true
    /// Ladder thresholds (§5.2). Step down at or above `passThreshold`;
    /// step up below `failThreshold`.
    public var passThreshold: Double = 0.90
    public var failThreshold: Double = 0.70

    public init() {}
}

/// One full-poem recitation during consolidation.
public struct ConsolidationPass: Codable, Hashable, Sendable {
    public var recitedAt: Date
    public var accuracy: Double
    /// Accuracy per asked line, keyed by `Line.order`.
    public var lineAccuracy: [Int: Double]

    public init(recitedAt: Date, accuracy: Double, lineAccuracy: [Int: Double]) {
        self.recitedAt = recitedAt
        self.accuracy = accuracy
        self.lineAccuracy = lineAccuracy
    }
}

/// Acquisition progress (§5.1). Stored as JSON on `Poem`.
public struct AcquisitionState: Codable, Hashable, Sendable {
    public var phase: AcquisitionPhase = .reading
    /// 1…6
    public var windowSize: Int = 1
    /// Next line index to work on within the current window-size pass.
    public var cursor: Int = 0
    public var sessionCount: Int = 0
    public var lastSessionEndedAt: Date?
    public var sleepGateOpensAt: Date?
    /// Completed passes over the whole poem at any window size.
    public var completedPasses: Int = 0
    public var consolidationPasses: [ConsolidationPass] = []
    /// Set once the stumble drill after the first consolidation pass was offered.
    public var stumbleDrillOffered: Bool = false

    public init() {}
}
