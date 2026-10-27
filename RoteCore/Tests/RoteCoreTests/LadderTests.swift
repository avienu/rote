import Foundation
import Testing
@testable import RoteCore

@Suite struct CueRendererTests {
    let text = "Should I compare thee to a summer's day?"
    var tokens: [Token] { Tokenizer.tokenize(text) }

    @Test func rungs() {
        #expect(CueRenderer.render(text: text, tokens: tokens, rung: .full) == text)
        #expect(CueRenderer.render(text: text, tokens: tokens, rung: .faded) == "Should I compare t▁▁▁ to a summer's d▁▁?")
        #expect(CueRenderer.render(text: text, tokens: tokens, rung: .firstLetters) == "S I c t t a s d?")
        #expect(CueRenderer.render(text: text, tokens: tokens, rung: .firstWord) == "Should ▁ ▁▁▁▁▁▁▁ ▁▁▁▁ ▁▁ ▁ ▁▁▁▁▁▁▁▁ ▁▁▁?")
        #expect(CueRenderer.render(text: text, tokens: tokens, rung: .blank) == "")
    }

    @Test func fadedIsDeterministic() {
        let a = CueRenderer.render(text: text, tokens: tokens, rung: .faded)
        for _ in 0..<5 { #expect(CueRenderer.render(text: text, tokens: tokens, rung: .faded) == a) }
    }

    @Test func contextLinesAlwaysFull() {
        #expect(CueRenderer.render(text: "Chorus:", tokens: Tokenizer.tokenize("Chorus:"), rung: .blank, isContext: true) == "Chorus:")
    }

    @Test func indentationSurvivesEveryRung() {
        let t = "          Wi' bickering brattle!"
        for rung in LadderRung.allCases where rung != .blank {
            #expect(CueRenderer.render(text: t, tokens: Tokenizer.tokenize(t), rung: rung).hasPrefix("          "))
        }
    }
}

@Suite struct LadderPolicyTests {
    @Test func thresholds() {
        #expect(LadderPolicy.step(.full, accuracy: 0.90, hintUsed: false) == .faded)
        #expect(LadderPolicy.step(.full, accuracy: 0.95, hintUsed: true) == .full)      // hint blocks stepping down
        #expect(LadderPolicy.step(.faded, accuracy: 0.89, hintUsed: false) == .faded)
        #expect(LadderPolicy.step(.faded, accuracy: 0.70, hintUsed: false) == .faded)
        #expect(LadderPolicy.step(.faded, accuracy: 0.69, hintUsed: false) == .full)
        #expect(LadderPolicy.step(.full, accuracy: 0.1, hintUsed: false) == .full)       // clamps
        #expect(LadderPolicy.step(.blank, accuracy: 1, hintUsed: false) == .blank)
        #expect(LadderPolicy.step(.full, accuracy: 0.80, hintUsed: false, pass: 0.8, fail: 0.6) == .faded)
    }

    @Test func linePassRule() {
        #expect(!LadderPolicy.linePassed(rung: .faded, accuracy: 1, hintUsed: false))
        #expect(LadderPolicy.linePassed(rung: .firstLetters, accuracy: 0.9, hintUsed: false))
        #expect(LadderPolicy.linePassed(rung: .blank, accuracy: 0.95, hintUsed: false))
        #expect(!LadderPolicy.linePassed(rung: .blank, accuracy: 0.95, hintUsed: true))
        #expect(!LadderPolicy.linePassed(rung: .blank, accuracy: 0.85, hintUsed: false))
    }
}

@Suite struct AcquisitionMachineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00:00 UTC
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func lines(_ fixture: Fixture) -> [AcquisitionLine] {
        fixture.poem.lines.map { AcquisitionLine(order: $0.order, isContext: $0.isContext) }
    }

