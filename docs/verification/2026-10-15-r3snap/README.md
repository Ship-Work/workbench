# Snap: caption starts selected, tags never block Save, editor and page say what they do

Branch `claude/snap-caption-tags-page`, stacked on the 15 October release train (`claude/train-1015`, on top of `main` at `edc15df`). Refs #359. The checks below ran on the branch's final source. Synthetic data only: the checks' generated images, temporary Snap stores and isolated preferences, and the surface gallery's isolated home. No installed app, real window, keyboard, clipboard or privacy setting was used.

## What changed

1. **A new text box starts with its caption selected.** The editor's Text button now raises a one-shot request. The inspector meets it with a small AppKit hook behind the existing TextEditor: the hook finds the caption's text view, makes it first responder and selects all of "Your text", so the first keystroke replaces it. This works for the first box, whose field is only just appearing, and for Text pressed while another caption has focus. Only the button raises the request. The gallery and checks call `addText()` directly, so their renders do not change. Undo coalescing is unchanged: typing over the selection is one step, and one Undo returns "Your text". The canvas's click-to-place text branch was removed, since nothing ever set the Text tool. `addText()` also loses its unused point parameter.
2. **The Pen, Arrow and Box slider says what it changes.** Both line-width sliders now carry a caption in the same form as Text size: "Line width · N px", in the pixels `SnapRendering.draw` strokes. One is for a selected mark and one is for the chosen tool. The VoiceOver label and the slider's one-step Undo are unchanged.
3. **Search says it finds image text.** The field reads "Search titles, notes, tags and image text". An empty result reads "Try another title, note, tag or words shown in the image. Your selection is kept." The handbook's `snap-history` effect says "Search titles, notes, tags and image text". `reviewedOn` and `implementationRevision` are unchanged.
4. **A tagged card keeps its row level.** Once any visible Snap has tags, every card holds the tag line, just as the title already holds two lines. An untagged card holds a single space, which is hidden from VoiceOver. An empty `Text` with `reservesSpace` measured 1 pt taller than a caption line, so it left the row 2 px ragged at 2x. A grid with no tagged Snap still shows no extra line.
5. **Empty tags: a guard, not a fix.** The brief said a trailing comma, or a cleared Tags field, makes Save fail as a damaged record. That holds only for a direct `SnapModel.saveDraft` call. The editor's Save (`CaptureImagePreview.saveEditing`) already trims tags, drops empty ones and sorts them before calling `saveDraft`, and it is the only production caller. So a person cannot reach this failure, and `saveDraft` is unchanged. A new check saves `["pricing", ""]` and `[""]` through the real Save and expects `["pricing"]` and no tags. It passes on the train and guards that path.
6. **Independent review follow-ups.** Text pressed at the 1,000-mark limit adds no box, but it still raised the caption request; the request then waited for the next text box selected, took focus from the canvas and selected its caption, so Delete edited the caption instead of removing the mark. The request is now raised only when the new box lands. The grid also reads its filtered Snaps once for both the tag line and the cards, so a search keystroke filters the library twice per render instead of three times. Layout is unchanged.

## Renders

`before/` and `after/` use the same filenames, in light and dark:

- `page-snap-default-*` and `page-snap-narrow-*` come from `--render-surfaces`. Before is `main`, after is this branch. They show the new search placeholder and the level grid. In the gallery fixture only the first Snap is tagged.
- `image-workspace-arrow-*` is a new shot in the image workspace check's output: an arrow selected on the check's 1,600 × 1,000 image. It shows "Line width · 6 px". The before render ran the same check against the train's `SnapEditorView`, so it has no caption. The 13 px figure in the brief belongs to the gallery's 2,880 × 1,800 fixture. That gallery shot belongs to another stream and was not added here.

The caption selection has no visible render. Its evidence is the check below.

## Checks

| Check | Result | Fails on the train without this change? |
| --- | --- | --- |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passed | |
| `.build/debug/LocalVoice --check-image-workspace` | `IMAGE_WORKSPACE_CHECKS_OK`, 89 checks | Yes, for the caption checks. Built with the train's `SnapEditorView.swift` (no hook), the run stops at "Text puts the new caption's field first with its whole caption selected". The two empty-tag checks pass on the train, as expected for a guard. Before the review fix, the run stopped at "Text refused at the mark limit leaves no caption request behind". |
| `.build/debug/LocalVoice --check-image-workspace DIR` (renders) | `image-workspace-{light,dark}`, `-crop`, `-small` and `image-preview-pending-draft` are pixel-identical to the train-view run. `image-workspace-arrow-*` differs only in the inspector. `snap-pending-draft-*` differs only in the placeholder and the cards' capture times. | |
| `.build/debug/LocalVoice --render-surfaces` | 360 renders, 162 entries, 0 flags. `page-snap-workspace-{text,crop,compact}` and the `page-snap-preview-*` shots are pixel-identical to `main`'s. | |
| `--render-surfaces` again after the review fixes | All renders written. `page-snap-default-*` and `page-snap-narrow-*` are pixel-identical to `after/`, and `card-probe.py` reads LEVEL in all four. The workspace and preview shots are still identical to `main`'s. The run exited 1 at the floating toolbar's resting-pointer step against the real display ("A copied cue appearing under a stationary pointer holds its time"). That code is outside this branch, and the independent review hit the same environment failure. | |
| `card-probe.py` on `page-snap-{default,narrow}-{light,dark}` | After: all three cards' Copy rows sit at 921–960 px and their bottoms at 984 px, in all four. The tagged card's own height is unchanged. | Yes. On `main`'s renders the tagged card's Copy row and bottom sit 42 px below the others (921–960 vs 879–918; 984 vs 942). With an empty `Text` instead of a space, the untagged cards still ended 2 px lower. |
| `.build/debug/LocalVoice --check-history-library` | 87 + 63 checks, including image-text search | |
| `.build/debug/LocalVoice --check-snap-capture` | 182 checks | |
| `bash scripts/test-snap.sh` | 195 checks, exit 0 | |
| `node --test site/tests/handbook.test.mjs` | 3 passed | |
| `python3 scripts/check-surfaces.py` | 688 entries OK, no registry diff | |
| `grep` for "notes and tags", "note or tag", `tool = .text` and `.tool == .text` in Sources | No matches | |

The caption check runs in the live editor panel, which is never ordered in on screen. It calls the Text button's method and lets the panel settle. It then asserts four things: the panel's first responder is a text view (not a field editor) holding "Your text" with (0, 9) selected; `insertText("Login", replacementRange:)` makes the mark's caption "Login"; one Undo returns "Your text" with the box still selected; and pressing Text again while that caption has focus selects the new box's whole caption, so typing replaces only that caption. SwiftUI keeps the "Text on image" accessibility label on its own element, and the underlying `NSTextView` reports none. The check therefore identifies the field by the caption it edits, not by its label. A fifth step fills the draft to the 1,000-mark limit, presses Text and asserts that no box was added and no caption request is left behind.

## Not verified natively

These need a signed Preview, checked by the integration owner or Ethan:

- **Caption selection.** In Snap › Edit…, choose Text with nothing selected and type: the words should replace "Your text". Choose Text again while typing in a caption: the new box's caption should be selected. Also check one input-method language (for example Pinyin), ⌘Z after typing, and VoiceOver reading the field.
- **Line width.** Choose Pen, drag the slider and check that the px readout tracks the next stroke's width.
- **Grid.** Tag one Snap and check that its row's Copy buttons line up in a real window.
