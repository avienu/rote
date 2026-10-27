# Rote — Implementation Spec (v1)

Personal app for memorizing poetry verbatim. iPhone + Mac, SwiftUI, on-device.

Decisions locked (2026-10-27):

| # | Decision | Choice |
|---|---|---|
| 1 | Speech engine | iOS 26 / macOS 26 minimum; Apple `SpeechAnalyzer` (on-device) |
| 2 | Platforms | iPhone and Mac together in v1; iPad/watch/visionOS later |
| 3 | Scheduler | `4rays/swift-fsrs` (MIT) behind a `Scheduler` protocol |
| 4 | Storage | SwiftData + CloudKit (private database) |
| 5 | v1 scope | Acquisition ladder + transition-level FSRS + speech check + grade propagation + heat map |
| 6 | Spec location | `~/Dropbox/prog/poetry-mem/SPEC.md` (this file) |
| 7 | Name | Rote (bundle id `com.avienu.rote`) |

---

## 1. Problem and thesis

A poem is one long ordered sequence. Flashcards fail because (a) one card per poem means failing the whole poem on one slip, and (b) one card per line in order breaks spaced repetition, which assumes independent, shuffleable items.

Rote's thesis, drawn from the survey of existing tools:

1. **The schedulable unit is the *transition*** — "given the previous k lines, produce line i" (LPCG / Cloze Overlapper insight). Every transition gets its own FSRS state.
2. **Acquisition and review are different modes.** Overlapping clozes are good for review, bad for first learning (LPCG's own author). Acquisition uses a growing window and a cue ladder (Memorize By Heart / LineByLine / Bible Memory App insight).
3. **A full recitation should update every line's schedule.** Align the spoken transcript to the poem, derive a per-line grade from word errors, and log an implicit review for each transition. No shipping app does this; it closes the gap between "I pass every card" and "I can recite the whole poem."
4. **The text is sacred.** Original line breaks, stanza breaks, punctuation, capitalization and indentation are stored exactly and never altered by any mode. Rote is a scaffold around the text, never a filter on it.

Non-goals for v1: audio playback/recording, meter overlay, meaning/"intention" prompts, loci anchors, import from online sources, sharing, any server.

---

## 2. Platforms and project layout

- Xcode project `Rote` with one multiplatform SwiftUI app target (iOS 26+, macOS 26+), plus Swift Package `RoteCore` for all non-UI logic so it is unit-testable without a simulator.
- `RoteCore` modules (folders in one package, one library target):
  - `Model/` — SwiftData models + value types.
  - `TextKit/` — poem parsing, tokenization, normalization, alignment/diff.
  - `Scheduling/` — `Scheduler` protocol, FSRS adapter, transition/item selection, grade propagation.
  - `Ladder/` — acquisition state machine and cue rendering rules.
  - `Speech/` — `SpeechEngine` protocol + `SpeechAnalyzerEngine`.
- Dependencies: `4rays/swift-fsrs` via SwiftPM. Nothing else in v1.
- Minimum deployment: iOS 26.0, macOS 26.0. Swift 6 language mode, strict concurrency.
- Mac is a real Mac app (not Catalyst/Designed-for-iPad): sidebar + detail, keyboard-first review (space = reveal, 1–4 = grade, R = record).

---

## 3. Data model (SwiftData)

All models carry `id: UUID`, `createdAt`, `updatedAt`. CloudKit requires optionals/defaults on every stored property and no unique constraints; follow that.

```
Poem
  title: String
  author: String?
  sourceNote: String?            // where the text came from
  rawText: String                // exact text as imported, never mutated
  locale: String                 // BCP-47, default "en-US"; drives speech + normalization
  status: PoemStatus             // .draft, .acquiring, .reviewing, .retired
  stanzas: [Stanza]              // ordered via `order`
  acquisition: AcquisitionState? // see §5
  settings: PoemSettings         // contextLines (default 2), ladder overrides

Stanza
  order: Int
  lines: [Line]

Line
  order: Int                     // global line index within poem (0-based), not per stanza
  text: String                   // exact, including leading whitespace
  isContext: Bool                // true = shown but never asked (dialogue/chorus marks)
  tokens: [Token]                // derived, cached; rebuilt if `text` changes
  ladderRung: LadderRung         // current cue level during acquisition (§5)

Token  (value type, Codable, stored as array on Line)
  surface: String                // exact substring incl. punctuation
  normalized: String             // lowercase, punctuation stripped, curly quotes folded, numerals as spelled? (no — keep digits; see §4)
  isWord: Bool                   // false for pure punctuation tokens
  range: Range<Int>              // UTF-16 offsets into Line.text

TransitionItem                   // the FSRS unit
  poem: Poem
  targetLineOrder: Int           // the line to produce
  schedulerState: Data           // opaque, owned by Scheduler (FSRS Card encoded)
  due: Date
  stability: Double              // mirrored from scheduler for queries
  difficulty: Double
  lapses: Int
  reps: Int
  lastReviewedAt: Date?

ReviewLog
  item: TransitionItem
  reviewedAt: Date
  grade: Grade                   // .again, .hard, .good, .easy
  source: ReviewSource           // .transitionCard, .fullRecitation, .stanzaRun, .acquisition
  mode: InputMode                // .speech, .firstLetterTyping, .selfGrade
  wordErrors: Int?               // from alignment when available
  wordCount: Int?
  elapsedMs: Int?
  hintsUsed: Int

WordStat                         // heat-map source
  poem: Poem
  lineOrder: Int
  tokenIndex: Int
  attempts: Int
  errors: Int                    // substitutions + deletions at this token
  lastErrorAt: Date?

RunItem                          // whole-poem / stanza chains (see §6.4)
  poem: Poem
  scope: RunScope                // .wholePoem, .stanza(order)
  due: Date
  lastRunAt: Date?
```

Context lines (`isContext == true`) have no `TransitionItem` of their own but do appear as context for the next asked line.

A line edit after items exist: rebuild tokens, keep the `TransitionItem` (the schedule survives small fixes), reset `WordStat` rows for that line.

---

## 4. Text handling (`TextKit`)

### 4.1 Import/parsing
- Input: plain text pasted or typed (iOS share sheet later). Also a `.txt` file drop on Mac.
- Blank line = stanza break. Consecutive blank lines collapse to one break.
- Line prefixed with `@` = context line (`isContext = true`); the `@` is stripped from `text`.
- Leading whitespace preserved (indentation is part of the poem). Trailing whitespace trimmed.
- First line is offered as title if title empty; user confirms.
- Everything is editable in a plain editor afterwards; Rote never auto-"fixes" text.

### 4.2 Tokenization and normalization
- Split on whitespace; then separate leading/trailing punctuation into their own non-word tokens. Internal apostrophes/hyphens stay inside the word (`o'er`, `well-nigh`).
- `normalized`: Unicode NFKC → lowercase → strip all punctuation except internal apostrophes → fold curly quotes/dashes → collapse diacritics only if `locale` is English.
- Keep digits as digits. Also keep a tiny equivalence table per locale for ASR drift (`o'er`↔`over`, `'tis`↔`tis`↔`it's`? — only `o'er/over`, `e'er/ever`, `ne'er/never`, `'tis/tis`, `'twas/twas` in v1). Equivalents count as **correct but flagged** (shown in amber, not red).

### 4.3 Alignment (the core of speech checking)
- Input: expected tokens (words only) for a span of lines; hypothesis tokens from the transcript (normalized the same way).
- Algorithm: Levenshtein-style word alignment (Needleman–Wunsch with match=0, sub=1, ins=1, del=1), backtrace to produce an op list `[match | sub | ins | del]` per expected token. O(n·m) is fine: spans are ≤ 300 words.
- Insertions (filler, restarts, "um") are not charged to any token but counted on the span.
- Output per line: `wordCount`, `errors` (sub+del), `insertions`, and per-token op for the heat map.
- Boundary handling for full recitations: align the whole poem at once, then split ops by line using the expected tokens' line membership. This avoids mis-assigning errors when a user skips a line (a run of deletions lands on the right line).

---

## 5. Acquisition mode (first days with a poem)

Purpose: get a poem from zero to "can recite with effort" using the LPCG protocol, automated.

### 5.1 State

```
AcquisitionState
  phase: .reading | .windowing | .sleepGate | .consolidating | .handedOff
  windowSize: Int                 // 1…6
  cursor: Int                     // next line index to work on
  sessionCount: Int
  lastSessionEndedAt: Date?
  sleepGateOpensAt: Date?         // set when windowing completes
```

Per line: `ladderRung` in `.full → .faded → .firstLetters → .firstWord → .blank`.

### 5.2 Flow
1. **Reading.** Show the full poem. User taps "I've read it". (One screen, nothing clever.)
2. **Windowing.** For `windowSize` in 1…6:
   - Walk the poem in windows of `windowSize` lines (non-overlapping, respecting that a window never starts on a context line).
   - For each window: show the lines at their current rung → user looks away and recites (speech or self-grade) → align → if all lines in window ≥ 90% words correct and no hint used, each line steps **down** one rung; if any line < 70%, that line steps **up** one rung (toward more cue); between 70–90%, stay.
   - Window passes when every line in it is at rung ≤ `.firstLetters` with ≥ 90% correct. Then advance.
   - A window size pass over the whole poem completes when all windows passed. Then `windowSize += 1`.
   - Hard cap per session: 20 minutes or user stop; state persists mid-walk.
3. **Sleep gate.** After the `windowSize == 6` pass (or after 3 full windowing passes, whichever is first), set `sleepGateOpensAt = next local 04:00 that is ≥ 6h away`. Show "Come back after you've slept." Nothing in this poem is available until then. (Non-negotiable per LPCG; a settings toggle can disable it for testing only.)
4. **Consolidating.** Two full-poem recitations on separate sessions ≥ 4h apart, each with ≥ 85% words correct overall. After the first, show the heat map and offer a "stumble drill" on lines < 80%.
5. **Hand-off.** Create `TransitionItem` for every non-context line (and `RunItem`s, §6.4). Seed each item with an initial review: grade derived from that line's consolidation accuracy (≥95% → `.easy`, ≥85 → `.good`, ≥70 → `.hard`, else `.again`). `status = .reviewing`.

### 5.3 Cue rendering per rung
- `.full` — exact text.
- `.faded` — show first letter + every content word whose index is even; hide others as `▁▁▁` with length proportional to the word. Deterministic per line so the user isn't seeing a different puzzle each time.
- `.firstLetters` — first letter of every word, punctuation kept, e.g. `S i c t t a s d?`
- `.firstWord` — only the first word of the line; rest blank.
- `.blank` — line number and a hairline only.

Context lines render at `.full` always, visually dimmed.

---

## 6. Review mode (long-term)

### 6.1 `Scheduler` protocol

```swift
protocol Scheduler: Sendable {
  associatedtype State: Codable & Sendable
  func newState(now: Date) -> State
  func review(_ state: State, grade: Grade, now: Date) -> (State, due: Date, stability: Double, difficulty: Double)
  func retrievability(_ state: State, now: Date) -> Double   // 0…1
}
```

`FSRSScheduler` wraps `4rays/swift-fsrs`. Default parameters from the library. Desired retention 0.90. Expose `desiredRetention` in Settings (0.80–0.97). Parameter optimization is out of v1 scope; the `ReviewLog` is already shaped so FSRSKit's optimizer can consume it later (item id, timestamp, grade, elapsed days).

### 6.2 Transition card
- Front: previous `contextLines` (default 2) non-hidden lines rendered in full, then the target line rendered `.blank` (or at a hint rung if the user asks). Stanza breaks are drawn when they fall inside the shown span. For the first line of a poem the context is the title.
- Input modes (user picks a default; can switch per card):
  - **Speak**: press-and-hold or tap-to-toggle mic; transcript streams in; on stop, align against the target line; auto-propose a grade (≥95% & no hints → `.good`, user can bump to `.easy`; 80–95 → `.hard`; <80 → `.again`). User confirms with one tap or keyboard.
  - **First-letter typing**: user types the first letter of each word in order; a wrong letter shows the word and counts an error; auto-grade as above using errors/wordCount.
  - **Self-grade**: tap to reveal; 4 buttons.
- Hints: "next letter" → "next word" → "whole line". Each hint caps the max grade (`.good`, `.hard`, `.again` respectively).
- Target line revealed in full after grading, with the diff colored.

### 6.3 Queue construction
- Due `TransitionItem`s across all `.reviewing` poems, shuffled, **but** two items from the same poem are never adjacent when alternatives exist, and the same line is never shown within 3 cards of being used as *context* (soft sibling spacing, since we don't get Anki's burying).
- New-item introduction isn't needed (hand-off creates all items at once with seeded grades).
- Daily cap: none by default; show count on the home screen.

### 6.4 Run items (chains)
- On hand-off create one `RunItem` per stanza and one for the whole poem.
- Stanza run due = `min(due of its transitions) + 1 day`, recomputed after every review in that stanza. Whole-poem run due = earliest stanza-run due + 2 days, floor 3 days after last whole-poem run.
- A run shows *nothing* (title only; stanza number for stanza runs) and expects a full recitation via speech (typing allowed on Mac). Result feeds §7.

### 6.5 Per-line hint state in review
If a transition item lapses twice in a row, the card for that line opens at `.firstLetters` for the next review and the max grade is `.good`. Clears after one clean pass.

---

## 7. Grade propagation (the differentiator)

After any aligned multi-line recitation (`RunItem`, consolidation pass, or stanza drill):

1. For each asked line `i` in the span, compute `acc_i = 1 − errors_i / wordCount_i` (deletions and substitutions; insertions ignored).
2. Map to an implicit grade: `≥0.95 → .good`, `0.80–0.95 → .hard`, `<0.80 → .again`. Never `.easy` from propagation (user may bump only on explicit cards).
3. Hesitation signal (v1-light): if `SpeechAnalyzer` timestamps show a pause > 2.5 s immediately before the first word of line `i`, cap line `i` at `.hard`.
4. Apply `scheduler.review(state, grade, now)` to each line's `TransitionItem` and write a `ReviewLog` with `source = .fullRecitation` (or `.stanzaRun`).
5. **Guardrail:** propagation may advance an item's `due` by at most the interval the scheduler proposes, but may never schedule it *later* than `now + 2 × previousInterval`. (Prevents one lucky run-through from pushing a shaky line out a month.)
6. Update `WordStat` for every token in the span.
7. Skipped lines (whole line deleted) → `.again`, and the *next* line's grade is also capped at `.hard` (the transition into it was never exercised).

---

## 8. Heat map

- Poem view with every word tinted by `errors / attempts` from `WordStat` (0 → no tint; ≥ 0.5 → strong red; use a 4-step scale, not continuous, so it reads at a glance). Lines additionally show a left gutter bar with transition stability (short = weak).
- Tap a line → its review history, current stability/difficulty, next due.
- "Drill weak spots" button: ad-hoc session of transition cards for lines whose `retrievability < 0.7` or whose last two `WordStat` windows show ≥ 1 error, ordered weakest first. Drill reviews are logged with `source = .transitionCard` and *do* update scheduling.
- Heat map resets per line on text edit; "Clear stats" per poem in settings.

---

## 9. Speech (`SpeechAnalyzerEngine`)

- Protocol:
  ```swift
  protocol SpeechEngine: Sendable {
    func prepare(locale: Locale) async throws        // triggers asset download if needed
    func start() async throws -> AsyncStream<SpeechUpdate>   // partial + final text with word timings when available
    func stop() async throws -> SpeechResult          // final transcript, [WordTiming]
  }
  ```
- Implementation: `SpeechAnalyzer` + `SpeechTranscriber` (long-form, on-device). Request `.audioTimeRange` attributes for word timings. Ask for mic permission on first use; speech recognition permission as required by the framework.
- Do **not** auto-pass on ASR output alone. Always show the diff; the user can tap a red word to mark it "I actually said this" (ASR misheard), which flips that token to match and re-grades. Those corrections are logged (`ReviewLog.hintsUsed` unaffected; add `asrCorrections: Int`).
- Contextual biasing: if the API exposes vocabulary/contextual strings, feed the poem's unique words. Mark as `TODO` if not available in the shipped SDK; test empirically with archaic diction (Hopkins, Donne) and record WER in `docs/asr-notes.md`.
- Locale asset handling: on poem create, call `prepare(locale:)`; if assets are unavailable for the locale, fall back to self-grade/typing and say so.
- Mac: same code path; AVAudioEngine input device selection in Settings.

---

## 10. UI (v1 screens)

1. **Library** — list of poems grouped by status; due count per poem; "+ Add poem".
2. **Add/Edit poem** — title, author, text editor (monospaced optional), locale picker, context-line (`@`) help, live stanza/line count. "Start learning" → acquisition.
3. **Acquisition session** — window view with cue rungs, big mic button, progress (window n of N, pass k of 6), stop. Sleep-gate screen.
4. **Review session** — transition card; mode switcher; hint; grade bar; keyboard shortcuts on Mac.
5. **Run** — title only + mic; afterwards full-poem diff view with per-line accuracy and "apply" (auto-applied; button is "Done").
6. **Poem detail** — heat map, stats (retention forecast = mean retrievability of items, weakest 5 lines), "Drill weak spots", settings (context lines, desired retention, sleep gate toggle), text edit, retire.
7. **Settings** — default input mode, desired retention, audio input device (Mac), export.

Design: plain, typographic, poem-first. Serif for poem text (New York / system serif), sans for chrome. Dark mode respected. No gamification, no streaks in v1.

---

## 11. Export / import

- Export poem as plain text (`@` restored for context lines) and as JSON (`poem + items + review logs`) for backup and later optimizer use.
- Import JSON from an export (restores schedules). No `.apkg` in v1.

---

## 12. Testing

`RoteCore` unit tests, required before UI work on each area:
- Parsing: stanza breaks, `@` lines, indentation preserved, round-trip export == input.
- Tokenization/normalization: punctuation splitting, internal apostrophes, equivalence table, NFKC.
- Alignment: known op lists for insert/delete/substitute cases; skipped-line attribution; whole-poem split-by-line correctness.
- Ladder: rung transitions at the 70/90 thresholds; deterministic `.faded` rendering.
- Scheduler adapter: round-trip encode/decode of state; `due` monotonic under `.good`.
- Propagation: grade mapping, `.easy` never produced, guardrail cap, skipped-line rule, hesitation cap.
- Queue: no adjacent same-poem items when alternatives exist.
- Speech: engine mocked via protocol; one manual smoke test checklist in `docs/asr-notes.md`.

Fixture poems in `Tests/Fixtures/`: a sonnet (14 lines, 1 stanza), a stanzaic poem (≥ 4 stanzas), one with dialogue/context lines, one with heavy indentation and archaic contractions.

---

## 13. Build order (milestones)

| M | Deliverable | Done when |
|---|---|---|
| 0 | Project + `RoteCore` package + SwiftPM dep + CI test run | `swift test` green on empty suites |
| 1 | TextKit: parse, tokenize, normalize, align + tests | fixtures pass |
| 2 | Models + SwiftData + CloudKit container; Library + Add/Edit on iOS and Mac | create/edit/sync a poem between devices |
| 3 | Scheduler adapter + TransitionItem + queue + review card with **self-grade and typing** | can review a hand-created poem end to end |
| 4 | SpeechAnalyzerEngine + diff view in review card | speak a line, see diff, grade proposed |
| 5 | Acquisition mode incl. sleep gate and hand-off | a new poem goes draft → reviewing |
| 6 | Run items + grade propagation + WordStat | one recitation updates N items; guardrail tested |
| 7 | Heat map + drill | weak lines visible and drillable |
| 8 | Export/import, settings, polish, Mac keyboard shortcuts | personal daily use |

Each milestone is a PR. Ship M3 to a TestFlight build and start using it before M4; real reviews inform the rest.

---

## 14. Open questions (not blocking; decide during build)

- Whether `SpeechAnalyzer` exposes contextual-string biasing in the shipped SDK (§9).
- Equivalence table: fixed list in v1; consider a per-poem "accepted variants" list if ASR drift is frequent.
- `.faded` rung may be too easy or too hard; thresholds (70/90) and the even-index rule are the first things to tune from real use.
- Whether stanza runs are worth their screen time for short poems (< 12 lines): v1 skips stanza runs for single-stanza poems.

---

## 15. Provenance

Ideas borrowed from: LPCG (sobjornstad/AnkiLPCG, acquisition protocol + transition cards), Cloze Overlapper and michalrus/anki-simple-cloze-overlapper (render-time overlap from one source), Memorize By Heart and The Bible Memory App (first-letter mode, 90% mastery bar, heat maps), LineByLine (per-line unlocking with fading), AnkiPoetry (`@` context lines), Memdora (first-word / step-through modes), Noice & Noice (meaning-first rehearsal — deferred to v1.1). LPCG and Cloze Overlapper are AGPL: read for ideas, do not copy code.
