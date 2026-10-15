import Foundation

@MainActor
enum PromptInsertionChecks {
    private final class Field {
        var value = "before TARGET after"
        var selection = NSRange(location: 7, length: 6)
        var readable = true, permitted = true, cancelled = false, progressive = true, refuses = false
        var writes: [String] = [], pastes = 0
        var onCapability: (() -> Void)?
        var afterWrite: (() -> Void)?
        var snapshot: PromptInsertionRunner.Snapshot { .init(value: value, selection: selection) }
        var driver: PromptInsertionRunner.Driver {
            .init(cancelled: { self.cancelled || Task.isCancelled }, permitted: { self.permitted },
                  snapshot: { self.readable ? self.snapshot : nil },
                  supportsProgressive: { self.onCapability?(); return self.progressive },
                  insert: { chunk in
                      self.writes.append(chunk)
                      guard !self.refuses, let range = Range(self.selection, in: self.value) else { return false }
                      self.value.replaceSubrange(range, with: chunk)
                      self.selection = NSRange(location: self.selection.location + chunk.utf16.count, length: 0)
                      return true
                  }, waitForConfirmation: { self.afterWrite?(); try Task.checkCancellation() },
                  paste: { _, expected in self.pastes += 1; self.value = expected.value; self.selection = expected.selection; return "pasted" })
        }
        func run(_ text: String = "hello") async -> String {
            await PromptInsertionRunner.run(text: text, destination: snapshot, driver: driver)
        }
    }
    static func run() async throws {
        var count = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw VoiceError.message("Prompt insertion: " + name) }
            count += 1
        }
        let unicode = "👨‍👩‍👧‍👦 café e\u{301}\n第二行"
        let field = Field()
        let result = await field.run(unicode)
        try check(field.value == "before \(unicode) after" && result == "Prompt inserted. Nothing was submitted.", "literal Unicode, newlines and selected-range replacement")
        try check(field.writes.joined() == unicode && field.writes.first!.count <= 2 && field.writes.allSatisfy { $0.count <= 256 } && field.pastes == 0,
                  "progressive writes use whole Characters with no fallback replay")
        // A long prompt: a two-Character probe, then confirmed writes that double to 256 Characters,
        // cut across emoji sequences, combining marks, CJK and newlines.
        let long = String(String(repeating: unicode, count: 200).prefix(2_000))
        let longField = Field()
        let longResult = await longField.run(long)
        try check(longField.value == "before \(long) after" && longResult == "Prompt inserted. Nothing was submitted." && longField.pastes == 0
                  && longField.writes.count <= 14 && longField.writes.first!.count <= 2 && longField.writes.allSatisfy { $0.count <= 256 }
                  && longField.writes.map(\.count).reduce(0, +) == long.count, "a 2,000-Character prompt lands exactly in at most 14 confirmed writes")
        // At the Library's limit the size stays at 256 for every later write: 7 growing writes, then 195.
        let longest = String(String(repeating: unicode, count: DemoResource.promptCharacterLimit / 10).prefix(DemoResource.promptCharacterLimit))
        let longestField = Field()
        let longestResult = await longestField.run(longest)
        try check(longestField.value == "before \(longest) after" && longestResult == "Prompt inserted. Nothing was submitted." && longestField.pastes == 0
                  && longestField.writes.count == 202 && longestField.writes.first!.count <= 2 && longestField.writes.allSatisfy { $0.count <= 256 },
                  "a prompt at the 50,000-Character Library limit lands exactly in 202 confirmed writes of at most 256")
        var confirmations = 0
        let stopsSecond = Field(); stopsSecond.afterWrite = { confirmations += 1; if confirmations == 2 { stopsSecond.cancelled = true } }
        let stopsResult = await stopsSecond.run(long)
        try check(stopsSecond.writes.count == 2 && stopsSecond.pastes == 0 && stopsResult.contains("could not be confirmed")
                  && stopsResult.contains("nothing was replayed"), "Escape during the second write stops there, with nothing replayed")
        let fallback = Field(); fallback.progressive = false
        let fallbackResult = await fallback.run(unicode)
        try check(fallbackResult == "pasted" && fallback.pastes == 1 && fallback.writes.isEmpty && fallback.value == field.value, "unsupported progressive write uses exactly one validated paste")
        let invalid = Field(); invalid.progressive = false
        _ = await invalid.run(String(repeating: "x", count: 50_001))
        try check(invalid.pastes == 0 && invalid.writes.isEmpty, "oversized prompt cannot bypass bounds through fallback")
        invalid.selection = NSRange(location: 500, length: 1)
        _ = await invalid.run()
        try check(invalid.pastes == 0 && invalid.writes.isEmpty, "invalid selection cannot fall back to paste")
        let boundary = Field(); boundary.progressive = false
        boundary.onCapability = { boundary.selection.location = 0 }
        _ = await boundary.run()
        try check(boundary.pastes == 0, "selection changes at the capability boundary stop fallback")
        let editing = Field(); editing.progressive = false
        editing.onCapability = { editing.permitted = false }
        _ = await editing.run()
        try check(editing.pastes == 0, "shortcut editing begins before fallback and blocks delivery")
        let cancelledFallback = Field(); cancelledFallback.progressive = false
        cancelledFallback.onCapability = { cancelledFallback.cancelled = true }
        _ = await cancelledFallback.run()
        try check(cancelledFallback.pastes == 0, "cancellation before fallback prevents any delivery")
        let unreadable = Field(); unreadable.readable = false
        _ = await unreadable.run()
        try check(unreadable.writes.isEmpty && unreadable.pastes == 0, "lost focus, permission, secure or unreadable field cannot receive text")
        let lost = Field(); lost.afterWrite = { lost.readable = false }
        let lostResult = await lost.run()
        try check(lost.writes.count == 1 && lost.pastes == 0 && lostResult.contains("could not be confirmed"), "focus loss after a write stops without replay")
        let changed = Field(); changed.afterWrite = { changed.value += "manual edit" }
        _ = await changed.run()
        try check(changed.writes.count == 1 && changed.pastes == 0, "manual field changes stop after the first unconfirmed write")
        let partial = Field(); partial.afterWrite = { partial.cancelled = true }
        _ = await partial.run()
        try check(partial.writes.count == 1 && partial.pastes == 0, "Escape after a chunk does not replay the full prompt")
        let practice = Field(); practice.afterWrite = { practice.permitted = false }
        _ = await practice.run()
        try check(practice.writes.count == 1 && practice.pastes == 0, "shortcut practice stops progressive insertion")
        let refused = Field(); refused.refuses = true
        _ = await refused.run()
        try check(refused.writes.count == 1 && refused.pastes == 0 && refused.value == "before TARGET after", "failed write never triggers a full paste")
        let queued = Field(); queued.progressive = false
        let task = Task { await queued.run() }; task.cancel()
        _ = await task.value
        try check(queued.writes.isEmpty && queued.pastes == 0, "cancelling a queued delivery Task prevents its first write")

        // The picker has closed by the time a delivery ends, so any ending but a confirmed insertion
        // shows as the toolbar's delivery cue, through the receipt owner dictation uses (#159).
        let receipts = ClipboardReceiptModel(clipboardChangeCount: { 40 }, now: { 0 }, automaticallySchedules: false)
        func cue(_ result: String, paste: TextDelivery.Outcome? = nil) {
            receipts.clear()
            let attempt = PromptAttempt(prompt: "Synthetic prompt", destination: "Notes", result: result)
            if let outcome = PromptInsertion.cue(for: attempt, paste: paste) { receipts.record(outcome: outcome, wordCount: 2, source: .prompt) }
        }
        cue(await Field().run())
        try check(receipts.receipt == nil && !receipts.isHUDVisible, "a confirmed insertion stays quiet")
        cue("pasted", paste: .init(message: "Pasted into Notes.", clipboardChangeCount: nil, wasPasted: true, destinationName: "Notes", pasteWasAttempted: true))
        try check(!receipts.isHUDVisible, "a confirmed paste stays quiet")
        let refusing = Field(); refusing.refuses = true
        let vanishing = Field(); vanishing.afterWrite = { vanishing.readable = false }
        let escaped = Field(); escaped.afterWrite = { escaped.cancelled = true }
        for (name, stopped) in [("refused", refusing), ("unconfirmed", vanishing), ("partial", escaped)] {
            let result = await stopped.run()
            cue(result)
            let receipt = receipts.receipt
            try check(receipts.isHUDVisible && receipt?.title == "Delivery stopped" && receipt?.source == .prompt
                      && receipt?.detail == PromptAttempt(prompt: "", destination: "", result: result).summary && result.hasPrefix(receipt?.detail.dropLast() ?? "-")
                      && receipt?.isClipboardCurrent == false && receipt?.canSuggestPaste == false && receipt?.clipboardChangeCount == nil
                      && stopped.writes.count == 1 && stopped.pastes == 0, "a \(name) insertion shows Delivery stopped with its reason, claims no clipboard and replays nothing")
        }
        receipts.refreshClipboardOwnership()
        try check(receipts.receipt?.isClipboardCurrent == false, "a stopped cue never becomes a clipboard shelf")
        cue("Paste sent.", paste: .init(message: "Paste sent.", clipboardChangeCount: 40, wasPasted: false, destinationName: "Notes",
                                         failure: .pasteUnconfirmed, pasteWasAttempted: true))
        try check(receipts.receipt?.title == "Paste unconfirmed" && receipts.receipt?.detail.contains("prompt") == true
                  && receipts.receipt?.detail.contains("transcript") == false && receipts.receipt?.canSuggestPaste == false,
                  "an unconfirmed paste fallback names the prompt and never suggests pasting again")
        cue("Copied.", paste: .init(message: "Copied. " + TextDelivery.copiedDetail(.focusChanged), clipboardChangeCount: 40, wasPasted: false,
                                     destinationName: nil, failure: .focusChanged))
        try check(receipts.receipt?.title == "Copied" && receipts.receipt?.detail.contains("⌘V") == true && receipts.receipt?.source == .prompt
                  && receipts.receipt?.isClipboardCurrent == true, "a fallback that left the prompt copied says so")
        cue("Stopped.", paste: .init(message: "Delivery stopped before pasting. The transcript remains copied.", clipboardChangeCount: 40,
                                      wasPasted: false, destinationName: nil, failure: .cancelled))
        try check(receipts.receipt?.title == "Delivery stopped" && receipts.receipt?.detail.contains("prompt") == true
                  && receipts.receipt?.detail.contains("transcript") == false, "a stopped paste fallback speaks of the prompt")

        // After the picker closes, typing waits for the frozen field to be in front again.
        let start = Date(timeIntervalSince1970: 1_000)
        var clock = start, polls = 0, pauses = 0
        func pause() async { pauses += 1; clock.addTimeInterval(0.02) }
        let immediate = await PromptFieldReturn.wait(until: { polls += 1; return true }, now: { clock }, pause: pause)
        try check(immediate && polls == 1 && pauses == 0, "a field already in front is typed into at once")
        polls = 0
        let returned = await PromptFieldReturn.wait(until: { polls += 1; return polls > 12 }, now: { clock }, pause: pause)
        try check(returned && pauses == 12 && clock.timeIntervalSince(start) < 0.3,
                  "typing waits while the field comes back, however long that takes within the limit")
        clock = start; pauses = 0
        let never = await PromptFieldReturn.wait(until: { false }, now: { clock }, pause: pause)
        try check(!never && abs(clock.timeIntervalSince(start) - PromptFieldReturn.limit) < 0.03,
                  "after about a second it stops waiting and leaves the runner's check to refuse")
        clock = start; pauses = 0
        let stopped = Task { await PromptFieldReturn.wait(until: { false }, now: { clock }, pause: pause) }
        stopped.cancel()
        try check(await stopped.value == false && pauses == 0, "Escape or Stop ends the wait at once")
        print("PROMPT_INSERTION_CHECKS_OK: \(count) checks passed")
    }
}
