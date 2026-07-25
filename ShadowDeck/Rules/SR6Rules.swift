//
//  SR6Rules.swift
//  ShadowDeck
//
//  Shadowrun 6th Edition (Sixth World) core rules strategy.
//  Default generation: Priority. Edge is a session pool; classic limits are not used.
//

import Foundation

public struct SR6Rules: EditionRules {
    public let edition: Edition = .sr6

    public var defaultGenerationSystem: GenerationSystem { .priority }
    public var standardBuildPointBudget: Int { 0 }
    public var standardPriorityKarma: Int { 50 }
    public var positiveQualityKarmaCap: Int { 20 }
    public var negativeQualityKarmaCap: Int { 20 }

    public init() {}

    public func metatypeProfile(_ metatype: MetatypeID) -> MetatypeProfile {
        MetatypeCatalog.profile(for: metatype, edition: .sr6)
    }

    public func attributePoints(for priority: PriorityLetter) -> Int? {
        // SR6 core Attributes column (approximate core table).
        switch priority {
        case .a: 24
        case .b: 16
        case .c: 12
        case .d: 8
        case .e: 2
        }
    }

    public func specialAttributePoints(for priority: PriorityLetter, metatype: MetatypeID) -> Int? {
        // SR6 uses adjustment points tied to metatype priority.
        switch metatype {
        case .human:
            switch priority {
            case .a: 13
            case .b: 11
            case .c: 9
            case .d: 4
            case .e: 1
            }
        case .elf:
            switch priority {
            case .a: 11
            case .b: 8
            case .c: 6
            case .d: 3
            case .e: nil
            }
        case .dwarf:
            switch priority {
            case .a: 11
            case .b: 8
            case .c: 5
            case .d: 1
            case .e: nil
            }
        case .ork:
            switch priority {
            case .a: 11
            case .b: 8
            case .c: 5
            case .d: 1
            case .e: nil
            }
        case .troll:
            switch priority {
            case .a: 11
            case .b: 7
            case .c: 4
            case .d: 0
            case .e: nil
            }
        }
    }

    public func resourceNuyen(for priority: PriorityLetter) -> Int? {
        switch priority {
        case .a: 450_000
        case .b: 275_000
        case .c: 150_000
        case .d: 50_000
        case .e: 8_000
        }
    }

    public func skillPoints(for priority: PriorityLetter) -> (skills: Int, groups: Int)? {
        // SR6 collapsed many skills; treat as skill points (groups less central).
        switch priority {
        case .a: (32, 0)
        case .b: (24, 0)
        case .c: (20, 0)
        case .d: (16, 0)
        case .e: (10, 0)
        }
    }

    public func karmaCostToRaiseAttribute(from current: Int) -> Int {
        // SR6 attribute advancement: new rating × 5
        (current + 1) * 5
    }

    public func karmaCostToRaiseSkill(from current: Int) -> Int {
        // SR6 skill: new rating × 5 (skills are broader)
        (current + 1) * 5
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

        // SR6 initiative: Reaction + Intuition, with Edge-centric combat flow.
        var pools: [String: Int] = [:]
        for skill in character.skills where skill.category == .active {
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
        guard character.edition == .sr6 else {
            result.error("edition.mismatch", "SR6Rules received a \(character.edition.rawValue) character.")
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
                let allowedExtra = character.houseRules.isEnabled(.exceptionalAttributeAtChargen) ? 1 : 0
                if value > bounds.maximum + allowedExtra || value < bounds.minimum {
                    result.error(
                        "attribute.bounds",
                        "\(attr.displayName) (\(value)) outside allowed range for \(character.metatype.displayName).",
                        field: attr.rawValue
                    )
                }
            }
        }

        // Edge is central in SR6 — warn if neglected.
        if character.attributes.edge < 2 {
            result.warning("edge.low", "Edge below 2 is unusually low for SR6 play.")
        }

        if character.awakened.usesMagic && character.attributes.magic < 1 {
            result.error("magic.missing", "Awakened path requires Magic ≥ 1.", field: "magic")
        }
        if character.awakened.usesResonance && character.attributes.resonance < 1 {
            result.error("resonance.missing", "Technomancer requires Resonance ≥ 1.", field: "resonance")
        }

        let essence = computeEssence(for: character)
        if essence <= 0 {
            result.error("essence.nonpositive", "Essence must remain above 0.")
        }

        let derived = deriveStats(for: character)
        if derived.physicalLimit != nil || derived.mentalLimit != nil || derived.socialLimit != nil {
            result.warning("limits.unexpected", "SR6 does not use classic Physical/Mental/Social limits.")
        }

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

        validatePriority(character, into: &result)
        return result
    }

    private func validatePriority(_ character: Character, into result: inout ValidationResult) {
        let system = character.generation.system
        guard system == .priority || system == .sumToTen || character.houseRules.isEnabled(.sumToTen) else {
            return
        }

        let assignment = character.generation.priority
        guard assignment.isComplete else {
            result.warning("priority.incomplete", "Priority assignment is incomplete.")
            return
        }

        let sumToTen = system == .sumToTen || character.houseRules.isEnabled(.sumToTen)
        if sumToTen {
            if assignment.sumToTenTotal != 10 {
                result.error(
                    "priority.sum_to_ten",
                    "Sum-to-Ten total is \(assignment.sumToTenTotal); expected 10."
                )
            }
        } else if !assignment.usesUniqueLetters {
            result.error("priority.unique", "Core priority requires unique A–E letters.")
        }

        if let metaPriority = assignment[.metatype],
           specialAttributePoints(for: metaPriority, metatype: character.metatype) == nil {
            result.error(
                "metatype.priority",
                "\(character.metatype.displayName) is not available at metatype priority \(metaPriority.rawValue)."
            )
        }
    }

    private func linkedAttributeHint(for catalogKey: String, attributes: AttributeRatings) -> Int {
        let key = catalogKey.lowercased()
        if key.contains("firearms") || key.contains("close") || key.contains("athletics") {
            return attributes.agility
        }
        if key.contains("stealth") || key.contains("piloting") {
            return attributes.reaction
        }
        if key.contains("perception") || key.contains("astral") {
            return attributes.intuition
        }
        if key.contains("influence") || key.contains("con") {
            return attributes.charisma
        }
        if key.contains("cracking") || key.contains("electronics") || key.contains("engineering") {
            return attributes.logic
        }
        return attributes.logic
    }
}
