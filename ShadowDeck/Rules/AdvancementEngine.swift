//
//  AdvancementEngine.swift
//  ShadowDeck
//
//  Pure karma advancement cost / eligibility / apply math (no UI).
//

import Foundation

// MARK: - Errors

public enum AdvancementError: Error, LocalizedError, Equatable {
    case insufficientKarma(needed: Int, available: Int)
    case atMaximum
    case skillNotFound
    case attributeNotRaiseable
    case staleFromRating(expected: Int, actual: Int)
    case invalidRaise
    case costMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .insufficientKarma(let needed, let available):
            return "Need \(needed) karma but only \(available) available."
        case .atMaximum:
            return "Already at maximum rating."
        case .skillNotFound:
            return "That skill was not found on the character."
        case .attributeNotRaiseable:
            return "That attribute cannot be raised further."
        case .staleFromRating(let expected, let actual):
            return "Plan is out of date (expected rating \(expected), found \(actual)). Refresh the plan."
        case .invalidRaise:
            return "Invalid raise (to-rating must be from-rating + 1)."
        case .costMismatch(let expected, let actual):
            return "Karma cost changed (plan had \(expected), current cost is \(actual)). Refresh the plan."
        }
    }
}

// MARK: - Raise preview (for UI rows)

public struct AdvancementRaisePreview: Sendable, Hashable, Identifiable {
    public var id: String { targetKey }
    public var kind: AdvancementKind
    public var targetKey: String
    public var displayName: String
    public var fromRating: Int
    public var toRating: Int
    public var maxRating: Int
    public var karmaCost: Int
    public var skillCategory: SkillCategory?
    public var canRaise: Bool

    public var progressSummary: String {
        "\(displayName)  \(fromRating) → \(toRating)  (\(karmaCost) karma)   max \(maxRating)"
    }

    public init(
        kind: AdvancementKind,
        targetKey: String,
        displayName: String,
        fromRating: Int,
        toRating: Int,
        maxRating: Int,
        karmaCost: Int,
        skillCategory: SkillCategory? = nil,
        canRaise: Bool
    ) {
        self.kind = kind
        self.targetKey = targetKey
        self.displayName = displayName
        self.fromRating = fromRating
        self.toRating = toRating
        self.maxRating = maxRating
        self.karmaCost = karmaCost
        self.skillCategory = skillCategory
        self.canRaise = canRaise
    }
}

// MARK: - Engine

public enum AdvancementEngine {
    /// Soft skill rating cap for post-chargen raises (v1).
    public static let skillSoftCap = 12

    /// Standard attributes offered for raise (plus Edge; Magic/Resonance when awakened).
    public static func raiseableAttributes(for character: Character) -> [AttributeID] {
        var ids = AttributeID.standardGenerationAttributes
        ids.append(.edge)
        if character.awakened.usesMagic || character.attributes.magic > 0 {
            ids.append(.magic)
        }
        if character.awakened.usesResonance || character.attributes.resonance > 0 {
            ids.append(.resonance)
        }
        return ids
    }

    // MARK: Maxima

    public static func skillMaximum(for _: SkillRating) -> Int {
        skillSoftCap
    }

    public static func attributeMaximum(
        for attribute: AttributeID,
        character: Character,
        rules: any EditionRules
    ) -> Int {
        let metatypeMax = rules.bounds(for: character.metatype, attribute: attribute).maximum
        return HouseRulesEngine.naturalAttributeMaximum(
            metatypeMaximum: metatypeMax,
            houseRules: character.houseRules
        )
    }

    // MARK: Costs

    public static func skillRaiseCost(
        character: Character,
        catalogKey: String,
        rules: any EditionRules
    ) -> Int? {
        guard let skill = character.skills.first(where: { $0.catalogKey == catalogKey }) else {
            return nil
        }
        guard skill.rating < skillMaximum(for: skill) else { return nil }
        return rules.karmaCostToRaiseSkill(from: skill.rating, category: skill.category)
    }

