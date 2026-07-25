//
//  GenerationDraft.swift
//  ShadowDeck
//
//  In-progress character creation state for the multi-page wizard.
//

import Foundation
import Observation

public enum GenerationStep: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case edition
    case concept
    case metatype
    case priorities
    case attributes
    case magic
    case skills
    case qualities
    case resources
    case finish

    public var id: Int { rawValue }

    public static func < (lhs: GenerationStep, rhs: GenerationStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .edition: "Edition"
        case .concept: "Concept"
        case .metatype: "Metatype"
        case .priorities: "Priorities"
        case .attributes: "Attributes"
        case .magic: "Magic / Resonance"
        case .skills: "Skills"
        case .qualities: "Qualities"
        case .resources: "Resources"
        case .finish: "Finish"
        }
    }

    public var systemImage: String {
        switch self {
        case .edition: "books.vertical"
        case .concept: "theatermasks"
        case .metatype: "person.3"
        case .priorities: "list.number"
        case .attributes: "figure.stand"
        case .magic: "sparkles"
        case .skills: "hammer"
        case .qualities: "star.circle"
        case .resources: "yensign.circle"
        case .finish: "checkmark.seal"
        }
    }
}

@Observable
@MainActor
public final class GenerationDraft {
    public var step: GenerationStep = .edition

    public var edition: Edition = .sr5
    public var houseRules: HouseRules = .coreBook
    public var archetype: RunnerArchetype = .streetSamurai
    public var name: String = ""
    public var streetName: String = ""
    public var concept: String = ""
    public var metatype: MetatypeID = .human
    public var awakened: AwakenedPath = .mundane
    public var generationSystem: GenerationSystem = .priority
    public var priority: PriorityAssignment = PriorityAssignment()
    public var attributes: AttributeRatings = AttributeRatings()
    public var skills: [SkillRating] = []
    public var qualities: [QualityInstance] = []
    public var nuyen: Int = 0
    public var notes: String = ""
    public var avatarData: Data?

    /// Attribute ranks purchased above metatype minimum (for point tracking).
    public var attributePurchases: [AttributeID: Int] = [:]
    public var specialPurchases: [AttributeID: Int] = [:]
    public var skillRanks: [String: Int] = [:]

    public var budget: GenerationBudget = GenerationBudget()

    public var rules: any EditionRules { RulesRegistry.rules(for: edition) }

    public init() {
        applyEditionDefaults()
    }

    public var steps: [GenerationStep] {
        // Magic step is always present; content adapts to awakened path.
        GenerationStep.allCases
    }

