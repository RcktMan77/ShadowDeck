//
//  CampaignSheetReport.swift
//  ShadowDeck
//
//  Phase 9B — validation + snapshot used for PDF / Chummer export stamps.
//

import Foundation

public struct CampaignSheetReport: Sendable {
    public var character: Character
    public var effects: CharacterEffects
    public var derived: DerivedStats
    public var validation: ValidationResult
    public var houseRulesSummary: String
    public var generatedAt: Date

    public var isCampaignReady: Bool { validation.isValid }

    public static func build(for character: Character) -> CampaignSheetReport {
        let rules = RulesRegistry.rules(for: character.edition)
        let effects = CharacterEffectsEngine.resolve(character)
        let derived = rules.deriveStats(for: character)
        let validation = rules.validate(character)
        let hr: String
        if character.houseRules.enabled.isEmpty {
            hr = "Core book"
        } else {
            hr = HouseRuleID.allCases
                .filter { character.houseRules.isEnabled($0) }
                .map(\.displayName)
                .joined(separator: ", ")
        }
        return CampaignSheetReport(
            character: character,
            effects: effects,
            derived: derived,
            validation: validation,
            houseRulesSummary: hr,
            generatedAt: Date()
        )
    }

    public init(
        character: Character,
        effects: CharacterEffects,
        derived: DerivedStats,
        validation: ValidationResult,
        houseRulesSummary: String,
        generatedAt: Date
    ) {
        self.character = character
        self.effects = effects
        self.derived = derived
        self.validation = validation
        self.houseRulesSummary = houseRulesSummary
        self.generatedAt = generatedAt
    }
}
