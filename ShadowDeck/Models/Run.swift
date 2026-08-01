//
//  Run.swift
//  ShadowDeck
//
//  GM Run / Mission tracker domain — pure value types, Codable.
//  Soft-links library characters by UUID; does not embed Character snapshots.
//

import AppKit
import Foundation

// MARK: - Status / enums

public enum RunStatus: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case planning
    case active
    case completed
    case failed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .planning: "Planning"
        case .active: "Active"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }

    public var systemImage: String {
        switch self {
        case .planning: "list.clipboard"
        case .active: "bolt.fill"
        case .completed: "checkmark.seal.fill"
        case .failed: "xmark.seal.fill"
        }
    }

    public var isTerminal: Bool {
        self == .completed || self == .failed
    }
}

public enum RunObjectiveStatus: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case pending
    case complete
    case failed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pending: "Pending"
        case .complete: "Complete"
        case .failed: "Failed"
        }
    }
}

public enum RunLogEntryKind: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case note
    case complication
    case heat
    case objective
    case session

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .note: "Note"
        case .complication: "Complication"
        case .heat: "Heat"
        case .objective: "Objective"
        case .session: "Session"
        }
    }

    public var systemImage: String {
        switch self {
        case .note: "note.text"
        case .complication: "exclamationmark.triangle"
        case .heat: "flame"
        case .objective: "target"
        case .session: "clock"
        }
    }
}

// MARK: - Nested value types

public struct RunPayout: Codable, Sendable, Hashable {
    public var nuyen: Int
    public var karma: Int

    public init(nuyen: Int = 0, karma: Int = 0) {
        self.nuyen = max(0, nuyen)
        self.karma = max(0, karma)
    }

    public static let zero = RunPayout(nuyen: 0, karma: 0)

    public var isZero: Bool { nuyen == 0 && karma == 0 }
}

public struct RunObjective: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var text: String
    /// `true` = primary objective list; `false` = secondary.
    public var isPrimary: Bool
    public var status: RunObjectiveStatus

    public init(
        id: UUID = UUID(),
        text: String = "",
        isPrimary: Bool = true,
        status: RunObjectiveStatus = .pending
    ) {
        self.id = id
        self.text = text
        self.isPrimary = isPrimary
        self.status = status
    }
}

public struct RunLogEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var kind: RunLogEntryKind
    public var text: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: RunLogEntryKind = .note,
        text: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
    }
}

/// Display-only award proposal — never mutates linked characters by itself.
public struct RunAwardSuggestion: Sendable, Hashable, Identifiable {
    public var characterID: UUID
    public var nuyen: Int
    public var karma: Int
    public var note: String

    public var id: UUID { characterID }

    public init(characterID: UUID, nuyen: Int, karma: Int, note: String) {
        self.characterID = characterID
        self.nuyen = nuyen
        self.karma = karma
        self.note = note
    }
}

// MARK: - Run aggregate

