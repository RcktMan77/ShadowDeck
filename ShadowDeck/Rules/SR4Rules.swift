//
//  SR4Rules.swift
//  ShadowDeck
//
//  Shadowrun 4th Edition (SR4A-oriented) core rules strategy.
//  Default generation: Build Points (400). Karma gen supported as peer path.
//

import Foundation

public struct SR4Rules: EditionRules {
    public let edition: Edition = .sr4

    public var defaultGenerationSystem: GenerationSystem { .buildPoints }
    public var standardBuildPointBudget: Int { 400 }
    public var standardPriorityKarma: Int { 0 }
    public var positiveQualityKarmaCap: Int { 35 }
    public var negativeQualityKarmaCap: Int { 35 }

    public init() {}

    public func metatypeProfile(_ metatype: MetatypeID) -> MetatypeProfile {
        MetatypeCatalog.profile(for: metatype, edition: .sr4)
    }

    // Optional priority table for tables that prefer it; BP remains default.
    public func attributePoints(for priority: PriorityLetter) -> Int? {
        switch priority {
        case .a: 24
        case .b: 20
        case .c: 16
        case .d: 14
        case .e: 12
        }
    }

    public func specialAttributePoints(for priority: PriorityLetter, metatype: MetatypeID) -> Int? {
        // Simplified special-point guidance when using priority with SR4.
        switch (priority, metatype) {
        case (.a, .human): 5
        case (.b, .human): 3
        case (.c, .human): 2
        case (.d, .human): 1
        case (.e, .human): 0
        case (.a, _): 4
        case (.b, _): 3
        case (.c, _): 2
        case (.d, _): 1
        case (.e, _): 0
        }
    }

    public func resourceNuyen(for priority: PriorityLetter) -> Int? {
        switch priority {
        case .a: 1_000_000
        case .b: 400_000
        case .c: 90_000
        case .d: 20_000
        case .e: 5_000
        }
    }

    public func skillPoints(for priority: PriorityLetter) -> (skills: Int, groups: Int)? {
        switch priority {
        case .a: (50, 0)
        case .b: (40, 0)
        case .c: (34, 0)
        case .d: (30, 0)
        case .e: (26, 0)
        }
    }

    public func karmaCostToRaiseAttribute(from current: Int) -> Int {
        // SR4A: new rating × 5
        (current + 1) * 5
    }

    public func karmaCostToRaiseSkill(from current: Int) -> Int {
        // SR4A active skill: new rating × 2
        (current + 1) * 2
    }

    public func computeEssence(for character: Character) -> Decimal {
        let lost = DerivedStatsCalculator.totalEssenceCost(
            augmentations: character.augmentations,
            houseRules: character.houseRules
        )
        return max(0, AttributeRatings.naturalEssenceBaseline - lost)
    }

    public func deriveStats(for character: Character) -> DerivedStats {
        let a = character.attributes
        let essence = computeEssence(for: character)
        let phys = DerivedStatsCalculator.physicalBoxes(body: a.body)
        let stun = DerivedStatsCalculator.stunBoxes(willpower: a.willpower)

        var pools: [String: Int] = [:]
        for skill in character.skills where skill.category == .active {
            // Placeholder linked attribute: use Reaction for combat-ish keys, Logic otherwise.
            let linked = linkedAttributeHint(for: skill.catalogKey, attributes: a)
            pools[skill.catalogKey] = DerivedStatsCalculator.dicePool(attribute: linked, skill: skill.rating)
        }

        return DerivedStats(
            initiativeDice: 1,
            initiativeBase: DerivedStatsCalculator.initiativeBase(reaction: a.reaction, intuition: a.intuition),
            composure: DerivedStatsCalculator.composure(charisma: a.charisma, willpower: a.willpower),
            judgeIntentions: DerivedStatsCalculator.judgeIntentions(charisma: a.charisma, intuition: a.intuition),
            memory: DerivedStatsCalculator.memory(logic: a.logic, willpower: a.willpower),
            liftCarry: a.strength * 15,
            movementWalk: a.agility * 2,
            movementRun: a.agility * 4,
            physicalLimit: nil,
            mentalLimit: nil,
            socialLimit: nil,
            condition: ConditionMonitor(
                physicalBoxes: phys,
                stunBoxes: stun,
                overflowBoxes: a.body
            ),
            currentEssence: essence,
            magicOrResonanceEffective: character.awakened.usesResonance ? a.resonance : a.magic,
            armor: DerivedStatsCalculator.equippedArmor(from: character.gear),
            dicePools: pools
        )
    }

