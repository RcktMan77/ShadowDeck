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

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        kind: AugmentationKind,
        grade: AugmentationGrade = .standard,
        rating: Int? = nil,
        essenceCost: Decimal,
        nuyenCost: Int = 0,
        notes: String = ""
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
    }
}