    @Test func windowsNeverStartOnContext() {
        let ls = lines(.upHill)   // context at 0 and 9; 16 asked lines
        let w2 = AcquisitionMachine.windows(lines: ls, size: 2)
        #expect(w2.count == 8)
        #expect(w2[0].orders == [0, 1, 2])          // context line 0 rides with the first window
        #expect(w2[0].askedOrders == [1, 2])
        #expect(w2[3].orders == [7, 8])
        #expect(w2[4].orders == [9, 10, 11])        // context line 9 tops the next window
        #expect(w2[4].askedOrders == [10, 11])
        #expect(w2.allSatisfy { $0.count == 8 })
        let w3 = AcquisitionMachine.windows(lines: ls, size: 3)
        #expect(w3.count == 6)
        #expect(w3.last?.askedOrders == [17])
        let w6 = AcquisitionMachine.windows(lines: lines(.sonnet30), size: 6)
        #expect(w6.map(\.askedOrders.count) == [6, 6, 2])
    }

    @Test func fullFlowToSleepGate() {
        var state = AcquisitionMachine.start()
        var ls = lines(.tyger)
        let settings = PoemSettings()
        #expect(state.phase == .reading)
        AcquisitionMachine.finishReading(&state)
        #expect(state.phase == .windowing && state.windowSize == 1)

        // Size 1: first window needs to climb to firstLetters before it can pass.
        var window = AcquisitionMachine.currentWindow(state: state, lines: ls)!
        #expect(window.askedOrders == [0])
        var out = AcquisitionMachine.apply(window: window, results: [0: LineResult(accuracy: 1)], state: &state, lines: &ls, settings: settings, now: now, calendar: utc)
        #expect(out == .repeatWindow)
        #expect(ls[0].rung == .faded)
        out = AcquisitionMachine.apply(window: window, results: [0: LineResult(accuracy: 1)], state: &state, lines: &ls, settings: settings, now: now, calendar: utc)
        #expect(out == .repeatWindow)
        #expect(ls[0].rung == .firstLetters)
        out = AcquisitionMachine.apply(window: window, results: [0: LineResult(accuracy: 0.95)], state: &state, lines: &ls, settings: settings, now: now, calendar: utc)
        #expect(out == .nextWindow)
        #expect(state.cursor == 1)
        #expect(ls[0].rung == .firstWord)

        // A slip below 70% pushes back up one rung.
        window = AcquisitionMachine.currentWindow(state: state, lines: ls)!
        out = AcquisitionMachine.apply(window: window, results: [1: LineResult(accuracy: 0.5)], state: &state, lines: &ls, settings: settings, now: now, calendar: utc)
        #expect(out == .repeatWindow)
        #expect(ls[1].rung == .full)

        // Pass size 1 (each line climbs to firstLetters first), then sizes 2 and
        // 3; the third full pass opens the sleep gate (§5.2, "whichever is first").
        func passEverything() -> WindowOutcome {
            var last: WindowOutcome = .repeatWindow
            var guardCount = 0
            repeat {
                let w = AcquisitionMachine.currentWindow(state: state, lines: ls)!
                let results = Dictionary(uniqueKeysWithValues: w.askedOrders.map { ($0, LineResult(accuracy: 1)) })
                last = AcquisitionMachine.apply(window: w, results: results, state: &state, lines: &ls, settings: settings, now: now, calendar: utc)
                guardCount += 1
            } while !(last == .sleepGate(opensAt: state.sleepGateOpensAt ?? now)) && guardCount < 500
                && { if case .passComplete = last { return false } else { return true } }()
            return last
        }
        #expect(passEverything() == .passComplete(nextWindowSize: 2))
        #expect(ls.allSatisfy { $0.rung >= .firstWord })
        #expect(passEverything() == .passComplete(nextWindowSize: 3))
        #expect(ls.allSatisfy { $0.rung == .blank })
        let final = passEverything()
        #expect(state.phase == .sleepGate)
        #expect(final == .sleepGate(opensAt: state.sleepGateOpensAt!))
        #expect(state.completedPasses == 3)
        #expect(state.sleepGateOpensAt!.timeIntervalSince(now) >= 6 * 3600)
    }

