//
//  SR5Rules.swift
//  ShadowDeck
//
//  Shadowrun 5th Edition core rules strategy.
//  Default generation: Priority. Limits are first-class derived stats.
//

import Foundation

public struct SR5Rules: EditionRules {
    public let edition: Edition = .sr5

    public var defaultGenerationSystem: GenerationSystem { .priority }
    public var standardBuildPointBudget: Int { 0 }
    public var standardPriorityKarma: Int { 25 }
    public var positiveQualityKarmaCap: Int { 25 }
    public var negativeQualityKarmaCap: Int { 25 }

    public init() {}

    public func metatypeProfile(_ metatype: MetatypeID) -> MetatypeProfile {
        MetatypeCatalog.profile(for: metatype, edition: .sr5)
    }

    public func attributePoints(for priority: PriorityLetter) -> Int? {
        // SR5 core priority table — Attributes column.
        switch priority {
        case .a: 24
        case .b: 20
        case .c: 16
        case .d: 14
        case .e: 12
        }
    }

    public func specialAttributePoints(for priority: PriorityLetter, metatype: MetatypeID) -> Int? {
        // Simplified from SR5 Metatype column (special attribute points in parentheses).
        // Full table is data-driven later; these cover core metatype × priority peers.
        switch metatype {
        case .human:
            switch priority {
            case .a: 9
            case .b: 7
            case .c: 5
            case .d: 3
            case .e: 1
            }
        case .elf:
            switch priority {
            case .a: 8
            case .b: 6
            case .c: 4
            case .d: 2
            case .e: nil // typically unavailable at E for non-human in core
            }
        case .dwarf:
            switch priority {
            case .a: 7
            case .b: 4
            case .c: 1
            case .d, .e: nil
            }
        case .ork:
            switch priority {
            case .a: 7
            case .b: 4
            case .c: 0
            case .d, .e: nil
            }
        case .troll:
            switch priority {
            case .a: 5
            case .b: 0
            case .c, .d, .e: nil
            }
        }
    }

    public func resourceNuyen(for priority: PriorityLetter) -> Int? {
        switch priority {
        case .a: 450_000
        case .b: 275_000
        case .c: 140_000
        case .d: 50_000
        case .e: 6_000
        }
    }

    public func skillPoints(for priority: PriorityLetter) -> (skills: Int, groups: Int)? {
        switch priority {
        case .a: (46, 10)
        case .b: (36, 5)
        case .c: (28, 2)
        case .d: (22, 0)
        case .e: (18, 0)
        }
    }

    public func karmaCostToRaiseAttribute(from current: Int) -> Int {
        // SR5: new rating × 5
        (current + 1) * 5
    }

    public func karmaCostToRaiseSkill(from current: Int) -> Int {
        // SR5 active: new rating × 2
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
        // Baseline from base attributes; effects engine applies gear/aug/quality/power mods.
        let a = character.attributes
        let essence = computeEssence(for: character)
        let phys = DerivedStatsCalculator.physicalBoxes(body: a.body)
        let stun = DerivedStatsCalculator.stunBoxes(willpower: a.willpower)

        var pools: [String: Int] = [:]
        // Effects engine rebuilds pools for all categories; keep a baseline for active skills here.
        for skill in character.skills where skill.category == .active && skill.rating > 0 {
            let linked = linkedAttributeHint(for: skill.catalogKey, attributes: a)
            pools[skill.catalogKey] = DerivedStatsCalculator.dicePool(attribute: linked, skill: skill.rating)
        }

        let baseline = DerivedStats(
            initiativeDice: 1,
            initiativeBase: DerivedStatsCalculator.initiativeBase(reaction: a.reaction, intuition: a.intuition),
            composure: DerivedStatsCalculator.composure(charisma: a.charisma, willpower: a.willpower),
            judgeIntentions: DerivedStatsCalculator.judgeIntentions(charisma: a.charisma, intuition: a.intuition),
            memory: DerivedStatsCalculator.memory(logic: a.logic, willpower: a.willpower),
            liftCarry: a.strength * 15,
            movementWalk: a.agility * 2,
            movementRun: a.agility * 4,
            physicalLimit: DerivedStatsCalculator.physicalLimit(
                strength: a.strength, body: a.body, reaction: a.reaction
            ),
            mentalLimit: DerivedStatsCalculator.mentalLimit(
                logic: a.logic, intuition: a.intuition, willpower: a.willpower
            ),
            socialLimit: DerivedStatsCalculator.socialLimit(
                charisma: a.charisma, willpower: a.willpower, essence: essence
            ),
            condition: ConditionMonitor(
                physicalBoxes: phys,
                stunBoxes: stun,
                physicalFilled: min(character.physicalDamage, phys),
                stunFilled: min(character.stunDamage, stun),
                overflowBoxes: a.body
            ),
            currentEssence: essence,
            magicOrResonanceEffective: character.awakened.usesResonance ? a.resonance : a.magic,
            armor: DerivedStatsCalculator.equippedArmor(from: character.gear),
            dicePools: pools
        )
        return CharacterEffectsEngine.playStats(for: character, baseDerived: baseline)
    }

