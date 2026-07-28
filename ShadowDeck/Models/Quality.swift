//
//  Quality.swift
//  ShadowDeck
//

import Foundation

public enum QualityKind: String, Codable, Sendable, CaseIterable, Hashable {
    case positive
    case negative
}

public struct QualityInstance: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var catalogKey: String
    public var name: String
    public var kind: QualityKind
    /// Karma cost (positive qualities cost karma; negative grant karma). Sign is semantic by kind.
    public var karmaValue: Int
    public var rating: Int?
    public var notes: String
    public var modifiers: [StatModifier]

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        kind: QualityKind,
        karmaValue: Int,
        rating: Int? = nil,
        notes: String = "",
        modifiers: [StatModifier] = []
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.kind = kind
        self.karmaValue = karmaValue
        self.rating = rating
        self.notes = notes
        self.modifiers = modifiers
    }
}

extension QualityInstance {
    private enum CodingKeys: String, CodingKey {
        case id, catalogKey, name, kind, karmaValue, rating, notes, modifiers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        catalogKey = try c.decode(String.self, forKey: .catalogKey)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(QualityKind.self, forKey: .kind)
        karmaValue = try c.decode(Int.self, forKey: .karmaValue)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        modifiers = try c.decodeIfPresent([StatModifier].self, forKey: .modifiers) ?? []
    }
}

extension QualityInstance: ModifierSource {
    public var modifierSourceName: String { name }
    public var modifierRating: Int { max(1, rating ?? 1) }
    public var contributesModifiers: Bool { true }
}
