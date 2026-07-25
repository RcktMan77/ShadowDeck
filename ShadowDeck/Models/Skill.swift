//
//  Skill.swift
//  ShadowDeck
//

import Foundation

public enum SkillCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case active
    case knowledge
    case language
}

public enum SkillGroupID: String, Codable, Sendable, CaseIterable, Hashable {
    case athletics
    case biotech
    case closeCombat
    case conjuring
    case cracking
    case electronics
    case enchanting
    case fireArarms = "firearms"
    case influence
    case engineering
    case outdoors
    case perception
    case piloting
    case sorcery
    case stealth
    case tasking

    public var displayName: String {
        switch self {
        case .closeCombat: "Close Combat"
        case .fireArarms: "Firearms"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// A skill rating on a character. Catalog definitions stay data-driven; this is instance data.
public struct SkillRating: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Stable catalog key (e.g. "pistols", "software", "english").
    public var catalogKey: String
    public var displayName: String
    public var category: SkillCategory
    public var rating: Int
    public var specialized: String?
    public var group: SkillGroupID?
    /// Knowledge / language only.
    public var knowledgeType: String?

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        displayName: String,
        category: SkillCategory,
        rating: Int,
        specialized: String? = nil,
        group: SkillGroupID? = nil,
        knowledgeType: String? = nil
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.displayName = displayName
        self.category = category
        self.rating = rating
        self.specialized = specialized
        self.group = group
        self.knowledgeType = knowledgeType
    }
}

/// Skill group bought as a unit (SR4 / SR5 style).
public struct SkillGroupRating: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var group: SkillGroupID
    public var rating: Int

    public init(id: UUID = UUID(), group: SkillGroupID, rating: Int) {
        self.id = id
        self.group = group
        self.rating = rating
    }
}
