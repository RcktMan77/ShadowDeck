//
//  AttributeID.swift
//  ShadowDeck
//
//  Canonical attribute identifiers shared across editions.
//

import Foundation

/// Physical, mental, and special attributes used by SR4 / SR5 / SR6 core.
public enum AttributeID: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    // Physical
    case body
    case agility
    case reaction
    case strength
    // Mental
    case willpower
    case logic
    case intuition
    case charisma
    // Special
    case edge
    case magic
    case resonance
    case essence
    case initiative // derived in most editions; stored when needed for overrides

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .body: "Body"
        case .agility: "Agility"
        case .reaction: "Reaction"
        case .strength: "Strength"
        case .willpower: "Willpower"
        case .logic: "Logic"
        case .intuition: "Intuition"
        case .charisma: "Charisma"
        case .edge: "Edge"
        case .magic: "Magic"
        case .resonance: "Resonance"
        case .essence: "Essence"
        case .initiative: "Initiative"
        }
    }

    public var category: AttributeCategory {
        switch self {
        case .body, .agility, .reaction, .strength:
            .physical
        case .willpower, .logic, .intuition, .charisma:
            .mental
        case .edge, .magic, .resonance, .essence, .initiative:
            .special
        }
    }

    /// Attributes purchased with normal attribute points at generation (not special/adjustment).
    public static var standardGenerationAttributes: [Self] {
        [.body, .agility, .reaction, .strength, .willpower, .logic, .intuition, .charisma]
    }

    /// Special attributes that may receive metatype adjustment / special points.
    public static var specialPointAttributes: [Self] {
        [.edge, .magic, .resonance]
    }
}

public enum AttributeCategory: String, Codable, Sendable, CaseIterable {
    case physical
    case mental
    case special
}

/// Integer ratings for most attributes; Essence is fractional and stored separately.
public struct AttributeRatings: Codable, Sendable, Hashable {
    public var body: Int
    public var agility: Int
    public var reaction: Int
    public var strength: Int
    public var willpower: Int
    public var logic: Int
    public var intuition: Int
    public var charisma: Int
    public var edge: Int
    public var magic: Int
    public var resonance: Int

    /// Essence is tracked as a decimal (e.g. 5.7). Natural baseline is 6.0.
    public var essence: Decimal

    public init(
        body: Int = 1,
        agility: Int = 1,
        reaction: Int = 1,
        strength: Int = 1,
        willpower: Int = 1,
        logic: Int = 1,
        intuition: Int = 1,
        charisma: Int = 1,
        edge: Int = 1,
        magic: Int = 0,
        resonance: Int = 0,
        essence: Decimal = 6
    ) {
        self.body = body
        self.agility = agility
        self.reaction = reaction
        self.strength = strength
        self.willpower = willpower
        self.logic = logic
        self.intuition = intuition
        self.charisma = charisma
        self.edge = edge
        self.magic = magic
        self.resonance = resonance
        self.essence = essence
    }

    public subscript(_ id: AttributeID) -> Int {
        get {
            switch id {
            case .body: body
            case .agility: agility
            case .reaction: reaction
            case .strength: strength
            case .willpower: willpower
            case .logic: logic
            case .intuition: intuition
            case .charisma: charisma
            case .edge: edge
            case .magic: magic
            case .resonance: resonance
            case .essence: NSDecimalNumber(decimal: essence).intValue
            case .initiative: 0
            }
        }
        set {
            switch id {
            case .body: body = newValue
            case .agility: agility = newValue
            case .reaction: reaction = newValue
            case .strength: strength = newValue
            case .willpower: willpower = newValue
            case .logic: logic = newValue
            case .intuition: intuition = newValue
            case .charisma: charisma = newValue
            case .edge: edge = newValue
            case .magic: magic = newValue
            case .resonance: resonance = newValue
            case .essence, .initiative: break
            }
        }
    }

    public static let naturalEssenceBaseline: Decimal = 6
}
