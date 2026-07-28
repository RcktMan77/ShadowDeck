//
//  Augmentation.swift
//  ShadowDeck
//
//  Cyberware and bioware instances on a character.
//

import Foundation

public enum AugmentationKind: String, Codable, Sendable, CaseIterable, Hashable {
    case cyberware
    case bioware
}

public enum AugmentationGrade: String, Codable, Sendable, CaseIterable, Hashable {
    case standard
    case alphaware
    case betaware
    case deltaware
    case used
}

public struct Augmentation: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var catalogKey: String
    public var name: String
    public var kind: AugmentationKind
    public var grade: AugmentationGrade
    public var rating: Int?
    /// Essence cost after grade modifiers (pre-house-rule).
    public var essenceCost: Decimal
    public var nuyenCost: Int
    public var notes: String
    public var modifiers: [StatModifier]
    public var purchasedInApp: Bool

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        kind: AugmentationKind,
        grade: AugmentationGrade = .standard,
        rating: Int? = nil,
        essenceCost: Decimal,
        nuyenCost: Int = 0,
        notes: String = "",
        modifiers: [StatModifier] = [],
        purchasedInApp: Bool = false
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.kind = kind
        self.grade = grade
        self.rating = rating
        self.essenceCost = essenceCost
        self.nuyenCost = nuyenCost
        self.notes = notes
        self.modifiers = modifiers
        self.purchasedInApp = purchasedInApp
    }
}

extension Augmentation {
    private enum CodingKeys: String, CodingKey {
        case id, catalogKey, name, kind, grade, rating, essenceCost, nuyenCost, notes
        case modifiers, purchasedInApp
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        catalogKey = try c.decode(String.self, forKey: .catalogKey)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(AugmentationKind.self, forKey: .kind)
        grade = try c.decodeIfPresent(AugmentationGrade.self, forKey: .grade) ?? .standard
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        essenceCost = try c.decode(Decimal.self, forKey: .essenceCost)
        nuyenCost = try c.decodeIfPresent(Int.self, forKey: .nuyenCost) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        modifiers = try c.decodeIfPresent([StatModifier].self, forKey: .modifiers) ?? []
        purchasedInApp = try c.decodeIfPresent(Bool.self, forKey: .purchasedInApp) ?? false
    }
}

extension Augmentation: ModifierSource {
    public var modifierSourceName: String { name }
    public var modifierRating: Int { max(1, rating ?? 1) }
    public var contributesModifiers: Bool { true }
}