    public static func attributeRaiseCost(
        character: Character,
        attribute: AttributeID,
        rules: any EditionRules
    ) -> Int? {
        guard canRaiseAttribute(character: character, attribute: attribute, rules: rules) else {
            return nil
        }
        let current = character.attributes[attribute]
        return rules.karmaCostToRaiseAttribute(from: current, houseRules: character.houseRules)
    }

    /// Cost to buy a new skill at rating 1 (from 0).
    public static func newSkillCost(
        category: SkillCategory,
        rules: any EditionRules
    ) -> Int {
        rules.karmaCostToRaiseSkill(from: 0, category: category)
    }

    // MARK: Eligibility

    public static func canRaiseSkill(
        character: Character,
        catalogKey: String,
        rules: any EditionRules
    ) -> Bool {
        skillRaiseCost(character: character, catalogKey: catalogKey, rules: rules) != nil
    }

    public static func canRaiseAttribute(
        character: Character,
        attribute: AttributeID,
        rules: any EditionRules
    ) -> Bool {
        // Essence and initiative are not purchased with karma this way.
        guard attribute != .essence, attribute != .initiative else { return false }
        let current = character.attributes[attribute]
        // Magic/Resonance at 0 for mundanes: do not offer.
        if attribute == .magic, current <= 0, character.awakened == .mundane { return false }
        if attribute == .resonance, current <= 0, character.awakened != .technomancer { return false }
        let max = attributeMaximum(for: attribute, character: character, rules: rules)
        return current < max
    }

    // MARK: Build plan items / previews

    public static func makeSkillRaiseItem(
        character: Character,
        catalogKey: String,
        rules: any EditionRules
    ) -> AdvancementPlanItem? {
        guard let skill = character.skills.first(where: { $0.catalogKey == catalogKey }),
              let cost = skillRaiseCost(character: character, catalogKey: catalogKey, rules: rules)
        else { return nil }
        return AdvancementPlanItem(
            kind: .skillRaise,
            targetKey: skill.catalogKey,
            displayName: skill.displayName,
            fromRating: skill.rating,
            toRating: skill.rating + 1,
            karmaCost: cost,
            skillCategory: skill.category
        )
    }

    public static func makeAttributeRaiseItem(
        character: Character,
        attribute: AttributeID,
        rules: any EditionRules
    ) -> AdvancementPlanItem? {
        guard let cost = attributeRaiseCost(character: character, attribute: attribute, rules: rules)
        else { return nil }
        let current = character.attributes[attribute]
        return AdvancementPlanItem(
            kind: .attributeRaise,
            targetKey: attribute.rawValue,
            displayName: attribute.displayName,
            fromRating: current,
            toRating: current + 1,
            karmaCost: cost
        )
    }

    public static func makeNewSkillItem(
        catalogKey: String,
        displayName: String,
        category: SkillCategory,
        rules: any EditionRules
    ) -> AdvancementPlanItem {
        let cost = newSkillCost(category: category, rules: rules)
        return AdvancementPlanItem(
            kind: .newSkill,
            targetKey: catalogKey,
            displayName: displayName,
            fromRating: 0,
            toRating: 1,
            karmaCost: cost,
            skillCategory: category
        )
    }

    public static func skillRaisePreview(
        character: Character,
        skill: SkillRating,
        rules: any EditionRules
    ) -> AdvancementRaisePreview {
        let max = skillMaximum(for: skill)
        let can = skill.rating < max
        let cost = can ? rules.karmaCostToRaiseSkill(from: skill.rating, category: skill.category) : 0
        return AdvancementRaisePreview(
            kind: .skillRaise,
            targetKey: skill.catalogKey,
            displayName: skill.displayName,
            fromRating: skill.rating,
            toRating: skill.rating + 1,
            maxRating: max,
            karmaCost: cost,
            skillCategory: skill.category,
            canRaise: can
        )
    }

