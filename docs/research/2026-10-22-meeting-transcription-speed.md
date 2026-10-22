# A meeting's transcript at Finish · 22 October 2026

The maintainer's ask: when a meeting finishes, its transcript should already be complete, so opening Meetings and pressing Copy transcript is the whole job; accuracy and speed both matter. This record holds what made Finish slow, what changed, the measurements behind each value, and what was deliberately not built, with the trigger that would bring it back.

**Status:** source change with synthetic measurements on one Mac (Apple M5, 16 GB, macOS 26.5.1, cached Parakeet v2 through FluidAudio 0.15.6). No real call has been recorded through it; that remains the acceptance owed under #280.

## 1. What Finish did

Finish saves the live words only when the live pass is *complete*: both sources confirmed to the end of their saved tracks, with nothing skipped (`MeetingRecovery.complete`). Otherwise `MeetingProcessor` transcribes the saved originals again: the mixed timeline in ten-minute segments, then, with both sources, every utterance of each track a second time for the You and Others labels.

The live pass confirmed fixed eight-second ranges, read with two seconds of context on each side, and matched the last confirmed word against the next reading. Parakeet hears that context a little differently each time, and a single unmatched boundary marks the whole pass incomplete (#280's degrade-don't-die rule, which kept live words going but sent Finish back to the originals).

Measured on seven synthetic 15-minute two-person meetings (below), **today's live pass was incomplete in all seven, with 24 to 49 unmatched boundaries each.** Every real-length meeting therefore waited for the full second transcription after Finish: **12.6 to 25.7 s per 15 minutes of meeting** on this Mac, roughly one to three and a half minutes for a one- to two-hour meeting, before Copy transcript appeared.

## 2. What Parakeet does that mattered

Two behaviours of Parakeet v2 under FluidAudio 0.15.6, found while measuring, shaped the change. Neither is in its documentation.

1. **A word's timing absorbs the silence after it.** A sentence's last word routinely ends where the next sound starts ("companions," 49.72–50.52 s over a 0.4 s pause). Gaps between word timings therefore do not show pauses; the audio's loudness does.
2. **A reading can come back empty over clear speech.** The decoder starts each reading from a fresh state. Traced in an instrumented copy of the decoder: at the first word the joint network chose between blank and the first token at p ≈ 0.5. When it chose blank, it chose blank for every later frame with p = 1.00, over ten seconds of plain speech. The same audio read 20 samples longer or shorter flips the outcome. It is far more likely after a long silence. One stretch of a synthetic meeting read with 3 s of silence first came back empty at 8 of 11 lengths, and at 0 of 11 when the reading started 0.3 s or 1 s before the speech. In the 10-minute meeting, 1 reading in 100 came back empty before this change. A second reading with 0.16 s of silence after the audio recovered all 18 empty decodes of the worst stretch. This affects any single-window reading, Dictate's saved-recording path included.

## 3. The change

**Live words are confirmed a phrase at a time** (`LiveVoiceWindow`). Each reading covers one source from the last cut to the newest audio, after about two seconds of new audio. A cut goes only where that source is quiet: MeetingConversation's loudness rule (30 ms frames over an adaptive floor, which digital silence no longer drags down), with the model's own words counting as sound from 0.1 s before each word's start to 0.2 s after it. Every confirmed word therefore comes from one reading that had the audio on both sides of it, and there is no boundary to match against the next reading. In order:

| Rule | Value | Why |
| --- | --- | --- |
| A phrase ends at quiet after its last word | 1.2 s, cut in its middle but a second clear of the reading's end | In a noisy room speech reads as quiet, and a word the reading's end cut short may not be heard yet (§6) |
| From this length, cut at the latest pause after the first word | 10 s, pause ≥ 0.3 s, not in the last second | Longer phrases give the model context; the last second can still change |
| The longest phrase | 14.5 s, at that pause or else the widest quiet in its second half | One model window, with room for the empty-reading retry's padding |
| A word belongs to the phrase it **starts** in | | Its end may be stretched over the pause (§2.1) |
| The same word heard again at the very start of the next reading, overlapping the last confirmed one, is kept once | within 0.1 s of the reading's start | The cut fell in its soft start; a repeat said later stays |
| A short gap in a source is silence in the window | under 0.1 s | The original track is padded the same way, so the pass ends exactly where the track does (§6) |
| A reading starts before the first sound after the cut | 1 s | Long leading silence multiplies empty readings (§2.2); a second keeps a soft first word that reads as quiet |
| A reading with no words over sound cuts nothing | | The next reading, a different length, gets another chance |
| …and its first word long after the sound starts cuts nothing | 1.0 s | It probably missed the phrase's start |
| A quiet reading with no words is passed over | after 4 s | Keeps silence from piling up in later readings |
| A phrase's last reading that hears nothing over sound, or starts late, is read again 80 ms out of step | at Finish | It has no later reading to correct it; the fuller of the two is kept. Its first 80 ms are dropped only when quiet, otherwise 80 ms of silence goes before it |
| Still doubtful over speech-level sound: Dictate's pass is incomplete | Dictate only | Its saved recording is one short reading; for a meeting it would be the whole meeting every time a call ends on a cough or typing |
| A whole window of sound with no words is passed over | at 14.5 s | Music, typing or another language; the saved-audio path would read it with the same model |

**An empty reading is read once more** with 0.16 s of silence after it (`EmptyReading`), when its audio held at least 0.3 s of sound louder than -40 dBFS and still fits one window. Live readings and saved recordings of one window (Dictate's saved path, each meeting utterance in the fallback) both use it. It costs nothing unless a reading comes back empty.

**The live journal** is saved at most twice a minute while words arrive, and always when the pass ends. Every save rewrites all the words so far, and only a complete journal is ever read back (`MeetingRecovery`, Dictate). Saving per phrase would have rewritten megabytes a second near the end of a two-hour meeting.

Unchanged: the fallback's own steps (it gains only `EmptyReading` for each utterance), the 60 s backlog rule, echo removal, turns, the saved formats and the History commit.

## 4. Measurements

**Method.** `meetbench`, kept outside the repository at `~/Developer/wb-models-eval/meeting-bench`, builds seven meetings of about 15 minutes from LibriSpeech test-clean and test-other. Each has a microphone lane ("You", two readers) and an app lane ("Others", three readers). Turns alternate with 0.3–1.6 s gaps; 12% overlap by up to a second; 5% are followed by 4–15 s of silence; there is a -58 dBFS noise floor. *Tight* runs utterances together with 0.02–0.2 s gaps. *Echo* adds the app lane to the microphone at -24 dB and 40 ms late, as laptop speakers do. It replays the live pass in 100 ms steps against the real model, with main's window compiled from a frozen copy and this change's from the worktree, and scores what each meeting would save against the readers' text. Word error rates use FluidAudio's English normaliser. LibriSpeech is read speech, cleaner than a call; the comparison is between paths over the same audio, not a claim about calls.

| Meeting | Today: live complete? | Today: wait after Finish | Now: complete? / wait | You, today → now | Others, today → now |
| --- | --- | --- | --- | --- | --- |
| clean 1 | no (42 unmatched) | 12.6 s | yes / 0.11 s | 1.51% → 1.27% | 3.64% → 3.64% |
| clean 2 | no (24) | 13.0 s | yes / 0.10 s | 2.24% → 2.47% | 2.64% → 2.64% |
| clean 3 | no (28) | 14.9 s | yes / 0.11 s | 0.97% → 0.60% | 1.87% → 1.35% |
| other 1 | no (39) | 17.2 s | yes / 0.10 s | 2.53% → 1.82% | 2.66% → 3.54% |
| other 2 | no (30) | 25.7 s | yes / 0.11 s | 2.95% → 2.81% | 2.46% → 1.64% |
| clean, tight | no (40) | 17.1 s | yes / 0.10 s | 1.05% → 1.44% | 1.53% → 1.53% |
| clean, echo | no (49) | 17.9 s | yes / 0.12 s | 7.16% → 3.55% * | 1.32% → 0.55% |

*Today* is what each meeting saves today, the fallback's per-speaker utterance pass; the wait is the fallback's recognition time alone. *Now* is the saved live conversation; the wait is the last readings' flush. *With echo, the microphone column compares live paths (word-level echo removal on both), because the benchmark's fallback replica does not run the utterance-level echo check.

Over the six meetings without echo (13,666 words), the saved text's word error rate goes from **2.20% to 2.09%**; today's unused live words were 2.52%. Lane by lane it is mixed, within a few words either way, so the honest summary is accuracy held while the wait went away; with the microphone hearing the call, the saved words improve markedly. The phrase pass reads the audio less often (about 910 readings per 15-minute meeting against 1,130) and reads an empty decode again 4 to 16 times per meeting.

**Dictate** shares the live pass and keeps its live words when the pass is complete. 120 synthetic dictations from test-clean (one reader, one to six sentences, 51 minutes) and 80 from test-other (29 minutes):

| | Live pass complete | Saved word error rate | Always reading the recording again | Worst wait after Stop |
| --- | --- | --- | --- | --- |
| clean, today | 65 of 120 | 1.92% | 1.55% | 0.47 s |
| clean, now | 120 of 120 | 1.56% | 1.56% | 0.08 s |
| other, today | 54 of 80 | 3.63% | 3.47% | 1.03 s |
| other, now | 80 of 80 | 3.63% | 3.47% | 0.09 s |

Dictate's saved words now match always reading the recording again on clean speech and stay where they were on the harder set, with no reading after Stop.

Values measured and not taken: starting each reading 0.3 s before the first sound (2.08% over the six meetings, level, but the echo meeting's microphone 7.03% against 4.13%, and a soft first word reading as quiet would fall outside the reading); a one-second lead-in of earlier audio before each reading (fewer empty readings but more doubled words at cuts), two seconds (worse), placing the cut just before the next heard word instead of counting heard words as sound (lost soft last words), and cuts in gaps between word timings (doubled the word at 18 cuts; §2.1).

**Through the app.** `--check-meeting-finish` played two of these meetings (clean 1, 943 s; other 2, 902 s) at 48 kHz and four times real time through the meeting owner, once built from main with only the check added and once from this change. Finish to a saved transcript took **12.15 s and 12.43 s today**, re-transcribing after the first unmatched boundary at 56 s and 200 s, and **0.51 s and 0.53 s now**, with the live words. The saved words' error rate over both speakers went from 2.67% to 2.51% and from 2.92% to 2.82%. Today's re-transcription time grows with the meeting; the live flush does not. The check's normaliser is plainer than the benchmark's, so its rates read a little higher.

## 5. Declined or deferred

| Idea | Why not now | Trigger to revisit |
| --- | --- | --- |
| Transcribe the saved originals in the background during the meeting, so the fallback is also ready at Finish | Doubles recognition during every meeting; the live pass now completes on every measured meeting | A real meeting's journal notes a backlog or another incomplete pass, or Macs slower than M1 join |
| At Finish, transcribe only the stretch a backlog skipped, not the whole recording | Same trigger; needs the journal to record skipped ranges and the processor to splice them | A "fell behind" note on a real meeting |
| Carry the decoder's state from one phrase to the next for language context | FluidAudio's state also carries a frame offset (`timeJump`) that would skip audio at the next reading's start; it can't be reset from outside 0.15.6 | A FluidAudio release that exposes a clean continuation state, measured with this benchmark |
| Report the empty-reading behaviour to FluidAudio | Sending it outside the project needs its own authority | The maintainer's go-ahead; the instrumented trace is reproducible from §2 |
| Use the crash-interrupted journal's confirmed words in recovery | Recovery after a crash is rare and still correct, only slower | A real meeting recovered after a crash |
| Cut at every 0.6 s pause, as the saved-audio path does | Shorter phrases gave the model less context and no measured gain in early runs | A real-call measurement that shows phrases too long for live reading |

## 6. Independent review

An independent reviewer read the change and drove a copy of the window through a harness with a stand-in model that stretches word ends and drops a reading's cut-off last word, at 8 to 96 kHz. It confirmed no range or index failure, frames aligned after each discard, every finishing reading making progress, a final confirmed time equal to the track's end, readings within the model's input limit and identities kept from provisional to confirmed. Its findings, all fixed in this change:

- In a noisy room the phrase-ending cut could fall after a word the reading's end had cut short, losing it (up to 29 of 420 words in its harshest scenario); the cut now stays a second clear of the reading's end.
- A phrase's last reading had no second chance; it is now read again 80 ms later in when it heard nothing over sound or started late.
- The duplicate rule could drop a genuine repeat ("no … no") inside a stretched word; it now applies only at the very start of a reading.
- A word the model timed in a short final reading's padding was never confirmed.
- Found before this change and blocking it: the original track fills source gaps over 25 ms with silence but the live window spliced gaps under 0.1 s without it, so the pass ended short of the track and Finish quietly transcribed everything again. The window now pads them too.
- Absurd word times could trap; they are refused like other invalid timing. The latest-pause rule no longer takes the quiet before a phrase's first word.

A second round re-ran every scenario against the fixes: all resolved, with a word lost in 0 of 582, 344 and 420 in the noisy-room scenarios, every word once at 8 to 96 kHz and the final confirmed time exact after 30 ms to 2 s gaps and multi-window queues. It found two more, both fixed: the last reading's second read dropped its first 80 ms even when a word started there (it now adds silence before it instead unless those 80 ms are quiet), and padded gap silence pulled the adaptive floor to -180 dB, so a fan at -45 dBFS read as speech for about 70 s (digital silence no longer moves the floor). It argued for leaving a doubtful last reading to the saved audio everywhere; Dictate does, Meetings does not, for the cost reason above.

Considered and left: surfacing the count of cuts made without a pause. Nothing reads it yet; the benchmark reports it (3 to 13 per 15-minute meeting, most in the tight one).

## 7. Owed

- On the installed Preview, a real two-sided call: Finish shows Transcript saved within a second or two, with live words used (the manifest's `liveText`). That needs System Audio Recording allowed for Preview, as the [15 October record](2026-10-15-meetings-category.md) says.
- `--check-meeting-capture-native` from the signed app now expects a complete live pass on its two-voice fixture, as before.