public struct Run: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var schemaVersion: Int

    public var title: String
    public var tags: [String]
    public var status: RunStatus
    /// Rulebook edition for this job; team links are restricted to matching characters.
    public var edition: Edition

    public var plannedDate: Date?
    public var startedAt: Date?
    public var completedAt: Date?

    /// Mr. Johnson / client free text.
    public var client: String
    public var location: String
    public var objectives: [RunObjective]
    /// Threats / opposition free text.
    public var opposition: String
    /// Standing complications (timeline may also capture mid-run events).
    public var complicationsNotes: String

    public var expectedPayout: RunPayout
    public var actualPayout: RunPayout?
    /// Heat generated (planned or actual).
    public var heatDelta: Int

    /// Soft links into `CharacterLibrary` (tolerate missing IDs after character delete).
    public var participantCharacterIDs: [UUID]
    /// Reserved for multi-campaign grouping; nil in v1.
    public var campaignID: UUID?

    public var sessionLog: [RunLogEntry]
    public var outcomeSummary: String
    public var gmNotes: String

    /// When non-nil, suggested awards have been committed to linked characters (double-apply guard).
    public var awardsAppliedAt: Date?
    /// Optional free-text note captured when awards were applied.
    public var awardsAppliedNote: String?

    public var createdAt: Date
    public var modifiedAt: Date

    public static let currentSchemaVersion = 1

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = Run.currentSchemaVersion,
        title: String = "",
        tags: [String] = [],
        status: RunStatus = .planning,
        edition: Edition = .sr5,
        plannedDate: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        client: String = "",
        location: String = "",
        objectives: [RunObjective] = [],
        opposition: String = "",
        complicationsNotes: String = "",
        expectedPayout: RunPayout = .zero,
        actualPayout: RunPayout? = nil,
        heatDelta: Int = 0,
        participantCharacterIDs: [UUID] = [],
        campaignID: UUID? = nil,
        sessionLog: [RunLogEntry] = [],
        outcomeSummary: String = "",
        gmNotes: String = "",
        awardsAppliedAt: Date? = nil,
        awardsAppliedNote: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.title = title
        self.tags = tags
        self.status = status
        self.edition = edition
        self.plannedDate = plannedDate
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.client = client
        self.location = location
        self.objectives = objectives
        self.opposition = opposition
        self.complicationsNotes = complicationsNotes
        self.expectedPayout = expectedPayout
        self.actualPayout = actualPayout
        self.heatDelta = heatDelta
        self.participantCharacterIDs = participantCharacterIDs
        self.campaignID = campaignID
        self.sessionLog = sessionLog
        self.outcomeSummary = outcomeSummary
        self.gmNotes = gmNotes
        self.awardsAppliedAt = awardsAppliedAt
        self.awardsAppliedNote = awardsAppliedNote
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // MARK: Codable (legacy payloads may omit `edition` / awards fields)

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, title, tags, status, edition
        case plannedDate, startedAt, completedAt
        case client, location, objectives, opposition, complicationsNotes
        case expectedPayout, actualPayout, heatDelta
        case participantCharacterIDs, campaignID
        case sessionLog, outcomeSummary, gmNotes
        case awardsAppliedAt, awardsAppliedNote
        case createdAt, modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Run.currentSchemaVersion
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try c.decodeIfPresent(RunStatus.self, forKey: .status) ?? .planning
        edition = try c.decodeIfPresent(Edition.self, forKey: .edition) ?? .sr5
        plannedDate = try c.decodeIfPresent(Date.self, forKey: .plannedDate)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        client = try c.decodeIfPresent(String.self, forKey: .client) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        objectives = try c.decodeIfPresent([RunObjective].self, forKey: .objectives) ?? []
        opposition = try c.decodeIfPresent(String.self, forKey: .opposition) ?? ""
        complicationsNotes = try c.decodeIfPresent(String.self, forKey: .complicationsNotes) ?? ""
        expectedPayout = try c.decodeIfPresent(RunPayout.self, forKey: .expectedPayout) ?? .zero
        actualPayout = try c.decodeIfPresent(RunPayout.self, forKey: .actualPayout)
        heatDelta = try c.decodeIfPresent(Int.self, forKey: .heatDelta) ?? 0
        participantCharacterIDs = try c.decodeIfPresent([UUID].self, forKey: .participantCharacterIDs) ?? []
        campaignID = try c.decodeIfPresent(UUID.self, forKey: .campaignID)
        sessionLog = try c.decodeIfPresent([RunLogEntry].self, forKey: .sessionLog) ?? []
        outcomeSummary = try c.decodeIfPresent(String.self, forKey: .outcomeSummary) ?? ""
        gmNotes = try c.decodeIfPresent(String.self, forKey: .gmNotes) ?? ""
        awardsAppliedAt = try c.decodeIfPresent(Date.self, forKey: .awardsAppliedAt)
        awardsAppliedNote = try c.decodeIfPresent(String.self, forKey: .awardsAppliedNote)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(title, forKey: .title)
        try c.encode(tags, forKey: .tags)
        try c.encode(status, forKey: .status)
        try c.encode(edition, forKey: .edition)
        try c.encodeIfPresent(plannedDate, forKey: .plannedDate)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(client, forKey: .client)
        try c.encode(location, forKey: .location)
        try c.encode(objectives, forKey: .objectives)
        try c.encode(opposition, forKey: .opposition)
        try c.encode(complicationsNotes, forKey: .complicationsNotes)
        try c.encode(expectedPayout, forKey: .expectedPayout)
        try c.encodeIfPresent(actualPayout, forKey: .actualPayout)
        try c.encode(heatDelta, forKey: .heatDelta)
        try c.encode(participantCharacterIDs, forKey: .participantCharacterIDs)
        try c.encodeIfPresent(campaignID, forKey: .campaignID)
        try c.encode(sessionLog, forKey: .sessionLog)
        try c.encode(outcomeSummary, forKey: .outcomeSummary)
        try c.encode(gmNotes, forKey: .gmNotes)
        try c.encodeIfPresent(awardsAppliedAt, forKey: .awardsAppliedAt)
        try c.encodeIfPresent(awardsAppliedNote, forKey: .awardsAppliedNote)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }

    public mutating func touch() {
        modifiedAt = Date()
    }

    /// Non-empty after trimming whitespace.
    public var hasValidTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var primaryObjectives: [RunObjective] {
        objectives.filter(\.isPrimary)
    }

    public var secondaryObjectives: [RunObjective] {
        objectives.filter { !$0.isPrimary }
    }

    /// Session log newest-first (does not mutate storage order).
    public var sessionLogNewestFirst: [RunLogEntry] {
        sessionLog.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Status transitions

    /// Apply a status change and auto-stamp dates when appropriate.
    public mutating func applyStatus(_ newStatus: RunStatus, at date: Date = Date()) {
        let previous = status
        status = newStatus
        if newStatus == .active, previous != .active, startedAt == nil {
            startedAt = date
        }
        if newStatus.isTerminal, previous != newStatus || completedAt == nil {
            if completedAt == nil {
                completedAt = date
            }
        }
        // Leaving a terminal state clears completion stamp so re-open is clean.
        if previous.isTerminal, !newStatus.isTerminal {
            completedAt = nil
        }
        touch()
    }

    /// True when terminal with no meaningful outcome text — UI may remind, not block.
    /// Strips RTF so empty rich-text shells don’t count as content.
    public var shouldRemindEmptyOutcome: Bool {
        status.isTerminal && Self.isBlankNote(outcomeSummary)
    }

    /// Empty plain text or empty/minimal RTF (no visible characters).
    public static func isBlankNote(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        // Prefer real RTF→plain conversion. Note: `cleanRichText` treats empty
        // attributed strings as a failed conversion and falls back to a stripper
        // that can leave font names — so empty docs would look non-empty.
        if trimmed.hasPrefix("{\\rtf") || trimmed.contains("{\\rtf") {
            let data = Data(trimmed.utf8)
            if let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                return attributed.string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            }
        }

        let plain = ChummerParsingHelpers.cleanRichText(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty
    }

    // MARK: Awards (suggestions only)

    /// Equal floor split of preferred payout across participants.
    /// Remainder nuyen/karma goes to the first participant. Does **not** mutate characters.
    public func suggestedAwards() -> [RunAwardSuggestion] {
        let ids = participantCharacterIDs
        guard !ids.isEmpty else { return [] }

        let source = actualPayout ?? expectedPayout
        let count = ids.count
        let baseNuyen = source.nuyen / count
        let baseKarma = source.karma / count
        let remNuyen = source.nuyen % count
        let remKarma = source.karma % count

        let sourceLabel = actualPayout != nil ? "actual" : "expected"
        let note = "Equal split of \(sourceLabel) payout (suggestions only — does not change character karma/nuyen)"

        return ids.enumerated().map { index, characterID in
            RunAwardSuggestion(
                characterID: characterID,
                nuyen: baseNuyen + (index == 0 ? remNuyen : 0),
                karma: baseKarma + (index == 0 ? remKarma : 0),
                note: note
            )
        }
    }
}

// MARK: - Factory

public extension Run {
    /// New planning run with a placeholder title the GM should replace.
    static func makeDraft(title: String = "New Run", edition: Edition = .sr5) -> Run {
        Run(title: title, status: .planning, edition: edition)
    }

    /// Whether a library character may join this run’s team (edition match).
    func acceptsParticipant(edition characterEdition: Edition?) -> Bool {
        guard let characterEdition else { return false }
        return characterEdition == edition
    }

    /// Drop linked runners that no longer match `edition` (e.g. after ruleset change).
    mutating func pruneIneligibleParticipants(characterEditions: [UUID: Edition]) {
        participantCharacterIDs.removeAll { id in
            guard let ed = characterEditions[id] else { return false }
            return ed != edition
        }
    }
}
