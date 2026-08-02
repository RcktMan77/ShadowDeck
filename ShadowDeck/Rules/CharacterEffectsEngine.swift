//
//  CharacterEffectsEngine.swift
//  ShadowDeck
//
//  Phase 7 — resolve base attributes + item/quality/power modifiers into
//  effective play-sheet stats. Catalog purchase helpers for nuyen.
//

import Foundation

public struct AppliedModifier: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var sourceName: String
    public var target: ModifierTarget
    public var amount: Int
    public var skillKey: String?
    public var condition: String?

    public init(
        id: UUID = UUID(),
        sourceName: String,
        target: ModifierTarget,
        amount: Int,
        skillKey: String? = nil,
        condition: String? = nil
    ) {
        self.id = id
        self.sourceName = sourceName
        self.target = target
        self.amount = amount
        self.skillKey = skillKey
        self.condition = condition
    }

    public var summary: String {
        let sign = amount >= 0 ? "+" : ""
        if target == .skill, let skillKey, !skillKey.isEmpty {
            return "\(sourceName): \(skillKey) \(sign)\(amount)"
        }
        return "\(sourceName): \(target.displayName) \(sign)\(amount)"
    }
}

public struct CharacterEffects: Sendable, Hashable {
    /// Attributes after permanent modifiers (augs, qualities, equipped gear, powers).
    public var effectiveAttributes: AttributeRatings
    public var attributeBonuses: [AttributeID: Int]
    /// Final armor value: max equipped armorRating + additive armor modifiers.
    public var armorBonus: Int
    public var initiativeBonus: Int
    public var initiativeDiceBonus: Int
    public var skillBonuses: [String: Int]
    public var limitBonuses: [ModifierTarget: Int]
    public var applied: [AppliedModifier]

    public init(
        effectiveAttributes: AttributeRatings = AttributeRatings(),
        attributeBonuses: [AttributeID: Int] = [:],
        armorBonus: Int = 0,
        initiativeBonus: Int = 0,
        initiativeDiceBonus: Int = 0,
        skillBonuses: [String: Int] = [:],
        limitBonuses: [ModifierTarget: Int] = [:],
        applied: [AppliedModifier] = []
    ) {
        self.effectiveAttributes = effectiveAttributes
        self.attributeBonuses = attributeBonuses
        self.armorBonus = armorBonus
        self.initiativeBonus = initiativeBonus
        self.initiativeDiceBonus = initiativeDiceBonus
        self.skillBonuses = skillBonuses
        self.limitBonuses = limitBonuses
        self.applied = applied
    }

    public func skillBonus(for skill: SkillRating) -> Int {
        let key = skill.catalogKey.lowercased()
        let name = skill.displayName.lowercased()
        var total = 0
        for (k, v) in skillBonuses {
            let lk = k.lowercased()
            if lk == key || lk == name || name.contains(lk) || lk.contains(name) {
                total += v
            }
        }
        return total
    }

    public func attributeBonus(for id: AttributeID) -> Int {
        attributeBonuses[id] ?? 0
    }
}

