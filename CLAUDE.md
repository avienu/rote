# Rote — notes for Claude Code

Rote is a personal iPhone + Mac app for memorizing poetry verbatim. Read `SPEC.md` first; it is the source of truth. Do not redesign what it decides; raise a question in the PR if something in it is impossible.

## Stack
- Swift 6, strict concurrency. SwiftUI multiplatform app target `Rote` (iOS 26+, macOS 26+).
- All logic lives in the Swift package `RoteCore` (`Model/`, `TextKit/`, `Scheduling/`, `Ladder/`, `Speech/`). UI code never contains alignment, scheduling or ladder rules.
- Scheduler: `4rays/swift-fsrs` behind the `Scheduler` protocol. Speech: Apple `SpeechAnalyzer` behind the `SpeechEngine` protocol. No other dependencies without asking.
- Storage: SwiftData + CloudKit private DB. Every stored property optional or defaulted; no `@Attribute(.unique)`.

## Rules
- The poem text is never altered by any mode. Line breaks, stanza breaks, indentation, punctuation and capitalization are preserved exactly. Normalization happens only on derived `Token.normalized`.
- Write `RoteCore` unit tests first for TextKit, Ladder, Scheduling and propagation (see SPEC §12). `swift test` must pass before any UI PR.
- Follow the milestone order in SPEC §13. One milestone per PR. Keep PRs small enough to review in ten minutes.
- Fixture poems go in `Tests/Fixtures/`. Use public-domain texts only.
- LPCG and Cloze Overlapper are AGPL: do not copy code from them.
- ASR output never auto-passes a review; always show the diff and let the user correct a misheard word.

## Conventions
- `Grade` is `.again/.hard/.good/.easy`. Propagated grades never produce `.easy`.
- Line indices (`Line.order`) are global within the poem, 0-based.
- Keep `docs/asr-notes.md` updated with measured WER on archaic diction and any SpeechAnalyzer API gaps.

## Working with Shawn
- When asking him to merge, give the PR's GitHub URL and the `gh` command.
- For UI changes, include screenshots (iOS and Mac) in the PR.
- Decisions for him: list each with context and a recommendation, and end with one pasteblock of lines he can return.