    public static func attributeRaisePreview(
        character: Character,
        attribute: AttributeID,
        rules: any EditionRules
    ) -> AdvancementRaisePreview {
        let current = character.attributes[attribute]
        let max = attributeMaximum(for: attribute, character: character, rules: rules)
        let can = canRaiseAttribute(character: character, attribute: attribute, rules: rules)
        let cost = can
            ? rules.karmaCostToRaiseAttribute(from: current, houseRules: character.houseRules)
            : 0
        return AdvancementRaisePreview(
            kind: .attributeRaise,
            targetKey: attribute.rawValue,
            displayName: attribute.displayName,
            fromRating: current,
            toRating: current + 1,
            maxRating: max,
            karmaCost: cost,
            canRaise: can
        )
    }

    // MARK: Suggestions (lightweight heuristics for UI)

    /// Metatype-favored attributes for “Suggested for you” (bias only; never filters full lists).
    public static func metatypeFavoredAttributes(_ metatype: MetatypeID) -> [AttributeID] {
        switch metatype {
        case .troll: [.body, .strength]
        case .ork: [.body, .strength]
        case .elf: [.agility, .charisma]
        case .dwarf: [.body, .willpower, .strength]
        case .human: [.edge]
        }
    }

    /// Metatype-favored skill catalog keys (partial match against character skills).
    public static func metatypeFavoredSkillKeys(_ metatype: MetatypeID) -> [String] {
        switch metatype {
        case .troll: ["unarmed", "intimidation", "heavy_weapons", "athletics"]
        case .ork: ["close_combat", "intimidation", "automatics", "blades"]
        case .elf: ["sneaking", "infiltration", "pistols", "negotiation", "etiquette", "gymnastics"]
        case .dwarf: ["armorer", "mechanic", "industrial", "hardware", "first_aid"]
        case .human: ["perception", "negotiation", "pistols"]
        }
    }

    /// Small static role → key skills map. Matches whole-word / substring against `concept` only when
    /// the concept string clearly contains a known role token (optional enhancement; safe no-op otherwise).
    public static func roleFavoredSkillKeys(concept: String) -> [String] {
        let c = concept.lowercased()
        let table: [(tokens: [String], keys: [String])] = [
            (["street sam", "samurai", "street samurai"], ["blades", "pistols", "dodge", "gymnastics", "perception"]),
            (["face", "negotiator"], ["negotiation", "etiquette", "con", "leadership", "impersonation"]),
            (["decker", "hacker"], ["hacking", "cybercombat", "electronic_warfare", "computer", "hardware"]),
            (["rigger"], ["pilot_ground_craft", "pilot_aircraft", "gunnery", "automotive_mechanic"]),
            (["mage", "magician", "spellcaster"], ["spellcasting", "counterspelling", "summoning", "assensing", "arcana"]),
            (["adept"], ["blades", "unarmed_combat", "gymnastics", "perception"]),
            (["techno", "technomancer"], ["compiling", "registering", "software", "cybercombat"]),
            (["infiltrator", "sneak", "covert"], ["sneaking", "palming", "locksmith", "disguise", "climbing"]),
            (["gunslinger", "shootist"], ["pistols", "automatics", "longarms", "perception"])
        ]
        var keys: [String] = []
        for row in table {
            if row.tokens.contains(where: { c.contains($0) }) {
                keys.append(contentsOf: row.keys)
            }
        }
        return keys
    }