    @Test func threePassesAlsoGate() {
        var state = AcquisitionMachine.start()
        AcquisitionMachine.finishReading(&state)
        state.completedPasses = 2
        state.windowSize = 3
        var ls = lines(.sonnet30).map { AcquisitionLine(order: $0.order, isContext: false, rung: .blank) }
        let settings = PoemSettings()
        var out: WindowOutcome = .repeatWindow
        for _ in 0..<10 {
            let w = AcquisitionMachine.currentWindow(state: state, lines: ls)!
            out = AcquisitionMachine.apply(window: w, results: Dictionary(uniqueKeysWithValues: w.askedOrders.map { ($0, LineResult(accuracy: 1)) }),
                                           state: &state, lines: &ls, settings: settings, now: now, calendar: utc)
            if case .sleepGate = out { break }
        }
        guard case .sleepGate = out else { Issue.record("expected sleep gate"); return }
        #expect(state.completedPasses == 3)
    }

    @Test func sleepGateOpensAtNextFourAMAtLeastSixHoursAway() {
        let cal = utc
        // 08:00 → next 04:00 is 20h away.
        let a = AcquisitionMachine.sleepGateOpening(after: now, calendar: cal)
        #expect(cal.component(.hour, from: a) == 4)
        #expect(a.timeIntervalSince(now) == 20 * 3600)
        // 23:30 → 04:00 is only 4.5h away → the day after.
        let late = cal.date(bySettingHour: 23, minute: 30, second: 0, of: now)!
        let b = AcquisitionMachine.sleepGateOpening(after: late, calendar: cal)
        #expect(b.timeIntervalSince(late) == 28.5 * 3600)
        // 21:00 → 04:00 is 7h away → fine.
        let evening = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now)!
        #expect(AcquisitionMachine.sleepGateOpening(after: evening, calendar: cal).timeIntervalSince(evening) == 7 * 3600)
    }

    @Test func gateBlocksUntilOpenUnlessDisabled() {
        var state = AcquisitionState()
        state.phase = .sleepGate
        state.sleepGateOpensAt = now.addingTimeInterval(3600)
        var settings = PoemSettings()
        #expect(AcquisitionMachine.isGated(state, settings: settings, now: now))
        AcquisitionMachine.openGateIfDue(&state, settings: settings, now: now)
        #expect(state.phase == .sleepGate)
        AcquisitionMachine.openGateIfDue(&state, settings: settings, now: now.addingTimeInterval(3601))
        #expect(state.phase == .consolidating)

        var s2 = AcquisitionState(); s2.phase = .sleepGate; s2.sleepGateOpensAt = now.addingTimeInterval(3600)
        settings.sleepGateEnabled = false
        #expect(!AcquisitionMachine.isGated(s2, settings: settings, now: now))
    }

    @Test func consolidationRules() {
        var state = AcquisitionState()
        state.phase = .consolidating
        let lineAcc: [Int: Double] = [0: 1, 1: 0.9, 2: 0.7, 3: 1]
        #expect(AcquisitionMachine.recordConsolidation(&state, accuracy: 0.8, lineAccuracy: lineAcc, now: now) == .belowThreshold(accuracy: 0.8, weakLines: [2]))
        #expect(state.consolidationPasses.isEmpty)
        #expect(AcquisitionMachine.recordConsolidation(&state, accuracy: 0.9, lineAccuracy: lineAcc, now: now) == .firstPassDone(weakLines: [2]))
        let soon = now.addingTimeInterval(3 * 3600)
        #expect(AcquisitionMachine.recordConsolidation(&state, accuracy: 0.95, lineAccuracy: lineAcc, now: soon) == .tooSoon(nextAllowedAt: now.addingTimeInterval(4 * 3600)))
        let later = now.addingTimeInterval(5 * 3600)
        let second: [Int: Double] = [0: 0.9, 1: 0.9, 2: 0.9, 3: 0.6]
        let out = AcquisitionMachine.recordConsolidation(&state, accuracy: 0.9, lineAccuracy: second, now: later)
        // Means: 0→0.95 easy, 1→0.9 good, 2→0.8 hard, 3→0.8 hard
        #expect(out == .readyForHandoff(seedGrades: [0: .easy, 1: .good, 2: .hard, 3: .hard]))
        #expect(state.phase == .handedOff)
    }
}
