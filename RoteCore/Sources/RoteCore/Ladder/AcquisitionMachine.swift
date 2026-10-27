import Foundation

/// A line as the acquisition machine sees it.
public struct AcquisitionLine: Hashable, Sendable {
    public var order: Int
    public var isContext: Bool
    public var rung: LadderRung

    public init(order: Int, isContext: Bool, rung: LadderRung = .full) {
        self.order = order
        self.isContext = isContext
        self.rung = rung
    }
}

/// A window of consecutive lines: `askedOrders` are graded, `orders` includes
/// any context lines that fall inside the window (shown, never asked).
public struct AcquisitionWindow: Hashable, Sendable {
    public var index: Int
    public var count: Int
    public var orders: [Int]
    public var askedOrders: [Int]

    public init(index: Int, count: Int, orders: [Int], askedOrders: [Int]) {
        self.index = index
        self.count = count
        self.orders = orders
        self.askedOrders = askedOrders
    }
}

public struct LineResult: Hashable, Sendable {
    public var accuracy: Double
    public var hintUsed: Bool

    public init(accuracy: Double, hintUsed: Bool = false) {
        self.accuracy = accuracy
        self.hintUsed = hintUsed
    }
}

public enum WindowOutcome: Hashable, Sendable {
    /// Some line fell short; the same window is shown again.
    case repeatWindow
    case nextWindow
    /// The whole poem passed at this window size; the next size begins.
    case passComplete(nextWindowSize: Int)
    /// Windowing is finished; nothing is available until `opensAt`.
    case sleepGate(opensAt: Date)
}

public enum ConsolidationOutcome: Hashable, Sendable {
    case belowThreshold(accuracy: Double, weakLines: [Int])
    case tooSoon(nextAllowedAt: Date)
    /// First qualifying pass; offer a stumble drill on these lines.
    case firstPassDone(weakLines: [Int])
    /// Second qualifying pass; hand off with these seed grades.
    case readyForHandoff(seedGrades: [Int: Grade])
}

/// The acquisition state machine (§5). Pure functions over value types; the
/// UI persists the returned state and rungs.
public enum AcquisitionMachine {
    public static let maxWindowSize = 6
    public static let maxPasses = 3
    public static let sessionCap: TimeInterval = 20 * 60
    public static let sleepGateMinimumGap: TimeInterval = 6 * 3600
    public static let sleepGateHour = 4
    public static let consolidationMinimumAccuracy = 0.85
    public static let consolidationSessionGap: TimeInterval = 4 * 3600
    public static let consolidationPassesRequired = 2
    public static let stumbleThreshold = 0.80

    // MARK: Windows

    /// Non-overlapping windows of `size` asked lines. Context lines never count
    /// toward the size and never form a window of their own: they ride at the
    /// top of the next window (shown dimmed, never asked), or with the last
    /// window when they end the poem.
    public static func windows(lines: [AcquisitionLine], size: Int) -> [AcquisitionWindow] {
        var result: [AcquisitionWindow] = []
        var orders: [Int] = []
        var asked: [Int] = []
        for line in lines {
            orders.append(line.order)
            if line.isContext { continue }
            asked.append(line.order)
            if asked.count == size {
                result.append(AcquisitionWindow(index: result.count, count: 0, orders: orders, askedOrders: asked))
                orders = []
                asked = []
            }
        }
        if !asked.isEmpty {
            result.append(AcquisitionWindow(index: result.count, count: 0, orders: orders, askedOrders: asked))
        } else if !orders.isEmpty, !result.isEmpty {
            result[result.count - 1].orders += orders
        }
        for i in result.indices { result[i].count = result.count }
        return result
    }

    /// The window containing `state.cursor`.
    public static func currentWindow(state: AcquisitionState, lines: [AcquisitionLine]) -> AcquisitionWindow? {
        let all = windows(lines: lines, size: max(1, state.windowSize))
        return all.first { ($0.askedOrders.last ?? -1) >= state.cursor } ?? all.last
    }

    // MARK: Phases

    public static func start() -> AcquisitionState {
        AcquisitionState()
    }

    public static func finishReading(_ state: inout AcquisitionState) {
        guard state.phase == .reading else { return }
        state.phase = .windowing
        state.windowSize = 1
        state.cursor = 0
    }