    public func validate(_ character: Character) -> ValidationResult {
        var result = ValidationResult()
        guard character.edition == .sr5 else {
            result.error("edition.mismatch", "SR5Rules received a \(character.edition.rawValue) character.")
            return result
        }

        if character.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.error("identity.name", "Character name is required.", field: "name")
        }

        // Validate effective (base + modifiers) against augmented play bounds.
        let profile = metatypeProfile(character.metatype)
        let effective = character.effectiveAttributes
        for attr in AttributeID.standardGenerationAttributes + [.edge] {
            let value = effective[attr]
            let bounds = profile.bounds(for: attr)
            if ValidationHelpers.attributeOutOfPlayBounds(
                value: value,
                bounds: bounds,
                houseRules: character.houseRules
            ) {
                let maxAllowed = ValidationHelpers.augmentedAttributeMaximum(
                    naturalMaximum: bounds.maximum,
                    houseRules: character.houseRules
                )
                result.error(
                    "attribute.bounds",
                    "\(attr.displayName) (\(value)) outside allowed range \(bounds.minimum)–\(maxAllowed) for \(character.metatype.displayName) (natural max \(bounds.maximum) + augs).",
                    field: attr.rawValue
                )
            }
        }

        if character.awakened.usesMagic && effective.magic < 1 {
            result.error("magic.missing", "Awakened path requires Magic ≥ 1.", field: "magic")
        }
        if character.awakened.usesResonance && character.attributes.resonance < 1 {
            result.error("resonance.missing", "Technomancer requires Resonance ≥ 1.", field: "resonance")
        }

        let essence = computeEssence(for: character)
        if essence <= 0 {
            result.error("essence.nonpositive", "Essence must remain above 0.")
        }

        // SR5 uses limits — ensure derivation produces them.
        let derived = deriveStats(for: character)
        if derived.physicalLimit == nil || derived.mentalLimit == nil || derived.socialLimit == nil {
            result.error("limits.missing", "SR5 characters must have Physical, Mental, and Social limits.")
        }

        let posCap = character.houseRules.positiveQualityKarmaCap ?? positiveQualityKarmaCap
        // Exclude free path qualities (Adept / Magician / Technomancer / …) from the budget.
        let positiveSpend = ValidationHelpers.positiveQualityKarmaSpend(qualities: character.qualities)
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
        let usesPriority = system == .priority || system == .sumToTen
            || character.houseRules.isEnabled(.sumToTen)
        guard usesPriority || system == .priority else {
            if system == .karmaGen || character.houseRules.isEnabled(.karmaGeneration) {
                let budget = character.houseRules.isEnabled(.karmaGeneration)
                    ? character.houseRules.karmaGenBudget
                    : character.generation.karmaBudget
                if character.generation.karmaSpent > budget && budget > 0 {
                    result.error("karma.overspent", "Karma spent exceeds karmagen budget (\(budget)).")
                }
            }
            return
        }

        let assignment = character.generation.priority
        guard assignment.isComplete else {
            result.warning("priority.incomplete", "Priority assignment is incomplete.")
            return
        }

        let sumToTen = system == .sumToTen || character.houseRules.isEnabled(.sumToTen)
        if sumToTen {
            let total = assignment.sumToTenTotal
            if total != 10 {
                result.error("priority.sum_to_ten", "Sum-to-Ten total is \(total); expected 10.")
            }
        } else if !assignment.usesUniqueLetters {
            result.error("priority.unique", "Core priority requires unique A–E letters.")
        }

        // Metatype availability: non-humans need sufficient metatype priority.
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
        if key.contains("pistol") || key.contains("automatic") || key.contains("longarms") {
            return attributes.agility
        }
        if key.contains("sneaking") || key.contains("gymnastics") {
            return attributes.agility
        }
        if key.contains("perception") {
            return attributes.intuition
        }
        if key.contains("negotiation") || key.contains("etiquette") {
            return attributes.charisma
        }
        if key.contains("computer") || key.contains("software") || key.contains("cybercombat") {
            return attributes.logic
        }
        return attributes.logic
    }
}