    /// Build suggestion previews: metatype/role bias + cheapest affordable (or nearly affordable) raises.
    public static func suggestions(
        for character: Character,
        rules: any EditionRules,
        limit: Int = 6,
        almostAffordableSlack: Int = 5
    ) -> [AdvancementRaisePreview] {
        let budget = character.karmaAvailable
        let almostCap = budget + max(0, almostAffordableSlack)

        var candidates: [AdvancementRaisePreview] = []
        for attr in raiseableAttributes(for: character) {
            let p = attributeRaisePreview(character: character, attribute: attr, rules: rules)
            if p.canRaise { candidates.append(p) }
        }
        for skill in character.skills {
            let p = skillRaisePreview(character: character, skill: skill, rules: rules)
            if p.canRaise { candidates.append(p) }
        }

        let favoredAttrs = Set(metatypeFavoredAttributes(character.metatype).map(\.rawValue))
        var favoredSkills = Set(metatypeFavoredSkillKeys(character.metatype))
        for key in roleFavoredSkillKeys(concept: character.concept) {
            favoredSkills.insert(key)
        }

        func isFavored(_ p: AdvancementRaisePreview) -> Bool {
            switch p.kind {
            case .attributeRaise:
                return favoredAttrs.contains(p.targetKey)
            case .skillRaise, .newSkill:
                return favoredSkills.contains { p.targetKey.contains($0) || $0.contains(p.targetKey) }
            case .other, .runAward:
                return false
            }
        }

        func score(_ p: AdvancementRaisePreview) -> (Int, Int, String) {
            // Lower is better: favored first, then cost tiers, then name
            let fav = isFavored(p) ? 0 : 1
            let costTier: Int
            if p.karmaCost <= budget {
                costTier = 0
            } else if p.karmaCost <= almostCap {
                costTier = 1
            } else {
                costTier = 2
            }
            return (fav, costTier * 1_000 + p.karmaCost, p.displayName.lowercased())
        }

        // Prefer items that are favored OR affordable/near-affordable; drop expensive non-favored.
        let filtered = candidates.filter { p in
            isFavored(p) || p.karmaCost <= almostCap
        }

        let sorted = filtered.sorted { a, b in
            let sa = score(a)
            let sb = score(b)
            if sa.0 != sb.0 { return sa.0 < sb.0 }
            if sa.1 != sb.1 { return sa.1 < sb.1 }
            return sa.2 < sb.2
        }

        // De-dupe by targetKey preserving order
        var seen = Set<String>()
        var result: [AdvancementRaisePreview] = []
        for p in sorted {
            guard seen.insert(p.targetKey).inserted else { continue }
            result.append(p)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: Apply

    /// Apply a single plan item. Re-validates rating and cost against live character state.
    public static func apply(
        _ item: AdvancementPlanItem,
        to character: inout Character,
        rules: any EditionRules,
        at date: Date = Date()
    ) throws {
        guard item.toRating == item.fromRating + 1 else {
            throw AdvancementError.invalidRaise
        }

        switch item.kind {
        case .skillRaise:
            try applySkillRaise(item, to: &character, rules: rules, at: date)
        case .attributeRaise:
            try applyAttributeRaise(item, to: &character, rules: rules, at: date)
        case .newSkill:
            try applyNewSkill(item, to: &character, rules: rules, at: date)
        case .other, .runAward:
            throw AdvancementError.invalidRaise
        }
    }

    /// Apply multiple items. Attributes first, then skills / new skills; re-validates each step.
    /// Fails atomically: on error, character is left unchanged (caller should pass a copy or rely on throw before mutation — we mutate in place after validating total when possible).
    public static func apply(
        items: [AdvancementPlanItem],
        to character: inout Character,
        rules: any EditionRules,
        at date: Date = Date()
    ) throws {
        guard !items.isEmpty else { return }

        let sorted = Self.sortedForApply(items)
        // Snapshot for atomicity
        let snapshot = character
        do {
            for item in sorted {
                try apply(item, to: &character, rules: rules, at: date)
            }
        } catch {
            character = snapshot
            throw error
        }
    }

    public static func sortedForApply(_ items: [AdvancementPlanItem]) -> [AdvancementPlanItem] {
        items.sorted { a, b in
            let ra = applyRank(a.kind)
            let rb = applyRank(b.kind)
            if ra != rb { return ra < rb }
            return a.targetKey < b.targetKey
        }
    }

    private static func applyRank(_ kind: AdvancementKind) -> Int {
        switch kind {
        case .attributeRaise: 0
        case .skillRaise: 1
        case .newSkill: 2
        case .other, .runAward: 3
        }
    }

    // MARK: Private apply helpers

    private static func debitKarma(_ character: inout Character, cost: Int) throws {
        let available = character.karmaAvailable
        guard cost <= available else {
            throw AdvancementError.insufficientKarma(needed: cost, available: available)
        }
        character.karmaAvailable = available - cost
    }

    private static func applySkillRaise(
        _ item: AdvancementPlanItem,
        to character: inout Character,
        rules: any EditionRules,
        at date: Date
    ) throws {
        guard let index = character.skills.firstIndex(where: { $0.catalogKey == item.targetKey }) else {
            throw AdvancementError.skillNotFound
        }
        let skill = character.skills[index]
        if skill.rating != item.fromRating {
            throw AdvancementError.staleFromRating(expected: item.fromRating, actual: skill.rating)
        }
        guard skill.rating < skillMaximum(for: skill) else {
            throw AdvancementError.atMaximum
        }
        let liveCost = rules.karmaCostToRaiseSkill(from: skill.rating, category: skill.category)
        if liveCost != item.karmaCost {
            throw AdvancementError.costMismatch(expected: item.karmaCost, actual: liveCost)
        }
        try debitKarma(&character, cost: liveCost)
        character.skills[index].rating = skill.rating + 1
        let summary = "\(skill.displayName) \(skill.rating) → \(skill.rating + 1) (\(liveCost) karma)"
        character.appendAdvancementLedger(
            AdvancementLedgerEntry(
                date: date,
                kind: .skillRaise,
                summary: summary,
                karmaSpent: liveCost,
                targetKey: skill.catalogKey
            )
        )
        character.touch()
    }

    private static func applyAttributeRaise(
        _ item: AdvancementPlanItem,
        to character: inout Character,
        rules: any EditionRules,
        at date: Date
    ) throws {
        guard let attribute = AttributeID(rawValue: item.targetKey) else {
            throw AdvancementError.attributeNotRaiseable
        }
        let current = character.attributes[attribute]
        if current != item.fromRating {
            throw AdvancementError.staleFromRating(expected: item.fromRating, actual: current)
        }
        guard canRaiseAttribute(character: character, attribute: attribute, rules: rules) else {
            throw AdvancementError.atMaximum
        }
        let liveCost = rules.karmaCostToRaiseAttribute(from: current, houseRules: character.houseRules)
        if liveCost != item.karmaCost {
            throw AdvancementError.costMismatch(expected: item.karmaCost, actual: liveCost)
        }
        try debitKarma(&character, cost: liveCost)
        character.attributes[attribute] = current + 1
        let summary = "\(attribute.displayName) \(current) → \(current + 1) (\(liveCost) karma)"
        character.appendAdvancementLedger(
            AdvancementLedgerEntry(
                date: date,
                kind: .attributeRaise,
                summary: summary,
                karmaSpent: liveCost,
                targetKey: attribute.rawValue
            )
        )
        character.touch()
    }

    private static func applyNewSkill(
        _ item: AdvancementPlanItem,
        to character: inout Character,
        rules: any EditionRules,
        at date: Date
    ) throws {
        if character.skills.contains(where: { $0.catalogKey == item.targetKey }) {
            // Already present — treat as skill raise from current if ratings match 0→1 intent
            throw AdvancementError.staleFromRating(expected: 0, actual: character.skills.first { $0.catalogKey == item.targetKey }?.rating ?? -1)
        }
        guard item.fromRating == 0, item.toRating == 1 else {
            throw AdvancementError.invalidRaise
        }
        let category = item.skillCategory ?? .active
        let liveCost = newSkillCost(category: category, rules: rules)
        if liveCost != item.karmaCost {
            throw AdvancementError.costMismatch(expected: item.karmaCost, actual: liveCost)
        }
        try debitKarma(&character, cost: liveCost)
        character.skills.append(
            SkillRating(
                catalogKey: item.targetKey,
                displayName: item.displayName,
                category: category,
                rating: 1
            )
        )
        let summary = "\(item.displayName) 0 → 1 (\(liveCost) karma)"
        character.appendAdvancementLedger(
            AdvancementLedgerEntry(
                date: date,
                kind: .newSkill,
                summary: summary,
                karmaSpent: liveCost,
                targetKey: item.targetKey
            )
        )
        character.touch()
    }
}
