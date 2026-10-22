# A meeting you can recognise · 22 October 2026

The maintainer, on 22 October 2026: "meeting in history is confusing as has no titles, and is hard to tell what the call was even about. It's just a log feeling experience of text. Ideally it on par with the best in class experience." He asked for the moments where getting a job done still carries friction to be made as easy as the best tools, starting there.

This record keeps what was found, what changed, the two earlier decisions it reverses and what was left, with the trigger for each.

## 1. What a saved meeting was

An audit of source and offscreen renders found that a saved meeting had no identity anywhere it is reused.

- **What was stored.** `Transcript` holds only its words, date and length. History's details hold purpose, names, tags and capture notes. There was no name and no app. The app lived only in the recording's own manifest.
- **The History row.** It showed the time, the word "Meeting" and a word count, then the first eight lines of words, which in a meeting is "You: Okay, can you hear me…". It was indistinguishable from a dictation except for its icon.
- **Home and Review.** Home's heading was "Meeting", and its earlier rows had identical headings. Review transcript opened on "Transcript". Search could not find a meeting by its app or by what was decided in it.
- **The 15 October table overstated this.** It said "App plus time; on-device name suggestions". In source, History showed only the time, and the on-device suggestions were names and tags behind Details…, read from the first 3,000 characters.
- **The gallery flattered it.** Its fixtures had hand-written names and recap-style text, not "You: … Others: …".

His own asks show the same thing recurring:

- 26 September: tag a transcript with the person and company, and search.
- 5 October, after a real call: "logical next steps in the workflow depending on the context".
- 10 October: a day of meetings pasted into an assistant was a "basically scrambled giant text blob" with no way to tell "which part of the transcript belongs to which meeting".
- 22 October: the request above.

Of 749 Workbench prompts read (7 September to 22 October), meetings are the one theme still growing: five asks between 15 and 22 October.

## 2. What the best tools do

Web research on 22 October 2026 covered Granola, Otter, Fireflies, Fathom, tl;dv, Zoom, Teams, Google Meet, Apple's call recordings, Superwhisper, MacWhisper, anarlog (formerly Hyprnote), Meetily, Jamie and Krisp. Vendor documentation is marked separately from reviews in the session's notes.

- **The record opens on a name and a short gist, never on the transcript.** Structured sections follow, and the words are one click away:
  - Otter: Summary, then Transcript.
  - Google Meet: Quick notes, then Full notes.
  - Fireflies: a one-line AI "Meeting summary".
  - anarlog: Memos, Summary, Transcript.
- **Names come from the calendar where one exists.** Without a calendar:
  - Apple: "Call with [contact]".
  - Superwhisper, MacWhisper and anarlog: a language model writes the title.
  - MacWhisper 14.6: "AI-generated titles and short summaries are now searchable".
- **Readiness varies.** Fathom is ready right after the call. Fireflies takes 5–10 minutes. Teams insights can take hours.
- **Trust comes from receipts:** Granola's source magnifier, Otter's "view in transcript", chapters with timestamps.
- **Meetings are kept apart from dictation.** Superwhisper 3.0 (15 October 2026) gave meetings "their own tab, separate from dictation history".
- **Nearly all of them write in the cloud.** anarlog offers Apple Intelligence only as an experimental provider.

## 3. What changed

**A meeting names itself on this Mac.** Once a meeting is saved, `MeetingNamer` reads it with Apple's on-device model (`MeetingNaming`). It writes three things:

- a name of a few words;
- one or two sentences on what it was about;
- up to five points: decisions, next steps with who does them, and dates.

These sit in History's details beside words they never change, marked "Written on this Mac by Apple Intelligence · your words are unchanged". Nothing leaves the Mac.

**How the model is used:**

- The model reads about 4,096 tokens, answer included, which is roughly 2,400 words. A meeting under 1,700 words is read whole.
- A longer meeting is read in parts of about 1,000 words. Each part gives its subjects and points, and the name and gist are written from those notes.
- A long meeting's points are taken from the parts themselves, spread across the meeting. Read together, the model kept to the first part's points.
- Every answer is a bounded structure. Free text with greedy sampling looped until the window was full; arrays with a maximum length stopped.
- A generic name ("Meeting", "Weekly Meeting", anything with "summary") is refused. A long meeting then falls back to the subjects its parts named most.

**When it runs:**

- It runs after Finish, ahead of anything older.
- Twenty seconds after launch it describes earlier meetings, newest first, after they learn their app from their recordings.
- It works one meeting at a time, at utility priority.
- A meeting whose words change is read again.
- A summary of words that changed while being read is not saved.
- A busy model is tried three times, then left for the next launch.
- Without Apple Intelligence it stops after one try.

**Measured on this Mac** (Apple M5, macOS 26.5.1, `--check-meeting-names-model` on synthetic transcripts):

| Meeting | Words | Time |
| --- | --- | --- |
| Product sync | 927 | 3.9–4.0 s |
| Customer discovery call | 836 | 3.0–3.6 s |
| One-to-one | 568 | 2.8–3.0 s |
| Three meetings read as one | 2,331 | 8.3 s |

The names were "Harbour Release and Northwind Escalation", "Service Desk Efficiency and Budget Allocation" and "Workload and Conference Discussion". By extrapolation, an hour of meeting (about 9,000 words) takes about half a minute.