    /// Applies one recitation of `window`. Rungs in `lines` are stepped in place.
    public static func apply(window: AcquisitionWindow, results: [Int: LineResult], state: inout AcquisitionState,
                             lines: inout [AcquisitionLine], settings: PoemSettings, now: Date,
                             calendar: Calendar = .current) -> WindowOutcome {
        var passed = true
        for order in window.askedOrders {
            guard let i = lines.firstIndex(where: { $0.order == order }) else { continue }
            let r = results[order] ?? LineResult(accuracy: 0)
            if !LadderPolicy.linePassed(rung: lines[i].rung, accuracy: r.accuracy, hintUsed: r.hintUsed, pass: settings.passThreshold) {
                passed = false
            }
            lines[i].rung = LadderPolicy.step(lines[i].rung, accuracy: r.accuracy, hintUsed: r.hintUsed,
                                              pass: settings.passThreshold, fail: settings.failThreshold)
        }
        guard passed else { return .repeatWindow }

        let all = windows(lines: lines, size: state.windowSize)
        if let next = all.first(where: { $0.index > window.index }), let first = next.askedOrders.first {
            state.cursor = first
            return .nextWindow
        }
        state.completedPasses += 1
        state.cursor = 0
        if state.windowSize >= maxWindowSize || state.completedPasses >= maxPasses {
            let opensAt = sleepGateOpening(after: now, calendar: calendar)
            state.phase = .sleepGate
            state.sleepGateOpensAt = opensAt
            return .sleepGate(opensAt: opensAt)
        }
        state.windowSize += 1
        return .passComplete(nextWindowSize: state.windowSize)
    }

    /// Next local 04:00 that is at least six hours away.
    public static func sleepGateOpening(after now: Date, calendar: Calendar = .current) -> Date {
        var candidate = calendar.nextDate(after: now, matching: DateComponents(hour: sleepGateHour, minute: 0, second: 0),
                                          matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        while candidate.timeIntervalSince(now) < sleepGateMinimumGap {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(86_400)
        }
        return candidate
    }

    public static func isGated(_ state: AcquisitionState, settings: PoemSettings, now: Date) -> Bool {
        guard state.phase == .sleepGate, settings.sleepGateEnabled, let opens = state.sleepGateOpensAt else { return false }
        return now < opens
    }

    /// Moves from the sleep gate to consolidation once it has opened (or the
    /// gate is disabled for testing).
    public static func openGateIfDue(_ state: inout AcquisitionState, settings: PoemSettings, now: Date) {
        guard state.phase == .sleepGate, !isGated(state, settings: settings, now: now) else { return }
        state.phase = .consolidating
    }

    /// Records a full-poem recitation during consolidation.
    public static func recordConsolidation(_ state: inout AcquisitionState, accuracy: Double, lineAccuracy: [Int: Double],
                                           now: Date) -> ConsolidationOutcome {
        let weak = lineAccuracy.filter { $0.value < stumbleThreshold }.keys.sorted()
        if let last = state.consolidationPasses.last, now.timeIntervalSince(last.recitedAt) < consolidationSessionGap {
            return .tooSoon(nextAllowedAt: last.recitedAt.addingTimeInterval(consolidationSessionGap))
        }
        guard accuracy >= consolidationMinimumAccuracy else {
            return .belowThreshold(accuracy: accuracy, weakLines: weak)
        }
        state.consolidationPasses.append(ConsolidationPass(recitedAt: now, accuracy: accuracy, lineAccuracy: lineAccuracy))
        if state.consolidationPasses.count >= consolidationPassesRequired {
            state.phase = .handedOff
            return .readyForHandoff(seedGrades: seedGrades(from: state.consolidationPasses))
        }
        return .firstPassDone(weakLines: weak)
    }

    /// Mean per-line accuracy over the qualifying passes → §5.5 grade.
    public static func seedGrades(from passes: [ConsolidationPass]) -> [Int: Grade] {
        var sums: [Int: (Double, Int)] = [:]
        for pass in passes {
            for (order, acc) in pass.lineAccuracy {
                let s = sums[order] ?? (0, 0)
                sums[order] = (s.0 + acc, s.1 + 1)
            }
        }
        return sums.mapValues { GradeProposal.forHandoff(accuracy: $0.0 / Double($0.1)) }
    }

    public static func endSession(_ state: inout AcquisitionState, now: Date) {
        state.sessionCount += 1
        state.lastSessionEndedAt = now
    }
}
