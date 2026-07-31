//
//  Advancement.swift
//  ShadowDeck
//
//  Karma advancement plan items and ledger entries (post-chargen purchases).
//

import Foundation

// MARK: - Kinds

/// What kind of advancement purchase this is.
public enum AdvancementKind: String, Codable, Sendable, Hashable, CaseIterable {
    case skillRaise
    case attributeRaise
    case newSkill
    case other

    public var displayName: String {
        switch self {
        case .skillRaise: "Skill raise"
        case .attributeRaise: "Attribute raise"
        case .newSkill: "New skill"
        case .other: "Other"
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
    public var karmaSpent: Int
    public var targetKey: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: AdvancementKind,
        summary: String,
        karmaSpent: Int,
        targetKey: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.summary = summary
        self.karmaSpent = karmaSpent
        self.targetKey = targetKey
    }
}
