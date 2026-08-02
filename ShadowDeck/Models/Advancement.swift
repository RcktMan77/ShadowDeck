//
//  Advancement.swift
//  ShadowDeck
//
//  Karma advancement plan items and ledger entries (post-chargen purchases).
//

import Foundation

// MARK: - Kinds

/// What kind of advancement ledger / plan item this is.
public enum AdvancementKind: String, Codable, Sendable, Hashable, CaseIterable {
    case skillRaise
    case attributeRaise
    case newSkill
    case other
    /// Run award (nuyen + karma gain). Not a cart purchasable raise.
    case runAward

    public var displayName: String {
        switch self {
        case .skillRaise: "Skill raise"
        case .attributeRaise: "Attribute raise"
        case .newSkill: "New skill"
        case .other: "Other"
        case .runAward: "Run award"
        }
    }
}

// MARK: - Plan item (cart / single purchase)

/// A single planned or applied raise. Cart holds these in session UI state.
public struct AdvancementPlanItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: AdvancementKind
    /// Skill `catalogKey` or `AttributeID.rawValue`.
    public var targetKey: String
    public var displayName: String
    public var fromRating: Int
    public var toRating: Int
    public var karmaCost: Int
    /// Skill category when kind is skill-related (for cost revalidation).
    public var skillCategory: SkillCategory?

    public init(
        id: UUID = UUID(),
        kind: AdvancementKind,
        targetKey: String,
        displayName: String,
        fromRating: Int,
        toRating: Int,
        karmaCost: Int,
        skillCategory: SkillCategory? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetKey = targetKey
        self.displayName = displayName
        self.fromRating = fromRating
        self.toRating = toRating
        self.karmaCost = karmaCost
        self.skillCategory = skillCategory
    }

    /// Compact row label, e.g. `Pistols  4 → 5  (8 karma)`.
    public var progressSummary: String {
        "\(displayName)  \(fromRating) → \(toRating)  (\(karmaCost) karma)"
    }
}

// MARK: - Ledger

public struct AdvancementLedgerEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: AdvancementKind
    /// Human-readable line, e.g. `Pistols 4 → 5 (8 karma)`.
    public var summary: String
    /// Karma delta convention: **positive = spent** (purchases); **negative = gained** (e.g. run awards).
    public var karmaSpent: Int
    public var targetKey: String?
    /// Nuyen gained (positive) or spent; used by run awards. Defaults to 0 for older entries.
    public var nuyenDelta: Int
    /// Soft link to the run that produced a run award, when known.
    public var relatedRunID: UUID?
    /// Street Cred delta from a run award (Phase 2D). Defaults to 0 for older entries.
    public var streetCredDelta: Int
    /// Notoriety delta from a run award (Phase 2D). Defaults to 0 for older entries.
    public var notorietyDelta: Int
    /// Public Awareness delta from a run award (Phase 2D). Defaults to 0 for older entries.
    public var publicAwarenessDelta: Int

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: AdvancementKind,
        summary: String,
        karmaSpent: Int,
        targetKey: String? = nil,
        nuyenDelta: Int = 0,
        relatedRunID: UUID? = nil,
        streetCredDelta: Int = 0,
        notorietyDelta: Int = 0,
        publicAwarenessDelta: Int = 0
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.summary = summary
        self.karmaSpent = karmaSpent
        self.targetKey = targetKey
        self.nuyenDelta = nuyenDelta
        self.relatedRunID = relatedRunID
        self.streetCredDelta = streetCredDelta
        self.notorietyDelta = notorietyDelta
        self.publicAwarenessDelta = publicAwarenessDelta
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, kind, summary, karmaSpent, targetKey, nuyenDelta, relatedRunID
        case streetCredDelta, notorietyDelta, publicAwarenessDelta
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        kind = try c.decode(AdvancementKind.self, forKey: .kind)
        summary = try c.decode(String.self, forKey: .summary)
        karmaSpent = try c.decode(Int.self, forKey: .karmaSpent)
        targetKey = try c.decodeIfPresent(String.self, forKey: .targetKey)
        nuyenDelta = try c.decodeIfPresent(Int.self, forKey: .nuyenDelta) ?? 0
        relatedRunID = try c.decodeIfPresent(UUID.self, forKey: .relatedRunID)
        streetCredDelta = try c.decodeIfPresent(Int.self, forKey: .streetCredDelta) ?? 0
        notorietyDelta = try c.decodeIfPresent(Int.self, forKey: .notorietyDelta) ?? 0
        publicAwarenessDelta = try c.decodeIfPresent(Int.self, forKey: .publicAwarenessDelta) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(kind, forKey: .kind)
        try c.encode(summary, forKey: .summary)
        try c.encode(karmaSpent, forKey: .karmaSpent)
        try c.encodeIfPresent(targetKey, forKey: .targetKey)
        if nuyenDelta != 0 {
            try c.encode(nuyenDelta, forKey: .nuyenDelta)
        }
        try c.encodeIfPresent(relatedRunID, forKey: .relatedRunID)
        if streetCredDelta != 0 {
            try c.encode(streetCredDelta, forKey: .streetCredDelta)
        }
        if notorietyDelta != 0 {
            try c.encode(notorietyDelta, forKey: .notorietyDelta)
        }
        if publicAwarenessDelta != 0 {
            try c.encode(publicAwarenessDelta, forKey: .publicAwarenessDelta)
        }
    }
}
