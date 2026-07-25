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

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        level: Int = 1,
        powerPointCost: Decimal,
        notes: String = ""
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.level = level
        self.powerPointCost = powerPointCost
        self.notes = notes
    }
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
