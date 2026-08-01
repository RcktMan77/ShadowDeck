//
//  DicePoolResolver.swift
//  ShadowDeck
//
//  Resolve skill/attribute dice pools for one-click roller launch.
//

import Foundation

public enum DicePoolResolver {
    public static func skillPool(character: Character, skill: SkillRating) -> (pool: Int, label: String) {
        let rules = RulesRegistry.rules(for: character.edition)
        let derived = rules.deriveStats(for: character)
        let pool = derived.dicePools[skill.catalogKey]
            ?? fallbackSkillPool(character: character, skill: skill)
        let label = "\(skill.displayName) · pool \(pool)"
        return (pool, label)
    }

    public static func attributePool(character: Character, attribute: AttributeID) -> (pool: Int, label: String) {
        let effective = character.effectiveAttributes[attribute]
        let label = "\(attribute.displayName) · pool \(effective)"
        return (max(0, effective), label)
    }

    public static func edgeRating(character: Character) -> Int {
        max(0, character.effectiveAttributes.edge)
    }

    private static func fallbackSkillPool(character: Character, skill: SkillRating) -> Int {
        let attrID = AdvancementGuidance.linkedAttributeID(for: skill)
        let attr = character.effectiveAttributes[attrID]
        return DerivedStatsCalculator.dicePool(attribute: attr, skill: skill.rating)
    }
}
