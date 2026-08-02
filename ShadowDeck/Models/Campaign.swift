//
//  Campaign.swift
//  ShadowDeck
//
//  GM campaign container — groups runs for a single table/edition on one Mac.
//  Distinct from `CampaignSheetReport` (character play-sheet export).
//

import Foundation

/// Multi-run campaign for one GM (local only).
public struct Campaign: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var schemaVersion: Int
    public var name: String
    /// Default ruleset for new runs created under this campaign.
    public var edition: Edition
    public var notes: String
    /// Free-text table defaults (not a full `HouseRules` blob in Phase 2A).
    public var houseRuleHints: String
    /// Hidden from the default Campaigns list; runs keep `campaignID`.
    public var isArchived: Bool
    public var createdAt: Date
    public var modifiedAt: Date

    public static let currentSchemaVersion = 1

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = Self.currentSchemaVersion,
        name: String = "",
        edition: Edition = .sr5,
        notes: String = "",
        houseRuleHints: String = "",
        isArchived: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.edition = edition
        self.notes = notes
        self.houseRuleHints = houseRuleHints
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public mutating func touch() {
        modifiedAt = Date()
    }

    public var hasValidName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func makeDraft(name: String = "New Campaign", edition: Edition = .sr5) -> Campaign {
        Campaign(name: name, edition: edition)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, name, edition, notes, houseRuleHints, isArchived
        case createdAt, modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        edition = try c.decodeIfPresent(Edition.self, forKey: .edition) ?? .sr5
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        houseRuleHints = try c.decodeIfPresent(String.self, forKey: .houseRuleHints) ?? ""
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(name, forKey: .name)
        try c.encode(edition, forKey: .edition)
        try c.encode(notes, forKey: .notes)
        try c.encode(houseRuleHints, forKey: .houseRuleHints)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

/// Lightweight list DTO for the Campaigns library.
public struct CampaignSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var edition: Edition
    public var isArchived: Bool
    public var modifiedAt: Date
    public var createdAt: Date
    /// Count of runs currently assigned to this campaign (computed at list time).
    public var runCount: Int
    public var activeRunCount: Int
    public var lastActivityAt: Date?

    public init(
        id: UUID,
        name: String,
        edition: Edition,
        isArchived: Bool,
        modifiedAt: Date,
        createdAt: Date,
        runCount: Int = 0,
        activeRunCount: Int = 0,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.edition = edition
        self.isArchived = isArchived
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.runCount = runCount
        self.activeRunCount = activeRunCount
        self.lastActivityAt = lastActivityAt
    }
}
