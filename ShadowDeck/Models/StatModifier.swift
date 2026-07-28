//
//  StatModifier.swift
//  ShadowDeck
//
//  Phase 7 — modifiers applied by gear, augs, qualities, and powers.
//

import Foundation

/// What a modifier adjusts on the play sheet.
public enum ModifierTarget: String, Codable, Sendable, CaseIterable, Hashable {
    case body, agility, reaction, strength
    case willpower, logic, intuition, charisma
    case edge, magic, resonance
    case armor
    case initiative
    case initiativeDice
    case physicalLimit, mentalLimit, socialLimit
    /// Skill bonus keyed by skill display name / catalog key in `skillKey`.
    case skill

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
        case .armor: "Armor"
        case .initiative: "Initiative"
        case .initiativeDice: "Initiative Dice"
        case .physicalLimit: "Physical Limit"
        case .mentalLimit: "Mental Limit"
        case .socialLimit: "Social Limit"
        case .skill: "Skill"
        }
    }

    public var attributeID: AttributeID? {
        switch self {
        case .body: return .body
        case .agility: return .agility
        case .reaction: return .reaction
        case .strength: return .strength
        case .willpower: return .willpower
        case .logic: return .logic
        case .intuition: return .intuition
        case .charisma: return .charisma
        case .edge: return .edge
        case .magic: return .magic
        case .resonance: return .resonance
        default: return nil
        }
    }

    public static func fromChummerAttribute(_ raw: String) -> ModifierTarget? {
        switch raw.uppercased() {
        case "BOD", "BODY": return .body
        case "AGI", "AGILITY": return .agility
        case "REA", "REACTION": return .reaction
        case "STR", "STRENGTH": return .strength
        case "WIL", "WILLPOWER": return .willpower
        case "LOG", "LOGIC": return .logic
        case "INT", "INTUITION": return .intuition
        case "CHA", "CHARISMA": return .charisma
        case "EDG", "EDGE": return .edge
        case "MAG", "MAGIC": return .magic
        case "RES", "RESONANCE": return .resonance
        default: return nil
        }
    }
}

/// A single numeric bonus (or penalty) contributed by an item or quality.
public struct StatModifier: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var target: ModifierTarget
    /// Fixed delta, or coefficient when `usesRating` is true (see `resolvedAmount`).
    public var amount: Int
    /// When true (and no `ratingTable`), effective = `amount * rating + ratingOffset`.
    public var usesRating: Bool
    /// Added after rating scaling (e.g. Chummer `Rating-1` → amount 1, offset −1).
    public var ratingOffset: Int
    /// Chummer `FixedValues(a,b,c)` — value at rating 1…n (clamped to ends).
    public var ratingTable: [Int]?
    /// For `.skill` targets — skill display name or catalog key.
    public var skillKey: String?
    public var condition: String?

    public init(
        id: UUID = UUID(),
        target: ModifierTarget,
        amount: Int,
        usesRating: Bool = false,
        ratingOffset: Int = 0,
        ratingTable: [Int]? = nil,
        skillKey: String? = nil,
        condition: String? = nil
    ) {
        self.id = id
        self.target = target
        self.amount = amount
        self.usesRating = usesRating
        self.ratingOffset = ratingOffset
        self.ratingTable = ratingTable
        self.skillKey = skillKey
        self.condition = condition
    }

    public func resolvedAmount(rating: Int) -> Int {
        let r = max(1, rating)
        if let table = ratingTable, !table.isEmpty {
            let idx = min(r, table.count) - 1
            return table[idx]
        }
        if usesRating {
            return amount * r + ratingOffset
        }
        return amount
    }

    public var summary: String {
        let label: String = {
            if target == .skill, let skillKey, !skillKey.isEmpty { return skillKey }
            return target.displayName
        }()
        if let table = ratingTable, !table.isEmpty {
            let preview = table.prefix(4).map(String.init).joined(separator: "/")
            let more = table.count > 4 ? "…" : ""
            return "\(label) [\(preview)\(more)] by rating"
        }
        if usesRating {
            if amount == 1 && ratingOffset == 0 { return "\(label) +Rating" }
            if amount == -1 && ratingOffset == 0 { return "\(label) −Rating" }
            if amount == 1 {
                return "\(label) Rating\(ratingOffset >= 0 ? "+" : "")\(ratingOffset)"
            }
            if ratingOffset == 0 { return "\(label) \(amount)×Rating" }
            return "\(label) \(amount)×Rating\(ratingOffset >= 0 ? "+" : "")\(ratingOffset)"
        }
        let sign = amount >= 0 ? "+" : ""
        return "\(label) \(sign)\(amount)"
    }
}

// MARK: - Codable (catalog JSON may omit id / optional fields)

extension StatModifier {
    private enum CodingKeys: String, CodingKey {
        case id, target, amount, usesRating, ratingOffset, ratingTable, skillKey, condition
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        target = try c.decode(ModifierTarget.self, forKey: .target)
        amount = try c.decode(Int.self, forKey: .amount)
        usesRating = try c.decodeIfPresent(Bool.self, forKey: .usesRating) ?? false
        ratingOffset = try c.decodeIfPresent(Int.self, forKey: .ratingOffset) ?? 0
        ratingTable = try c.decodeIfPresent([Int].self, forKey: .ratingTable)
        skillKey = try c.decodeIfPresent(String.self, forKey: .skillKey)
        condition = try c.decodeIfPresent(String.self, forKey: .condition)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(target, forKey: .target)
        try c.encode(amount, forKey: .amount)
        try c.encode(usesRating, forKey: .usesRating)
        if ratingOffset != 0 { try c.encode(ratingOffset, forKey: .ratingOffset) }
        try c.encodeIfPresent(ratingTable, forKey: .ratingTable)
        try c.encodeIfPresent(skillKey, forKey: .skillKey)
        try c.encodeIfPresent(condition, forKey: .condition)
    }
}

/// Something that can contribute play-sheet modifiers.
public protocol ModifierSource {
    var modifierSourceName: String { get }
    var modifierRating: Int { get }
    var modifiers: [StatModifier] { get }
    /// When false, source is ignored (e.g. unequipped gear).
    var contributesModifiers: Bool { get }
}

public extension ModifierSource {
    var contributesModifiers: Bool { true }
    var modifierRating: Int { 1 }
}
