//
//  MagicAndResonance.swift
//  ShadowDeck
//

import Foundation

public enum AwakenedPath: String, Codable, Sendable, CaseIterable, Hashable {
    case mundane
    case fullMagician
    case aspectedMagician
    case mysticAdept
    case adept
    case technomancer

    public var displayName: String {
        switch self {
        case .mundane: "Mundane"
        case .fullMagician: "Magician"
        case .aspectedMagician: "Aspected Magician"
        case .mysticAdept: "Mystic Adept"
        case .adept: "Adept"
        case .technomancer: "Technomancer"
        }
    }

    public var usesMagic: Bool {
        switch self {
        case .fullMagician, .aspectedMagician, .mysticAdept, .adept: true
        default: false
        }
    }

    public var usesResonance: Bool { self == .technomancer }
}

public struct SpellInstance: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var catalogKey: String
    public var name: String
    public var category: String
    public var notes: String

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        category: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.category = category
        self.notes = notes
    }
}

public struct AdeptPowerInstance: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var catalogKey: String
    public var name: String
    public var level: Int
    public var powerPointCost: Decimal
    public var notes: String
    public var modifiers: [StatModifier]

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        level: Int = 1,
        powerPointCost: Decimal,
        notes: String = "",
        modifiers: [StatModifier] = []
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.level = level
        self.powerPointCost = powerPointCost
        self.notes = notes
        self.modifiers = modifiers
    }
}

extension AdeptPowerInstance {
    private enum CodingKeys: String, CodingKey {
        case id, catalogKey, name, level, powerPointCost, notes, modifiers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        catalogKey = try c.decode(String.self, forKey: .catalogKey)
        name = try c.decode(String.self, forKey: .name)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        powerPointCost = try c.decode(Decimal.self, forKey: .powerPointCost)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        modifiers = try c.decodeIfPresent([StatModifier].self, forKey: .modifiers) ?? []
    }
}

extension AdeptPowerInstance: ModifierSource {
    public var modifierSourceName: String { name }
    public var modifierRating: Int { max(1, level) }
    public var contributesModifiers: Bool { true }
}

public struct ComplexFormInstance: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var catalogKey: String
    public var name: String
    public var notes: String

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        notes: String = ""
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.notes = notes
    }
}
