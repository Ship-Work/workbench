# Where Workbench was slow, heavy or stuck · 22 October 2026

The maintainer asked, after Finish on a meeting went from about 12 s to about half a second ([#392](https://github.com/Ship-Work/workbench/pull/392), [its record](2026-10-22-meeting-transcription-speed.md)): what value did the two long goal sessions of 14–16 October (the overnight batch, [its ledger](2026-10-15-overnight-batch.md); the Meetings lighthouse, [its record](2026-10-15-meetings-category.md)) leave unrealised, and where else has the app become inefficient? Three read-only audits answered with measurements on his Mac (Apple M5, 16 GB, macOS 26.5.1): an open-issue ledger, a hot-path probe against copies of his data and synthetic stores, and a disk and memory footprint. This record keeps what they found, what was built and what was left, with the trigger for each.

## 1. Where the earlier sessions' value is stuck

Almost nothing they filed is unbuilt. Of 103 open issues, 66 are built and shipped in 2.6.0 and stay open only under the Refs-not-Fixes policy, waiting for a check on the installed app; 6 are partly built, 14 unbuilt (most of them paused or awaiting a decision), 9 are not build items and 8 are superseded. The value is stuck in five places:

1. **The checks nobody ran.** About 60 issues need only a look on the installed app. The overnight batch's eleven-step morning tour was never taken.
2. **Meetings has never heard a real call.** Neither installed edition has ever recorded sound from a call app (`workbench.permissions.callAudio.v1` is unset in both), and the 15 October real-capture check found System Audio Recording silent for both. Detection is switched on in both editions; there has been no recording since 6 October.
3. **The running edition is behind.** The Preview in use is build 20261015183936 (`0d0ab43`); the 20 October Meetings fixes (#389) and #392 are in no installed build.
4. **Decisions waiting:** #357's two naming choices, #60, #64 and #287's naming.
5. **Superseded issues padding the list:** #17, #58, #65, #70, #149, #161, #173 and #220 (Read and retired surfaces); #160, #171, #172 and #223 effectively accepted.

The round-five angles the batch left unswept (privacy and disk hygiene, scale, deck output, dates and time zones, sleep and display, offline) are partly covered here: disk hygiene and scale below; the others remain the place a next pass starts.

## 2. What was measured, and what was built

| Finding | Measured | Built |
| --- | --- | --- |
| After every new binary or macOS update, the Neural Engine compiles Parakeet's encoder again; Dictate refused and sent the window to Models | 15.4 s for a new build against the same cache, then 0.56 s; encoder alone 15.35 s; the installed apps' compile caches rewritten minutes after each install | Dictate records while the saved model loads and transcribes at Stop once it is ready (`claude/dictate-while-speech-warms`) |
| Live Dictate words first appeared 2.3 s after starting, 1.44 s after speech at the median | `--check-live-voice-model`; 120 synthetic dictations | Dictate reads every second at user-initiated priority: 0.60 s median, same 1.55% word error rate (`claude/dictate-sooner-words`, on #392) |
| A two-sided meeting keeps about 806 MB an hour, forever | 16-bit PCM at 48 kHz, two tracks, plus 115 MB an hour of segments when the fallback ran | Committed originals rewritten as Apple Lossless, verified sample for sample, and segments removed: roughly 350–420 MB an hour (`claude/meetings-lossless-originals`) |
| Finish re-transcribed every real-length meeting | 12.2–12.4 s through the app per 15 minutes | Phrase-at-a-time live words (#392) |
| Two meeting checks and the finish check left a settings plist in `~/Library/Preferences` per run | ten from one day's runs | Absolute-path suites (#392) |

## 3. Measured and left, with what would change it

| Finding | Measured now | Why not now | Trigger |
| --- | --- | --- | --- |
| A fixed 250 ms wait before every Snap and Snap & Talk capture, then PNG encode, insert and a library reload on the main thread before narration starts | ≈0.35–0.5 s from press to recording (estimated from measured parts: encode 8–29 ms per megapixel, insert 3 ms, reload 12 ms) | The wait lets the toolbar leave the screen before `screencapture`; shortening it needs a native pass that proves the toolbar is not captured, which needs Screen Recording access | A native Snap pass with Screen Recording allowed, or narration that loses its first words |
| History is one `state.json`, rewritten in full on the main thread, twice per dictation; Finish decodes it four times | 0.6 ms a write and 2 ms per Finish today; 29 ms and 120 ms at 3,000 dictations and 150 meetings; 73 ms and 285 ms at 5,000 and 400 | Finish's re-read is how it confirms the transcript is durable before saying Saved; the costs are small at today's 140 items | History past 2 MB (about 1,000 dictations and 20 meetings): per-item transcript bodies and an in-memory lookup that keeps the durability check |
| The Snap library reloads every `snap.json` on the main thread after each save | 12 ms at 56 Snaps; 41 ms at 500; 140 ms at 2,000 | Small today; about 60 Snaps a month | 500 Snaps: insert the saved item instead of reloading |
| History search scans every transcript's text on the main thread | 0.7 ms today; 63 ms at 13 MB; 152 ms at 34 MB. Folded bytes and `memmem` measured 18× faster | Same | History past 10 MB |
| Starting Meetings is refused during the same 15 s after an update | as above | Meetings' admission and detection offers depend on readiness; a call rarely starts within seconds of an update | A meeting refused after an update in real use |
| `TextDelivery.capture` sets no Accessibility timeout | Suspected: a hung app could block the main thread for macOS's default timeout | Not observed; 29 ms on first use, then under a millisecond | A Dictate press that freezes Workbench |
| A model download over an existing copy keeps the previous 443 MB in a hidden candidate folder | None today | The contract keeps the previous bytes on purpose ([workbench.md](../workbench.md)) | A second re-download, or a decision to drop the old copy after a successful load |
| StageMark keeps two copies of every scene asset, and 16 renders (92 MB) from the retired apply-to-desktop | 46 MB of duplicates here | The app expects both copies; one render may be the current wallpaper | StageMark work resuming |

Idle cost is not a problem: the running Preview used 0.11 s of CPU in a minute (0.18%), its six-day average, with a 269 MB footprint and about 91 MB of Neural Engine memory for the loaded model.

## 4. The disk

Workbench's own data is 377 MB across both editions. The disk had 15 GB free because of developer output: about 40 GB of `.build` folders in `~/Developer` worktrees (23 GB untouched since 15 October), 26.7 GB in Codex worktrees, 3.1 GB of evaluation speech models the app never reads (Cohere, Parakeet v3 and unified; it uses only Parakeet v2), about 0.9 GB of developer compile caches, and 4,278 test plists from September. None of that is the app's to clear; the maintainer decides it.

## 5. Owed to the maintainer

- Allow System Audio Recording for the edition in use (System Settings › Privacy & Security › Screen & System Audio Recording), then record one real call.
- Install a Preview that carries #389, #392 and the branches above; the running Preview predates them.
- The tour and decisions in section 1.
