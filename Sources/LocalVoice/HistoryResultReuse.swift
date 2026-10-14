import AppKit

extension AppModel {
    /// An explicit reuse of the reviewed text, with the existing transient
    /// clipboard receipt. It has no dictation target or unresolved-delivery state.
    @discardableResult
    func copySavedResult(_ text: String, jobID: UUID) -> TextDelivery.Outcome {
        let outcome = HistoryResultReuse.copy(text, jobID: jobID, receipts: clipboardReceipt)
        status = outcome.message
        return outcome
    }
}

@MainActor
enum HistoryResultReuse {
    @discardableResult
    static func copy(_ text: String, jobID: UUID, receipts: ClipboardReceiptModel,
                     pasteboard: NSPasteboard = .general) -> TextDelivery.Outcome {
        let count = TextDelivery.copy(text, to: pasteboard)
        let outcome = TextDelivery.Outcome(message: count == nil ? "Could not copy the saved result." : TextDelivery.copiedMessage,
            clipboardChangeCount: count, wasPasted: false, destinationName: nil, failure: count == nil ? .copyFailed : nil)
        receipts.record(outcome: outcome, wordCount: TextRules.wordCount(text), source: .result(jobID))
        return outcome
    }
}

/// History's Copy and Copy result confirm beside the control pressed (Fit rule 7). Rows sit in a
/// lazy list and can leave it, so the page owns one confirmation and names the transcript or task
/// it belongs to. The toolbar's receipt cue is unchanged.
@MainActor
enum HistoryCopy {
    /// Copies first, then confirms by what the copy wrote, never by the status line: a write is
    /// Copied, a refused one says why, aloud too. Returns the item that now holds the confirmation
    /// or its problem; nil when there were no words and nothing was attempted, so a confirmation
    /// already showing stays with its own item.
    static func confirm(_ id: UUID, in feedback: TranscriptReviewFeedback, copy: () -> TextDelivery.Outcome?) -> UUID? {
        guard let outcome = copy() else { return nil }
        if outcome.failure == nil { feedback.finish("Copied") } else { feedback.fail(heard: outcome.message) }
        return id
    }
}
