# Rote

Personal iPhone + Mac app for memorizing poetry verbatim. `SPEC.md` is the
source of truth; `CLAUDE.md` has the working rules.

## Layout

- `RoteCore/` — Swift package with every rule: `TextKit` (parse, tokenize,
  align), `Ladder` (acquisition), `Scheduling` (FSRS adapter, queue,
  propagation, runs, heat map, export), `Speech` (engine boundary,
  `SpeechAnalyzer` implementation), `Model` (SwiftData).
- `Rote/` — SwiftUI multiplatform app (iOS 26, macOS 26).
- `project.yml` — xcodegen spec; `Rote.xcodeproj` is generated from it and committed.
- `docs/asr-notes.md` — speech findings, smoke test, WER table.

## Build

```sh
swift test --package-path RoteCore          # the rules
xcodegen generate                            # after adding files to Rote/
xcodebuild -project Rote.xcodeproj -scheme Rote -destination 'platform=macOS' build
```

The development team (`DEVELOPMENT_TEAM` in `project.yml`) is set to Shawn's
company team; change it there and run `xcodegen generate` if you build under
another account. The first signed build registers the Mac in the developer
account and creates the CloudKit container `iCloud.com.avienu.rote`.

## Development hooks (Debug builds)

| Env var | Effect |
|---|---|
| `ROTE_LOCAL_STORE=1` | local storage, no CloudKit (needed for unsigned runs) |
| `ROTE_STORE_PATH=path` | throwaway store location |
| `ROTE_SEED_FIXTURES=1` | seed sample poems into an empty store |
| `ROTE_SEED_HISTORY=1` | plus two imperfect run-throughs for the heat map |
| `ROTE_FAKE_TRANSCRIPT=auto` | canned speech engine (one wrong word, one "um") |
| `ROTE_AUTO_REVIEW`, `ROTE_AUTO_LEARN`, `ROTE_AUTO_RUN`, `ROTE_AUTO_SPEAK`, `ROTE_AUTO_APPLY`, `ROTE_AUTO_SETTINGS` | open screens for screenshots |
| `ROTE_SNAPSHOT=file.png` | Mac: write the key window to a PNG and quit |

## Keyboard (Mac)

⌘N new poem · ⌘R review · ⌘I import · ⇧⌘E export all · ⌘, settings.
Files can also be opened directly, from Finder, the iOS share sheet or `open -a Rote <file>`:
a JSON export is imported (poems with the same id are replaced, schedules included);
a `.txt` opens the editor pre-filled. A text file may start with a two-line header,
title then author, followed by a blank line; see `library/poems/README.md`.
On a card: space reveal · H hint · R record · 1–4 grade · P peek (learning).

## Library

`library/POEMS.md` is the ranked reading list; `library/poems/` holds public-domain
texts in the header format, and `tools/txt2rote.py` bundles them into
`library/rote-import.json` for a one-shot import.
`library/poems/ORDER.txt` sets the Drafts queue order the archive carries.

Drafts are a learning queue: the top one is marked **Up next**, drag rows to reorder
(Edit on iOS), or right-click a draft and choose **Learn next**. It is a suggestion;
Start learning works on any draft.