public enum CharacterEffectsEngine {
    /// Resolve all active modifiers on a character.
    /// - Note: `character.attributes` are treated as **base** (natural / unaugmented).
    public static func resolve(_ character: Character) -> CharacterEffects {
        var attrBonus: [AttributeID: Int] = [:]
        var initiativeBonus = 0
        var initiativeDiceBonus = 0
        var skillBonuses: [String: Int] = [:]
        var limitBonuses: [ModifierTarget: Int] = [:]
        var additiveArmor = 0
        var applied: [AppliedModifier] = []

        let sources: [any ModifierSource] =
            character.gear.map { $0 as any ModifierSource }
            + character.augmentations.map { $0 as any ModifierSource }
            + character.qualities.map { $0 as any ModifierSource }
            + character.adeptPowers.map { $0 as any ModifierSource }

        for source in sources where source.contributesModifiers {
            let rating = source.modifierRating
            for mod in source.modifiers {
                let amount = mod.resolvedAmount(rating: rating)
                guard amount != 0 else { continue }

                applied.append(
                    AppliedModifier(
                        sourceName: source.modifierSourceName,
                        target: mod.target,
                        amount: amount,
                        skillKey: mod.skillKey,
                        condition: mod.condition
                    )
                )

                if let attr = mod.target.attributeID {
                    attrBonus[attr, default: 0] += amount
                } else {
                    switch mod.target {
                    case .armor:
                        additiveArmor += amount
                    case .initiative:
                        initiativeBonus += amount
                    case .initiativeDice:
                        initiativeDiceBonus += amount
                    case .skill:
                        let key = (mod.skillKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !key.isEmpty {
                            skillBonuses[key, default: 0] += amount
                        }
                    case .physicalLimit, .mentalLimit, .socialLimit:
                        limitBonuses[mod.target, default: 0] += amount
                    default:
                        break
                    }
                }
            }
        }

        // Base armor = highest armorRating among equipped gear; additive mods stack on top.
        let baseArmor = character.gear
            .filter(\.equipped)
            .compactMap(\.armorRating)
            .max() ?? 0
        let totalArmor = baseArmor + additiveArmor

        if baseArmor > 0 {
            if let g = character.gear.first(where: { $0.equipped && $0.armorRating == baseArmor }) {
                applied.insert(
                    AppliedModifier(
                        sourceName: g.name,
                        target: .armor,
                        amount: baseArmor
                    ),
                    at: 0
                )
            }
        }

        var effective = character.attributes
        for (id, bonus) in attrBonus {
            effective[id] += bonus
        }

        return CharacterEffects(
            effectiveAttributes: effective,
            attributeBonuses: attrBonus,
            armorBonus: totalArmor,
            initiativeBonus: initiativeBonus,
            initiativeDiceBonus: initiativeDiceBonus,
            skillBonuses: skillBonuses,
            limitBonuses: limitBonuses,
            applied: applied
        )
    }

    /// Apply effects into derived stats (armor, initiative, pools, limits).
    public static func enhanceDerived(
        _ derived: DerivedStats,
        character: Character,
        effects: CharacterEffects
    ) -> DerivedStats {
        var d = derived
        let a = effects.effectiveAttributes

        d.armor = effects.armorBonus
        d.initiativeBase = a.reaction + a.intuition + effects.initiativeBonus
        d.initiativeDice = max(1, derived.initiativeDice + effects.initiativeDiceBonus)

        // Condition monitors from effective Body / Willpower.
        let phys = DerivedStatsCalculator.physicalBoxes(body: a.body)
        let stun = DerivedStatsCalculator.stunBoxes(willpower: a.willpower)
        d.condition = ConditionMonitor(
            physicalBoxes: phys,
            stunBoxes: stun,
            physicalFilled: min(character.physicalDamage, phys),
            stunFilled: min(character.stunDamage, stun),
            overflowBoxes: a.body
        )

        d.composure = DerivedStatsCalculator.composure(charisma: a.charisma, willpower: a.willpower)
        d.judgeIntentions = DerivedStatsCalculator.judgeIntentions(charisma: a.charisma, intuition: a.intuition)
        d.memory = DerivedStatsCalculator.memory(logic: a.logic, willpower: a.willpower)
        d.liftCarry = a.strength * 15
        d.movementWalk = a.agility * 2
        d.movementRun = a.agility * 4
        d.magicOrResonanceEffective = character.awakened.usesResonance ? a.resonance : a.magic

        var pools: [String: Int] = [:]
        // Active, knowledge, and language skills all roll attribute + skill (+ modifiers).
        for skill in character.skills where skill.rating > 0 {
            let linked = linkedAttribute(for: skill, attributes: a)
            let bonus = effects.skillBonus(for: skill)
            pools[skill.catalogKey] = linked + skill.rating + bonus
        }
        d.dicePools = pools

        if d.physicalLimit != nil {
            d.physicalLimit = DerivedStatsCalculator.physicalLimit(
                strength: a.strength,
                body: a.body,
                reaction: a.reaction
            )
            if let bonus = effects.limitBonuses[.physicalLimit] {
                d.physicalLimit = (d.physicalLimit ?? 0) + bonus
            }
            d.mentalLimit = DerivedStatsCalculator.mentalLimit(
                logic: a.logic,
                intuition: a.intuition,
                willpower: a.willpower
            )
            if let bonus = effects.limitBonuses[.mentalLimit] {
                d.mentalLimit = (d.mentalLimit ?? 0) + bonus
            }
            d.socialLimit = DerivedStatsCalculator.socialLimit(
                charisma: a.charisma,
                willpower: a.willpower,
                essence: d.currentEssence
            )
            if let bonus = effects.limitBonuses[.socialLimit] {
                d.socialLimit = (d.socialLimit ?? 0) + bonus
            }
        }

        return d
    }

    /// Convenience: resolve + enhance a rules-derived baseline.
    public static func playStats(
        for character: Character,
        baseDerived: DerivedStats
    ) -> DerivedStats {
        let effects = resolve(character)
        return enhanceDerived(baseDerived, character: character, effects: effects)
    }

    /// Linked attribute for dice pools (SR5-style: active skill hints + knowledge types).
    private static func linkedAttribute(for skill: SkillRating, attributes: AttributeRatings) -> Int {
        // Knowledge / language: attribute from knowledge type (core SR5).
        if skill.category == .knowledge || skill.category == .language {
            return knowledgeLinkedAttribute(skill: skill, attributes: attributes)
        }

        let key = skill.catalogKey.lowercased()
        let name = skill.displayName.lowercased()
        let blob = key + " " + name
        if blob.contains("pistol") || blob.contains("automatic") || blob.contains("longarm")
            || blob.contains("heavy_weapon") || blob.contains("sneak") || blob.contains("gym")
            || blob.contains("escape") || blob.contains("lock") || blob.contains("palming")
            || blob.contains("disguise") || blob.contains("imperson") {
            return attributes.agility
        }
        if blob.contains("unarmed") || blob.contains("blade") || blob.contains("club")
            || blob.contains("throw") || blob.contains("swim") || blob.contains("run") {
            return attributes.strength
        }
        if blob.contains("hack") || blob.contains("computer") || blob.contains("software")
            || blob.contains("cybercombat") || blob.contains("electronic") || blob.contains("hardware")
            || blob.contains("arcana") || blob.contains("aeronautics") || blob.contains("industrial") {
            return attributes.logic
        }
        if blob.contains("perception") || blob.contains("assense") || blob.contains("track")
            || blob.contains("navigation") || blob.contains("survival") || blob.contains("artisa") {
            return attributes.intuition
        }
        if blob.contains("con") || blob.contains("etiquette") || blob.contains("negotiation")
            || blob.contains("leadership") || blob.contains("instruction") || blob.contains("intimidation")
            || blob.contains("performance") {
            return attributes.charisma
        }
        if blob.contains("willpower") {
            return attributes.willpower
        }
        return attributes.reaction
    }

    /// SR5 knowledge categories: Academic/Professional → Logic; Street/Interest/Language → Intuition.
    private static func knowledgeLinkedAttribute(
        skill: SkillRating,
        attributes: AttributeRatings
    ) -> Int {
        let type = (skill.knowledgeType ?? "").lowercased()
        if skill.category == .language
            || type.contains("language")
            || type.contains("street")
            || type.contains("interest") {
            return attributes.intuition
        }
        if type.contains("academic") || type.contains("professional") {
            return attributes.logic
        }
        // Infer from name when Chummer didn't store a type.
        let name = skill.displayName.lowercased() + " " + skill.catalogKey.lowercased()
        if name.contains("haven") || name.contains("underworld") || name.contains("street")
            || name.contains("gang") || name.contains("syndicate") || name.contains("shadow")
            || name.contains("sprawl") || name.contains("nightlife") {
            return attributes.intuition
        }
        if name.contains("corp") || name.contains("science") || name.contains("history")
            || name.contains("matrix") || name.contains("magical") || name.contains("theory") {
            return attributes.logic
        }
        // Default knowledge: Intuition (common for street/interest lore).
        return attributes.intuition
    }

    // MARK: - Purchase

    /// Deduct nuyen for an item cost (qty × unit). Soft-fails if insufficient funds.
    public static func chargeNuyen(
        _ character: inout Character,
        unitCost: Int,
        quantity: Int = 1,
        itemName: String,
        allowDebt: Bool = false
    ) -> (charged: Int, message: String) {
        let total = max(0, unitCost) * max(1, quantity)
        guard total > 0 else {
            return (0, "\(itemName) added (no nuyen cost).")
        }
        if !allowDebt, character.nuyen < total {
            return (
                0,
                "Not enough nuyen for \(itemName) (need ¥\(total), have ¥\(character.nuyen)). Added without charging."
            )
        }
        character.nuyen -= total
        return (total, "Purchased \(itemName) for ¥\(total). Balance ¥\(character.nuyen).")
    }

    /// Refund nuyen when removing a previously purchased item.
    public static func refundNuyen(
        _ character: inout Character,
        unitCost: Int,
        quantity: Int = 1,
        itemName: String
    ) -> String {
        let total = max(0, unitCost) * max(1, quantity)
        guard total > 0 else { return "\(itemName) removed." }
        character.nuyen += total
        return "Refunded ¥\(total) for \(itemName). Balance ¥\(character.nuyen)."
    }
}

// MARK: - Character convenience

public extension Character {
    /// Base attributes (stored) + modifiers from inventory / augs / qualities / powers.
    var effects: CharacterEffects {
        CharacterEffectsEngine.resolve(self)
    }

    var effectiveAttributes: AttributeRatings {
        effects.effectiveAttributes
    }
}