    public func validate(_ character: Character) -> ValidationResult {
        var result = ValidationResult()
        guard character.edition == .sr4 else {
            result.error("edition.mismatch", "SR4Rules received a \(character.edition.rawValue) character.")
            return result
        }

        if character.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.error("identity.name", "Character name is required.", field: "name")
        }

        let profile = metatypeProfile(character.metatype)
        for attr in AttributeID.standardGenerationAttributes + [.edge] {
            let value = character.attributes[attr]
            let bounds = profile.bounds(for: attr)
            if !bounds.contains(value) {
                result.error(
                    "attribute.bounds",
                    "\(attr.displayName) (\(value)) outside \(character.metatype.displayName) range \(bounds.minimum)–\(bounds.maximum).",
                    field: attr.rawValue
                )
            }
        }

        if character.awakened.usesMagic && character.attributes.magic < 1 {
            result.error("magic.missing", "Awakened path requires Magic ≥ 1.", field: "magic")
        }
        if character.awakened.usesResonance && character.attributes.resonance < 1 {
            result.error("resonance.missing", "Technomancer requires Resonance ≥ 1.", field: "resonance")
        }
        if character.awakened == .mundane {
            if character.attributes.magic > 0 {
                result.warning("magic.mundane", "Mundane character has Magic > 0.")
            }
            if character.attributes.resonance > 0 {
                result.warning("resonance.mundane", "Mundane character has Resonance > 0.")
            }
        }

        let essence = computeEssence(for: character)
        if essence < 0 {
            result.error("essence.negative", "Essence cannot be negative.")
        }
        if essence == 0 {
            result.warning("essence.zero", "Essence is 0 — character is dying / dead under core rules.")
        }

        // Qualities budget (core + house rule cap).
        let posCap = character.houseRules.positiveQualityKarmaCap ?? positiveQualityKarmaCap
        let positiveSpend = character.qualities
            .filter { $0.kind == .positive }
            .reduce(0) { $0 + $1.karmaValue }
        if positiveSpend > posCap {
            result.error(
                "qualities.positive_cap",
                "Positive qualities cost \(positiveSpend) karma; cap is \(posCap)."
            )
        }

        if character.generation.system == .buildPoints {
            if character.generation.buildPointBudget <= 0 {
                result.warning("bp.budget", "Build point budget is not set.")
            }
            if character.generation.buildPointsSpent > character.generation.buildPointBudget {
                result.error(
                    "bp.overspent",
                    "Spent \(character.generation.buildPointsSpent) BP of \(character.generation.buildPointBudget)."
                )
            }
        }

        validatePriorityIfNeeded(character, into: &result)
        return result
    }

    private func validatePriorityIfNeeded(_ character: Character, into result: inout ValidationResult) {
        let system = character.generation.system
        guard system == .priority || system == .sumToTen else { return }
        let assignment = character.generation.priority
        guard assignment.isComplete else {
            result.warning("priority.incomplete", "Priority assignment is incomplete.")
            return
        }
        if system == .priority && !assignment.usesUniqueLetters {
            result.error("priority.unique", "Core priority requires unique A–E letters.")
        }
        if system == .sumToTen || character.houseRules.isEnabled(.sumToTen) {
            let total = assignment.sumToTenTotal
            if total != 10 {
                result.error("priority.sum_to_ten", "Sum-to-Ten total is \(total); expected 10.")
            }
        }
    }

    private func linkedAttributeHint(for catalogKey: String, attributes: AttributeRatings) -> Int {
        let key = catalogKey.lowercased()
        if key.contains("sneak") || key.contains("gym") || key.contains("athletic") {
            return attributes.agility
        }
        if key.contains("pistol") || key.contains("automatic") || key.contains("longarms") || key.contains("heavy") {
            return attributes.agility
        }
        if key.contains("unarm") || key.contains("blade") || key.contains("club") {
            return attributes.agility
        }
        if key.contains("perception") || key.contains("assensing") {
            return attributes.intuition
        }
        if key.contains("negotiate") || key.contains("etiquette") || key.contains("leadership") {
            return attributes.charisma
        }
        return attributes.logic
    }
}
