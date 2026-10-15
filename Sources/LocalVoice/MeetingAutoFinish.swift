import Foundation

/// Call activity is process metadata, never an inference from silent samples.
/// Unknown observations and audio-route recovery revoke a pending finish.
struct MeetingAutoFinish {
    enum Activity { case active, inactive, unknown }
    private var observedActive = false
    private var inactiveSince: TimeInterval?
    private var keptOpen = false
    var inactivityDelay: TimeInterval = 20
    var grace: TimeInterval = 10

    mutating func keepRecording() { keptOpen = true; inactiveSince = nil }

    /// A non-nil value is a visible countdown; zero authorizes this session's
    /// normal Finish path. Pause/reconnect require fresh active-call evidence.
    mutating func observe(_ activity: Activity, now: TimeInterval, suspended: Bool) -> Int? {
        guard !keptOpen else { return nil }
        guard !suspended else { observedActive = false; inactiveSince = nil; return nil }
        switch activity {
        case .active: observedActive = true; inactiveSince = nil; return nil
        case .unknown: observedActive = false; inactiveSince = nil; return nil
        case .inactive:
            guard observedActive else { return nil }
            if inactiveSince == nil { inactiveSince = now }
            let quietFor = max(0, now - inactiveSince!)
            guard quietFor >= inactivityDelay else { return nil }
            return max(0, Int(ceil(inactivityDelay + grace - quietFor)))
        }
    }
}

enum MeetingFollowUp {
    /// The bundled Meeting notes and follow-up skill: what changed, decisions, actions with an owner and a
    /// date only when the speakers gave them, open questions and a follow-up message. Its own suggested
    /// task applies; a keyword guess never becomes a claimed decision.
    static let skillID = "workbench-meeting-follow-up"

    /// The review's skills for a door. A meeting's own Prepare follow-up… offers every transcript skill
    /// with the meeting skill preferred, so the person can still choose Coach or the general follow-up.
    /// The other single-transcript door, Suggest details, keeps the general skill alone, as before.
    /// A History selection keeps the pack's remembered choice.
    static func reviewSkills(meetingDoor: Bool, singleTranscript: Bool, builtIns: [TranscriptHandoffSkill],
                             packSkills: [TranscriptHandoffSkill], packPreferred: String?)
        -> (skills: [TranscriptHandoffSkill], preferred: String?) {
        if meetingDoor {
            let skills = builtIns + packSkills
            return (skills, skills.contains { $0.id == skillID } ? skillID : nil)
        }
        if singleTranscript { return ([.followUp], nil) }
        return (builtIns + packSkills, packPreferred)
    }
}