    public var canGoNext: Bool {
        switch step {
        case .edition, .concept, .metatype, .magic, .qualities, .resources:
            return true
        case .priorities:
            if generationSystem == .buildPoints || generationSystem == .karmaGen || generationSystem == .pointBuy {
                return true
            }
            return priority.isComplete && priorityValid
        case .attributes:
            return budget.attributePointsRemaining >= 0
        case .skills:
            return budget.skillPointsRemaining >= 0
        case .finish:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var priorityValid: Bool {
        if generationSystem == .sumToTen || houseRules.isEnabled(.sumToTen) {
            return priority.isComplete && priority.sumToTenTotal == 10
        }
        return priority.isComplete && priority.usesUniqueLetters
    }

    public func goNext() {
        guard canGoNext, let idx = steps.firstIndex(of: step), idx + 1 < steps.count else { return }
        // Recompute budgets when leaving priorities / metatype.
        if step == .priorities || step == .metatype || step == .edition {
            recomputeBudgetsFromPriorities()
        }
        step = steps[idx + 1]
        if step == .concept {
            concept = archetype.displayName
            awakened = archetype.defaultAwakened
        }
    }

    public func goBack() {
        guard let idx = steps.firstIndex(of: step), idx > 0 else { return }
        step = steps[idx - 1]
    }

    public func applyEditionDefaults() {
        generationSystem = rules.defaultGenerationSystem
        budget.positiveQualityKarmaCap = houseRules.positiveQualityKarmaCap ?? rules.positiveQualityKarmaCap
        budget.negativeQualityKarmaCap = rules.negativeQualityKarmaCap
        if generationSystem == .buildPoints {
            budget.resetBuildPoints(total: rules.standardBuildPointBudget)
        }
        recomputeBudgetsFromPriorities()
        resetAttributesToMinima()
    }

    public func selectEdition(_ newEdition: Edition) {
        edition = newEdition
        applyEditionDefaults()
    }

    public func selectArchetype(_ newArchetype: RunnerArchetype) {
        archetype = newArchetype
        concept = newArchetype.displayName
        awakened = newArchetype.defaultAwakened
        if awakened.usesMagic && attributes.magic < 1 {
            attributes.magic = 1
        }
        if awakened.usesResonance && attributes.resonance < 1 {
            attributes.resonance = 1
        }
    }

    public func selectMetatype(_ newMetatype: MetatypeID) {
        metatype = newMetatype
        resetAttributesToMinima()
        recomputeBudgetsFromPriorities()
    }

    public func assignPriority(_ letter: PriorityLetter, to column: PriorityColumn) {
        if generationSystem == .priority && !houseRules.isEnabled(.sumToTen) {
            // Enforce unique letters: clear other columns using this letter.
            for col in PriorityColumn.allCases where col != column {
                if priority[col] == letter {
                    priority[col] = nil
                }
            }
        }
        priority[column] = letter
        recomputeBudgetsFromPriorities()
    }

    public func recomputeBudgetsFromPriorities() {
        let r = rules
        budget.positiveQualityKarmaCap = houseRules.positiveQualityKarmaCap ?? r.positiveQualityKarmaCap
        budget.negativeQualityKarmaCap = r.negativeQualityKarmaCap

        if generationSystem == .buildPoints {
            budget.resetBuildPoints(total: r.standardBuildPointBudget)
            // Approximate attribute pool for BP tables (player still tracks BP holistically later).
            budget.resetAttributes(total: 200) // BP-ish placeholder pool UI for attrs; refined later
            budget.resetSkills(points: 100, groups: 0)
            budget.resetNuyen(total: 5_000)
            budget.karmaTotal = r.standardPriorityKarma + (houseRules.isEnabled(.bonusStartingKarma) ? houseRules.bonusKarma : 0)
            budget.karmaRemaining = budget.karmaTotal
            return
        }

        if let attrLetter = priority[.attributes], let pts = r.attributePoints(for: attrLetter) {
            budget.resetAttributes(total: pts)
        } else {
            budget.resetAttributes(total: 0)
        }

        if let metaLetter = priority[.metatype],
           let special = r.specialAttributePoints(for: metaLetter, metatype: metatype)
        {
            budget.resetSpecial(total: special)
        } else {
            budget.resetSpecial(total: 0)
        }

        if let skillLetter = priority[.skills], let sk = r.skillPoints(for: skillLetter) {
            budget.resetSkills(points: sk.skills, groups: sk.groups)
        } else {
            budget.resetSkills(points: 0, groups: 0)
        }

        if let resLetter = priority[.resources], let nuyen = r.resourceNuyen(for: resLetter) {
            budget.resetNuyen(total: nuyen)
            self.nuyen = nuyen
        } else {
            budget.resetNuyen(total: 0)
            self.nuyen = 0
        }

        budget.karmaTotal = r.standardPriorityKarma
        if houseRules.isEnabled(.bonusStartingKarma) || houseRules.isEnabled(.primeRunnerPackage) {
            budget.karmaTotal += houseRules.bonusKarma
        }
        budget.karmaRemaining = budget.karmaTotal

        // Re-apply purchase spending to remaining counters.
        recomputeAttributeRemaining()
        recomputeSkillRemaining()
    }

    public func resetAttributesToMinima() {
        let profile = MetatypeCatalog.profile(for: metatype, edition: edition)
        for id in AttributeID.standardGenerationAttributes {
            let min = profile.bounds(for: id).minimum
            attributes[id] = min
            attributePurchases[id] = 0
        }
        attributes.edge = profile.bounds(for: .edge).minimum
        specialPurchases[.edge] = 0
        attributes.magic = awakened.usesMagic ? max(1, attributes.magic) : 0
        attributes.resonance = awakened.usesResonance ? max(1, attributes.resonance) : 0
        attributes.essence = AttributeRatings.naturalEssenceBaseline
        recomputeAttributeRemaining()
    }

    public func canIncreaseAttribute(_ id: AttributeID) -> Bool {
        let profile = MetatypeCatalog.profile(for: metatype, edition: edition)
        let bounds = profile.bounds(for: id)
        let current = attributes[id]
        guard current < bounds.maximum else { return false }
        if AttributeID.standardGenerationAttributes.contains(id) {
            return budget.attributePointsRemaining > 0
        }
        if id == .edge || id == .magic || id == .resonance {
            return budget.specialPointsRemaining > 0
        }
        return false
    }

    public func canDecreaseAttribute(_ id: AttributeID) -> Bool {
        let profile = MetatypeCatalog.profile(for: metatype, edition: edition)
        let min = profile.bounds(for: id).minimum
        // Magic/Resonance minimum 1 if path requires.
        if id == .magic && awakened.usesMagic { return attributes.magic > 1 }
        if id == .resonance && awakened.usesResonance { return attributes.resonance > 1 }
        return attributes[id] > min
    }

    public func increaseAttribute(_ id: AttributeID) {
        guard canIncreaseAttribute(id) else { return }
        attributes[id] += 1
        if AttributeID.standardGenerationAttributes.contains(id) {
            attributePurchases[id, default: 0] += 1
            budget.attributePointsRemaining -= 1
        } else {
            specialPurchases[id, default: 0] += 1
            budget.specialPointsRemaining -= 1
        }
    }

    public func decreaseAttribute(_ id: AttributeID) {
        guard canDecreaseAttribute(id) else { return }
        attributes[id] -= 1
        if AttributeID.standardGenerationAttributes.contains(id) {
            attributePurchases[id, default: 0] = max(0, (attributePurchases[id] ?? 0) - 1)
            budget.attributePointsRemaining += 1
        } else {
            specialPurchases[id, default: 0] = max(0, (specialPurchases[id] ?? 0) - 1)
            budget.specialPointsRemaining += 1
        }
    }

    public func setSkillRank(catalogKey: String, displayName: String, rank: Int, category: SkillCategory = .active) {
        let clamped = max(0, min(rank, 6))
        let previous = skillRanks[catalogKey] ?? 0
        let delta = clamped - previous
        guard delta != 0 else { return }
        if delta > 0 {
            guard budget.skillPointsRemaining >= delta else { return }
            budget.skillPointsRemaining -= delta
        } else {
            budget.skillPointsRemaining -= delta // delta negative → add back
        }
        skillRanks[catalogKey] = clamped
        if clamped == 0 {
            skills.removeAll { $0.catalogKey == catalogKey }
        } else if let idx = skills.firstIndex(where: { $0.catalogKey == catalogKey }) {
            skills[idx].rating = clamped
        } else {
            skills.append(
                SkillRating(
                    catalogKey: catalogKey,
                    displayName: displayName,
                    category: category,
                    rating: clamped
                )
            )
        }
    }

    public func canIncreaseSkill(catalogKey: String) -> Bool {
        let current = skillRanks[catalogKey] ?? 0
        return current < 6 && budget.skillPointsRemaining > 0
    }

    public func canDecreaseSkill(catalogKey: String) -> Bool {
        (skillRanks[catalogKey] ?? 0) > 0
    }

    public func buildCharacter() -> Character {
        var gen = GenerationProfile(
            system: generationSystem,
            priority: priority,
            buildPointBudget: budget.buildPointsTotal,
            buildPointsSpent: budget.buildPointsTotal - budget.buildPointsRemaining,
            karmaBudget: budget.karmaTotal,
            karmaSpent: 0,
            nuyenBudget: budget.nuyenTotal,
            nuyenSpent: budget.nuyenTotal - nuyen,
            attributePoints: budget.attributePointsTotal,
            specialAttributePoints: budget.specialPointsTotal,
            skillPoints: budget.skillPointsTotal,
            skillGroupPoints: budget.skillGroupPointsTotal,
            isFinished: true
        )
        _ = gen

        var character = Character(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            streetName: streetName.trimmingCharacters(in: .whitespacesAndNewlines),
            concept: concept.isEmpty ? archetype.displayName : concept,
            notes: notes,
            edition: edition,
            metatype: metatype,
            awakened: awakened,
            generation: GenerationProfile(
                system: generationSystem,
                priority: priority,
                buildPointBudget: budget.buildPointsTotal,
                buildPointsSpent: max(0, budget.buildPointsTotal - budget.buildPointsRemaining),
                karmaBudget: budget.karmaTotal,
                nuyenBudget: budget.nuyenTotal,
                nuyenSpent: max(0, budget.nuyenTotal - nuyen),
                attributePoints: budget.attributePointsTotal,
                specialAttributePoints: budget.specialPointsTotal,
                skillPoints: budget.skillPointsTotal,
                skillGroupPoints: budget.skillGroupPointsTotal,
                isFinished: true
            ),
            houseRules: houseRules,
            attributes: attributes,
            skills: skills.filter { $0.rating > 0 },
            qualities: qualities,
            karmaTotal: budget.karmaTotal,
            karmaAvailable: budget.karmaRemaining,
            nuyen: nuyen
        )
        if let avatarData {
            character.avatar.inlineData = avatarData
            character.avatar.mimeType = "image/png"
        }
        return character
    }

    // MARK: - Private

    private func recomputeAttributeRemaining() {
        let spent = attributePurchases.values.reduce(0, +)
        budget.attributePointsRemaining = max(0, budget.attributePointsTotal - spent)
        let specialSpent = specialPurchases.values.reduce(0, +)
        budget.specialPointsRemaining = max(0, budget.specialPointsTotal - specialSpent)
    }

    private func recomputeSkillRemaining() {
        let spent = skillRanks.values.reduce(0, +)
        budget.skillPointsRemaining = max(0, budget.skillPointsTotal - spent)
    }
}

/// Starter active skills offered in the wizard (edition-agnostic short list).
public enum ChargenSkillCatalog {
    public static let active: [(key: String, name: String)] = [
        ("pistols", "Pistols / Firearms"),
        ("unarmed", "Unarmed / Close Combat"),
        ("sneaking", "Sneaking / Stealth"),
        ("perception", "Perception"),
        ("athletics", "Athletics / Gymnastics"),
        ("negotiation", "Negotiation / Influence"),
        ("hacking", "Hacking / Cracking"),
        ("electronics", "Electronics / Hardware"),
        ("piloting", "Piloting"),
        ("spellcasting", "Spellcasting"),
        ("summoning", "Summoning"),
        ("first_aid", "First Aid / Biotech"),
    ]
}
