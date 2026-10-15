# Guide, handbook and README say what the release train does

Branch `claude/public-pages-match-train`, stacked on the 15 October release train (`claude/train-1015`, on top of `main` at `edc15df`). Refs #382. Copy and checks only: no Swift source, app surface or surface registry entry changed, so there are no gallery renders. The checks below ran on the branch's final source.

## What changed

1. **The guide's phone-share section names the entire-display route.** After "press Present and share the Workbench window in your call." it now says "To include Draw, the Timer or a floating persona, share your entire display instead.", matching Present's footer from the presenting-polish branch. Can't see your phone?'s Help online opens this section. The presenting-polish record left this line unchanged; this branch carries it.
2. **The guide's Dictate tile says the words are copied when live insertion stops.** "Moving or editing the field stops live insertion, and the complete words are copied, ready to paste." Once its writer has stopped, live delivery copies the words as dictated whatever Restore clipboard says.
3. **The handbook no longer lists Read as a direct entry point.** The craft card's Start clearly reads "Dictate, Draw and Present remain direct entry points." Nothing was added in Read's place.
4. **The README's credits stop offering a retired download.** Pocket TTS keeps its CC BY 4.0 credit and now says it powered the retired Read voices and that current builds neither include nor download it. The Apple line names AppKit, SwiftUI and AVFoundation, without installed macOS voices: speech synthesis appears only in Persona's voice check mode.

The Timer sentence the first proposal offered for Draw's tile was left out; the guide never says the display sleeps.

## Where the checks live

The site checks are in `site/tests/copy.test.mjs` and read only pages inside `site/`. Vercel builds from `site/` alone and runs the site tests before `build.mjs`, so a site test that read `README.md` or `Sources/` would fail there and stop a production deploy. The README check is in `scripts/test-read-retirement.py`, which the harnesses phase runs.

## Checks

| Check | Result | Fails without this change? |
| --- | --- | --- |
| `node --test site/tests/*.test.mjs` (from the repository root, as CI runs it) | 26 tests passed | Yes. With the train's `site/guide/index.html` and `site/handbook/index.html` put back, the three new tests fail and the other 23 pass. |
| The same tests and `node build.mjs`, run in a scratch copy holding only the tracked `site/` files | 26 tests passed; the site built for production v2.5.0, and the built guide and handbook carry the three new sentences | |
| `python3 scripts/test-read-retirement.py` | 6 tests passed | Yes. With the train's `README.md`, `test_readme_credits_describe_no_reading_voice_download` fails on "Neural voices". |
| `grep -nE "Neural voices\|Dictate, Read," README.md site/handbook/index.html` | No matches | |
| `bash scripts/test.sh harnesses` | Passed (exit 0) | |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passed | |

## Not verified

The public site was not deployed; the live guide and handbook change only at the next `scripts/deploy-site.sh` run. The pages were checked as built HTML, not viewed in a browser. Other internal documents that still describe Read as a tool (historical design prompts, research and the utility comparison) were left as they are.
