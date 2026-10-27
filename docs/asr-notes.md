# ASR notes

Measured behaviour of Apple `SpeechAnalyzer` / `SpeechTranscriber` in Rote, plus
API gaps. Update this file whenever something below changes.

## SDK facts (Xcode 27.1, iOS 26 / macOS 26 SDK)

- `SpeechTranscriber(locale:preset:)` with `.timeIndexedProgressiveTranscription`
  gives volatile + final results and `audioTimeRange` attributes per word run.
  Rote reads `run.audioTimeRange` from `result.text.runs` for word timings.
- Contextual-string biasing **is** exposed: `AnalysisContext.contextualStrings`
  keyed by `AnalysisContext.ContextualStringsTag.general`, set via
  `SpeechAnalyzer.setContext(_:)`. Rote passes the poem's unique normalized
  words before each recording. Whether it measurably helps archaic diction is
  still to be measured (table below).
- Assets: `AssetInventory.status(forModules:)` then
  `assetInstallationRequest(supporting:)` → `downloadAndInstall()`. `prepare`
  does this and throws `localeUnsupported` / `assetsUnavailable` so the card
  can fall back to typing or self-grade.
- Microphone permission is requested with `AVAudioApplication.requestRecordPermission()`.
  `SFSpeechRecognizer` authorization is **not** requested; verify on device that
  `SpeechAnalyzer` does not require it. If it does, add the request in
  `SpeechAnalyzerEngine.start()` (the `NSSpeechRecognitionUsageDescription`
  string is already in Info.plist).
- Audio: `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` decides the
  format; the `AVAudioEngine` input tap is converted with `AVAudioConverter`.
  Mac input-device selection is a Settings item (M8).

## Open gaps / TODO

- [ ] Confirm no `SFSpeechRecognizer` authorization is needed (see above).
- [ ] Confirm timing attributes arrive on volatile results, not only final ones.
- [ ] Decide whether `.fastResults` reporting option is worth the accuracy cost for
      single-line cards.
- [ ] Measure the effect of contextual strings on the archaic words below.

## Manual smoke test (run on a real device after each Speech change)

1. New poem with locale `en-US`; open a transition card; switch to Speak.
2. First use: mic permission prompt appears once; asset download (if any) shows
   status text, then the mic button enables.
3. Tap record, say the line, tap stop. Transcript streamed while speaking.
4. Diff shows green/amber/red words; proposed grade matches the §6.2 table;
   no grade is applied until a button is pressed.
5. Tap a red word → it turns green, grade proposal updates, `asrCorrections`
   increments in the log.
6. Say an extra "um" mid-line → counted as insertion, accuracy unchanged.
7. Skip a word → red deletion on that word.
8. Mac: `R` toggles recording; space / 1–4 still work after stop.
9. Switch locale to one without assets (e.g. `is-IS`) → card says speech is
   unavailable and offers typing.

## WER on archaic diction

Fill in from real recordings (3 takes each, quiet room, built-in mic). WER =
(sub + del + ins) / expected words, from the diff view before corrections.

| Text | Words | Without context strings | With context strings | Notes |
|---|---|---|---|---|
| Hopkins, "The Windhover" (first 6 lines) | | | | |
| Donne, "Batter my heart" (first 8 lines) | | | | |
| Burns, "To a Mouse" stanza 1 | | | | Scots contractions |
| Shakespeare, Sonnet 30 (full) | | | | `cancell'd`, `o'er` |

Common confusions observed (append as found): `o'er → over` (handled by the
equivalence table), `thee → the`, `thy → the`.
