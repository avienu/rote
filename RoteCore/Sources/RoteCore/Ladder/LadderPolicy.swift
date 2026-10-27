import Foundation

/// Rung transitions (§5.2). Thresholds come from `PoemSettings` so they can be
/// tuned per poem; defaults are 0.90 / 0.70.
public enum LadderPolicy {
    /// ≥ pass and no hint → one rung less help; < fail → one rung more help; else stay.
    public static func step(_ rung: LadderRung, accuracy: Double, hintUsed: Bool,
                            pass: Double = 0.90, fail: Double = 0.70) -> LadderRung {
        if accuracy >= pass, !hintUsed { return rung.lessHelp }
        if accuracy < fail { return rung.moreHelp }
        return rung
    }

    /// A line counts as passed when recited at `.firstLetters` or less help
    /// with at least `pass` accuracy and no hint.
    public static func linePassed(rung: LadderRung, accuracy: Double, hintUsed: Bool, pass: Double = 0.90) -> Bool {
        rung >= .firstLetters && accuracy >= pass && !hintUsed
    }
}