The model misstated one figure in one point: "reduce … by 2200 tickets per month", where 2,200 was the monthly ticket count. That is why every summary is marked as written on this Mac and the words stay one click away.

**While something else listens:** naming waits before each request to the model while Dictate, Meetings or Snap & Talk is listening or transcribing. They use the Neural Engine too, and Natural cleanup uses the same model on a five-second deadline. It resumes when they end.

**What an independent review changed before merge:**

- Answers are flattened to one line before saving. A line break had made History refuse the summary, and with it every later save.
- The switch follows the value it sends. Turned back on, it had done nothing until the next Finish.
- Naming waits during capture (above).
- A follow-up's title keeps the purpose and names, and adds only a name the person typed. The written name is left out: it arrives seconds after Finish, and a follow-up prepared before it must still be found after.
- A part the model refuses is left out rather than emptying the meeting.
- A model still loading at login is tried again rather than given up on.
- Retries no longer hold up a meeting saved meanwhile.
- A summary keeps a fingerprint of the words it read.
- Generic names are refused only when every word is filler, so "Release notes for 2.6" stands.
- A summary over the limits is dropped rather than refusing the whole details file.

**Where it shows:**

- **History row.** A meeting leads with its name, then when, the app, its length and word count, then what it was about. Until it is described, it is named by its app ("Zoom meeting") and shows four lines of its words instead of eight.
- **History filter and days.** History has a Meetings filter, and its list is headed by day: Today, Yesterday, a weekday within the week, then dates.
- **Prepare follow-up… on every meeting.** A meeting or call's History row, and its context menu, open the same reviewed follow-up Meetings and Home open. Before, a past meeting needed a checkbox, Hand off…, a skill change and a cleared selection.
- **Review transcript.** It opens on the name and facts, then the gist and points over the words. ⌘F finds in the words.
- **Meetings page.** It shows the name and gist above Copy transcript once they arrive.
- **Home.** The tile's heading is the name, and its excerpt is what the meeting was about.
- **Copy.** Copying a meeting from anywhere starts with two lines: its name, then the app, time and length. Meetings pasted together then stay apart.
- **Search.** It covers the name, the app, what it was about and the points.
- **Details….** It has a Name field. A name typed there always wins over the written one, and Save keeps every detail the editor doesn't show.

**The app is recorded with each saved meeting** as a captured fact. It is shown as the meeting's source, never as a participant.

## 4. Two earlier decisions this reverses

- **Titles: "small by decision"** (15 October table, "Titles and context"). Reversed by the maintainer's request above. Calendar titles stay declined: they need a Calendar permission and the meeting rarely matches an event. This is reconsidered only if the maintainer asks for calendar names.
- **"Automatic notes are a deliberate non-goal; the handoff is the answer."** This narrows rather than reverses. What the meeting was about, and its points, are now written in the app so it can be recognised and found. Notes, action items, follow-up messages and templates stay with Prepare follow-up and the person's own agent.

**Rule 5 ("proactive features only offer").** Naming is a quality of Meetings, not an offer or an action:

- it labels the person's own saved item on this Mac;
- it sends nothing and starts nothing;
- it changes no words.

It has its one switch, Recording options' **Name meetings on this Mac**. The switch is on by default because naming is the behaviour asked for. Switching it off stops new naming and leaves existing summaries in place.

## 5. Left, with what would change it

| Idea | Why not now | Trigger |
| --- | --- | --- |
| Points with receipts (each point links to the words it came from; a point whose quote isn't found is dropped) | Needs word timings kept per turn in History and a sheet that scrolls to them | A wrong point noticed in real use, or the maintainer asking where a point came from |
| Chapters and jump-to-moment | Same timing work; parts are a natural chapter boundary | A meeting over 30 minutes reviewed in real use |
| Naming during the call, so the name is there at Finish | Apple's model would compete with live recognition for the Neural Engine during the call; untested | A real call shows the 4–30 s wait after Finish matters |
| Ask your meetings | Retrieval across meetings and citations | Repeated searches for the same topic across meetings |
| Snaps named by their app and the top line of their text; dictations showing where their words went | Separate jobs on separate stores | The next pass on History (the 22 October audit ranks both) |
| Day headers in History | Smaller value than names | History scrolling complaints |
| A meeting's summary in Copy | Copy gives the words an assistant needs; the summary is visible and selectable | An ask to paste the summary alone |
| Background throttling | Apple's model may be slowed while Workbench is not frontmost; the queue retries three times | Meetings left unnamed after real use |

**Going back to an earlier build:** 2.6.0 and earlier read the details file and ignore the new fields. Any History write from them, even ticking a checkbox, rewrites it without them. Summaries and apps come back on the next launch of this build; a name typed in Details… does not.

Native acceptance is owed:

- a real meeting named on the installed Preview, with Apple Intelligence on;
- the same with it off;
- an earlier meeting named after an update;
- ⌘F's find bar in Review transcript: Return finds the next match and Escape closes the bar, not the sheet.

Synthetic checks: `--check-history-library` (81 meeting-name checks, day headings and every review finding included: details, headings, search, the Meetings filter, Copy, cleaning, parts, the route with a stand-in model and the queue). Renders: the gallery's `page-history-state-meetings`, `page-history-transcript-review-named`, `page-meeting-state-completed-named` and `page-home-state-results`.
