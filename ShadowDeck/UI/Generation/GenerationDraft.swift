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

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .edition: "Choose Edition"
        case .concept: "Concept & Role"
        case .metatype: "Metatype"
        case .priorities: "Priorities"
        case .attributes: "Attributes"
        case .magic: "Magic / Resonance"
        case .skills: "Skills"
        case .qualities: "Qualities"
        case .resources: "Resources"
        case .finish: "Finishing Touches"
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
    public var priority = PriorityAssignment()
    public var attributes = AttributeRatings()
    public var skills: [SkillRating] = []
    public var qualities: [QualityInstance] = []
    public var nuyen: Int = 0
    public var notes: String = ""
    public var avatarData: Data?

    /// Attribute ranks purchased above metatype minimum (for point tracking).
    public var attributePurchases: [AttributeID: Int] = [:]
    public var specialPurchases: [AttributeID: Int] = [:]
    public var skillRanks: [String: Int] = [:]
    /// SR4A skill group ratings (0 = none). Chargen max 4.
    public var skillGroupRatings: [SkillGroupID: Int] = [:]
    /// Spells learned with BP during SR4 chargen.
    public var spells: [SpellInstance] = []
    /// Contacts bought with BP during SR4 chargen (Connection + Loyalty).
    public var contacts: [Contact] = []

    public var budget = GenerationBudget()

    /// Free knowledge ranks from house rules (auto or fixed).
    public private(set) var freeKnowledgePool: Int = 0
    /// Free contact-point pool total (CHA×3 + expanded extras). Used for **priority** chargen, not SR4 BP.
    public private(set) var contactPointPool: Int = 0

    /// Free contact points spent (sum of Connection + Loyalty on draft contacts). Priority chargen only.
    public var contactPointsSpent: Int {
        contacts.reduce(0) { $0 + max(0, $1.connection) + max(0, $1.loyalty) }
    }

    /// Remaining free contact points for priority chargen (not used for SR4A BP accounting).
    public var contactPointsRemaining: Int {
        contactPointPool - contactPointsSpent
    }

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
            return !isBuildPointsOverBudget
        case .priorities:
            if generationSystem == .buildPoints || generationSystem == .karmaGen || generationSystem == .pointBuy {
                return !isBuildPointsOverBudget
            }
            return priority.isComplete && priorityValid
        case .attributes:
            if generationSystem == .buildPoints {
                return !isBuildPointsOverBudget
            }
            return budget.attributePointsRemaining >= 0
        case .skills:
            if generationSystem == .buildPoints {
                return !isBuildPointsOverBudget
            }
            return budget.skillPointsRemaining >= 0
        case .finish:
            let named = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if generationSystem == .buildPoints {
                return named && !isBuildPointsOverBudget
            }
            return named
        }
    }

    /// True when SR4 BP mode has spent more than the budget.
    public var isBuildPointsOverBudget: Bool {
        generationSystem == .buildPoints && budget.buildPointsRemaining < 0
    }

    /// Live SR4A BP category breakdown (empty ledger when not in BP mode).
    public var buildPointLedger: SR4BuildPointLedger {
        guard generationSystem == .buildPoints else { return SR4BuildPointLedger() }
        return SR4BuildPointEngine.ledger(
            metatype: metatype,
            attributes: attributes,
            awakened: awakened,
            skills: skills,
            skillRanks: skillRanks,
            skillGroupRatings: skillGroupRatings,
            spells: spells,
            contacts: contacts,
            qualities: qualities,
            nuyen: nuyen,
            budget: budget.buildPointsTotal
        ).ledger
    }

    /// Max spells at SR4A chargen (2 × highest Spellcasting / Ritual Spellcasting).
    public var maxSpellsAtChargen: Int {
        SR4BuildPointEngine.maxSpellsAtChargen(skillRanks: skillRanks, skills: skills)
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
        setAwakenedPath(newArchetype.defaultAwakened)
    }

    public func selectMetatype(_ newMetatype: MetatypeID) {
        metatype = newMetatype
        resetAttributesToMinima()
        recomputeBudgetsFromPriorities()
    }

    /// Change Magic/Resonance path and recompute BP when needed.
    public func setAwakenedPath(_ path: AwakenedPath) {
        awakened = path
        if path.usesMagic && attributes.magic < 1 {
            attributes.magic = 1
        }
        if path.usesResonance && attributes.resonance < 1 {
            attributes.resonance = 1
        }
        if path == .mundane {
            attributes.magic = 0
            attributes.resonance = 0
        }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
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

    /// Call after the house-rules browser applies a selection.
    public func applyHouseRulesSelection() {
        if houseRules.isEnabled(.karmaGeneration) {
            generationSystem = .karmaGen
        } else if houseRules.isEnabled(.sumToTen) {
            generationSystem = .sumToTen
        } else if generationSystem == .sumToTen || generationSystem == .karmaGen {
            generationSystem = rules.defaultGenerationSystem
        }
        recomputeBudgetsFromPriorities()
    }

    public func recomputeBudgetsFromPriorities() {
        let r = rules
        budget.positiveQualityKarmaCap = HouseRulesEngine.positiveQualityCap(
            editionDefault: r.positiveQualityKarmaCap,
            houseRules: houseRules
        )
        budget.negativeQualityKarmaCap = r.negativeQualityKarmaCap

        if generationSystem == .buildPoints {
            // Real SR4A BP: single 400 BP pool. Attribute/skill steppers spend BP directly
            // (no separate priority-style point pools).
            budget.resetBuildPoints(total: r.standardBuildPointBudget > 0
                ? r.standardBuildPointBudget
                : SR4BuildPointEngine.defaultBudget)
            budget.resetAttributes(total: 0)
            budget.resetSpecial(total: 0)
            budget.resetSkills(points: 0, groups: 0)
            // Nuyen is bought with BP; ceiling is remaining BP × 5,000 (recomputed after spends).
            budget.karmaTotal = HouseRulesEngine.startingKarma(
                editionBaseline: r.standardPriorityKarma,
                houseRules: houseRules
            )
            budget.karmaRemaining = budget.karmaTotal
            recomputeBuildPoints()
            refreshHouseRulePools()
            return
        }

        if generationSystem == .karmaGen || houseRules.isEnabled(.karmaGeneration) {
            // Simplified karmagen: attribute/skill pools derived from budget for the wizard UI.
            generationSystem = .karmaGen
            let kBudget = houseRules.karmaGenBudget
            budget.resetAttributes(total: max(12, kBudget / 40))
            budget.resetSpecial(total: 3)
            budget.resetSkills(points: max(18, kBudget / 30), groups: 0)
            budget.resetNuyen(total: 25_000)
            self.nuyen = 25_000
            budget.karmaTotal = HouseRulesEngine.startingKarma(
                editionBaseline: kBudget,
                houseRules: houseRules
            )
            // Avoid double-counting: karmagen budget already includes power level.
            if houseRules.isEnabled(.bonusStartingKarma) || houseRules.isEnabled(.primeRunnerPackage) {
                // startingKarma already added bonus; for pure karmagen the baseline IS karmaGenBudget
                budget.karmaTotal = kBudget + (houseRules.isEnabled(.bonusStartingKarma) || houseRules.isEnabled(.primeRunnerPackage)
                    ? max(0, houseRules.bonusKarma)
                    : 0)
            } else {
                budget.karmaTotal = kBudget
            }
            budget.karmaRemaining = budget.karmaTotal
            recomputeAttributeRemaining()
            recomputeSkillRemaining()
            recomputeSkillGroupRemaining()
            refreshHouseRulePools()
            return
        }

        if let attrLetter = priority[.attributes], let pts = r.attributePoints(for: attrLetter) {
            budget.resetAttributes(total: pts)
        } else {
            budget.resetAttributes(total: 0)
        }

        if let metaLetter = priority[.metatype],
           let special = r.specialAttributePoints(for: metaLetter, metatype: metatype) {
            budget.resetSpecial(total: special)
        } else {
            budget.resetSpecial(total: 0)
        }

        if let skillLetter = priority[.skills], let sk = r.skillPoints(for: skillLetter) {
            budget.resetSkills(points: sk.skills, groups: sk.groups)
        } else {
            budget.resetSkills(points: 0, groups: 0)
        }

        if let resLetter = priority[.resources], let baseNuyen = r.resourceNuyen(for: resLetter) {
            let nuyen = HouseRulesEngine.resourceNuyen(base: baseNuyen, houseRules: houseRules)
            budget.resetNuyen(total: nuyen)
            self.nuyen = nuyen
        } else {
            budget.resetNuyen(total: 0)
            self.nuyen = 0
        }

        budget.karmaTotal = HouseRulesEngine.startingKarma(
            editionBaseline: r.standardPriorityKarma,
            houseRules: houseRules
        )
        budget.karmaRemaining = budget.karmaTotal

        // Re-apply purchase spending to remaining counters.
        recomputeAttributeRemaining()
        recomputeSkillRemaining()
        recomputeSkillGroupRemaining()
        refreshHouseRulePools()
    }

    private func refreshHouseRulePools() {
        freeKnowledgePool = HouseRulesEngine.freeKnowledgePoints(
            attributes: attributes,
            houseRules: houseRules
        )
        contactPointPool = HouseRulesEngine.contactPoints(
            charisma: attributes.charisma,
            houseRules: houseRules
        )
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
        let maxAllowed = HouseRulesEngine.naturalAttributeMaximum(
            metatypeMaximum: bounds.maximum,
            houseRules: houseRules
        )
        guard current < maxAllowed else { return false }
        if generationSystem == .buildPoints {
            // Need enough BP for one more attribute point (10 BP).
            return budget.buildPointsRemaining >= SR4BuildPointEngine.attributePointCost
        }
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
        if generationSystem == .buildPoints {
            if AttributeID.standardGenerationAttributes.contains(id) {
                attributePurchases[id, default: 0] += 1
            } else {
                specialPurchases[id, default: 0] += 1
            }
            recomputeBuildPoints()
            refreshHouseRulePools()
            return
        }
        if AttributeID.standardGenerationAttributes.contains(id) {
            attributePurchases[id, default: 0] += 1
            budget.attributePointsRemaining -= 1
        } else {
            specialPurchases[id, default: 0] += 1
            budget.specialPointsRemaining -= 1
        }
        refreshHouseRulePools()
    }

    public func decreaseAttribute(_ id: AttributeID) {
        guard canDecreaseAttribute(id) else { return }
        attributes[id] -= 1
        if generationSystem == .buildPoints {
            if AttributeID.standardGenerationAttributes.contains(id) {
                attributePurchases[id, default: 0] = max(0, (attributePurchases[id] ?? 0) - 1)
            } else {
                specialPurchases[id, default: 0] = max(0, (specialPurchases[id] ?? 0) - 1)
            }
            recomputeBuildPoints()
            refreshHouseRulePools()
            return
        }
        if AttributeID.standardGenerationAttributes.contains(id) {
            attributePurchases[id, default: 0] = max(0, (attributePurchases[id] ?? 0) - 1)
            budget.attributePointsRemaining += 1
        } else {
            specialPurchases[id, default: 0] = max(0, (specialPurchases[id] ?? 0) - 1)
            budget.specialPointsRemaining += 1
        }
        refreshHouseRulePools()
    }

    // MARK: - Recommendations (user-triggered)

    public var lastRecommendationNote: String?

    public func applyRecommendedPriorities() {
        let rec = ChargenRecommendations.priorities(archetype: archetype, metatype: metatype)
        priority = rec.assignment
        if houseRules.isEnabled(.sumToTen) {
            generationSystem = .sumToTen
        }
        recomputeBudgetsFromPriorities()
        lastRecommendationNote = rec.rationale
    }

    /// Attribute-point budget for recommendations (stable if reapplied).
    /// In BP mode, counts free BP as if physical/mental attributes were back at metatype minima
    /// so a second click does not shrink the budget by the spend of the first apply.
    /// **Pure** — must not mutate budget (called from SwiftUI view bodies for button subtitles).
    public var recommendedAttributePointBudget: Int {
        if generationSystem == .buildPoints {
            let ledger = buildPointLedger
            let total = budget.buildPointsTotal > 0
                ? budget.buildPointsTotal
                : SR4BuildPointEngine.defaultBudget
            let remaining = total - ledger.total
            let bpIfAttrsCleared = max(0, remaining) + ledger.attributes
            let freePoints = bpIfAttrsCleared / SR4BuildPointEngine.attributePointCost
            return min(20, freePoints)
        }
        return budget.attributePointsTotal
    }

    /// Active-skill rank budget for recommendations (stable if reapplied).
    /// **Pure** — must not mutate budget (called from SwiftUI view bodies).
    public var recommendedSkillPointBudget: Int {
        if generationSystem == .buildPoints {
            let ledger = buildPointLedger
            let total = budget.buildPointsTotal > 0
                ? budget.buildPointsTotal
                : SR4BuildPointEngine.defaultBudget
            let remaining = total - ledger.total
            let bpIfSkillsCleared = max(0, remaining) + ledger.skills
            let freeRanks = bpIfSkillsCleared / SR4BuildPointEngine.activeSkillRankCost
            return min(36, freeRanks)
        }
        return budget.skillPointsTotal
    }

    public func applyRecommendedAttributes() {
        // Keep ledger remaining current before applying (mutation only on user action).
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
        let pointBudget = recommendedAttributePointBudget
        let rec = ChargenRecommendations.attributes(
            archetype: archetype,
            metatype: metatype,
            edition: edition,
            pointBudget: pointBudget
        )
        resetAttributesToMinima()
        let profile = MetatypeCatalog.profile(for: metatype, edition: edition)
        for id in AttributeID.standardGenerationAttributes {
            let bounds = profile.bounds(for: id)
            let maxAllowed = HouseRulesEngine.naturalAttributeMaximum(
                metatypeMaximum: bounds.maximum,
                houseRules: houseRules
            )
            let target = rec.values[id] ?? bounds.minimum
            let clamped = Swift.min(maxAllowed, Swift.max(bounds.minimum, target))
            attributes[id] = clamped
            attributePurchases[id] = Swift.max(0, clamped - bounds.minimum)
        }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        } else {
            recomputeAttributeRemaining()
        }
        refreshHouseRulePools()
        lastRecommendationNote = rec.rationale
    }

    public func applyRecommendedSkills() {
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
        let pointBudget = recommendedSkillPointBudget
        skills.removeAll()
        skillRanks.removeAll()
        if generationSystem != .buildPoints {
            budget.skillPointsRemaining = budget.skillPointsTotal
            // Reset groups so recommend can re-spend the full group pool.
            skillGroupRatings.removeAll()
            budget.skillGroupPointsRemaining = budget.skillGroupPointsTotal
        }
        let rec = ChargenRecommendations.skills(archetype: archetype, pointBudget: pointBudget)
        let names = Dictionary(uniqueKeysWithValues: ChargenSkillCatalog.active.map { ($0.key, $0.name) })
        for (key, rank) in rec.ranks.sorted(by: { $0.key < $1.key }) {
            setSkillRank(catalogKey: key, displayName: names[key] ?? key, rank: rank)
        }
        if generationSystem != .buildPoints, budget.skillGroupPointsTotal > 0 {
            let groupRec = ChargenRecommendations.skillGroups(
                archetype: archetype,
                pointBudget: budget.skillGroupPointsTotal
            )
            for (group, rating) in groupRec.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                setSkillGroupRating(group, rating: rating)
            }
            recomputeSkillGroupRemaining()
        }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
        lastRecommendationNote = rec.rationale
    }

    /// Whether a quality can be toggled on under current caps / BP.
    public func canAddQuality(kind: QualityKind, karmaValue: Int) -> Bool {
        let cost = abs(karmaValue)
        if generationSystem == .buildPoints {
            let pos = qualities.filter { $0.kind == .positive }.reduce(0) { $0 + abs($1.karmaValue) }
            let neg = qualities.filter { $0.kind == .negative }.reduce(0) { $0 + abs($1.karmaValue) }
            let cap = 35
            switch kind {
            case .positive:
                guard pos + cost <= cap else { return false }
                return budget.buildPointsRemaining >= cost
            case .negative:
                return neg + cost <= cap
            }
        }
        switch kind {
        case .positive:
            return budget.positiveQualityKarmaUsed + cost <= budget.positiveQualityKarmaCap
        case .negative:
            return budget.negativeQualityKarmaGained + cost <= budget.negativeQualityKarmaCap
        }
    }

    public func setSkillRank(catalogKey: String, displayName: String, rank: Int, category: SkillCategory = .active) {
        let clamped = max(0, min(rank, 6))
        let previous = skillRanks[catalogKey] ?? 0
        let delta = clamped - previous
        guard delta != 0 else { return }

        if generationSystem == .buildPoints {
            let perRank = category == .active
                ? SR4BuildPointEngine.activeSkillRankCost
                : SR4BuildPointEngine.knowledgeSkillRankCost
            let bpDelta = delta * perRank
            if bpDelta > 0 {
                guard budget.buildPointsRemaining >= bpDelta else { return }
            }
            applySkillRankChange(
                catalogKey: catalogKey,
                displayName: displayName,
                clamped: clamped,
                category: category
            )
            recomputeBuildPoints()
            return
        }

        if delta > 0 {
            guard budget.skillPointsRemaining >= delta else { return }
            budget.skillPointsRemaining -= delta
        } else {
            budget.skillPointsRemaining -= delta // delta negative → add back
        }
        applySkillRankChange(
            catalogKey: catalogKey,
            displayName: displayName,
            clamped: clamped,
            category: category
        )
    }

    public func canIncreaseSkill(catalogKey: String) -> Bool {
        let current = skillRanks[catalogKey] ?? 0
        guard current < 6 else { return false }
        if generationSystem == .buildPoints {
            return budget.buildPointsRemaining >= SR4BuildPointEngine.activeSkillRankCost
        }
        return budget.skillPointsRemaining > 0
    }

    public func canDecreaseSkill(catalogKey: String) -> Bool {
        (skillRanks[catalogKey] ?? 0) > 0
    }

    // MARK: - Skill groups / spells / contacts

    /// Max skill group rating at chargen (SR4A BP: 4; priority SR5-style: 6).
    public var skillGroupMaxAtChargen: Int {
        generationSystem == .buildPoints ? SR4BuildPointEngine.skillGroupMaxAtChargen : 6
    }

    public func skillGroupRating(_ group: SkillGroupID) -> Int {
        skillGroupRatings[group] ?? 0
    }

    public func canIncreaseSkillGroup(_ group: SkillGroupID) -> Bool {
        let current = skillGroupRating(group)
        guard current < skillGroupMaxAtChargen else { return false }
        if generationSystem == .buildPoints {
            return budget.buildPointsRemaining >= SR4BuildPointEngine.skillGroupRankCost
        }
        // Priority (SR5): one skill-group point per rating rank.
        return budget.skillGroupPointsRemaining > 0
    }

    public func canDecreaseSkillGroup(_ group: SkillGroupID) -> Bool {
        skillGroupRating(group) > 0
    }

    public func setSkillGroupRating(_ group: SkillGroupID, rating: Int) {
        let clamped = max(0, min(rating, skillGroupMaxAtChargen))
        let previous = skillGroupRating(group)
        let delta = clamped - previous
        guard delta != 0 else { return }
        if generationSystem == .buildPoints {
            if delta > 0 {
                let need = delta * SR4BuildPointEngine.skillGroupRankCost
                guard budget.buildPointsRemaining >= need else { return }
            }
        } else {
            // Priority: spend/refund skill-group points 1:1 with rating.
            if delta > 0 {
                guard budget.skillGroupPointsRemaining >= delta else { return }
            }
        }
        if clamped == 0 {
            skillGroupRatings.removeValue(forKey: group)
        } else {
            skillGroupRatings[group] = clamped
        }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        } else {
            recomputeSkillGroupRemaining()
        }
    }

    public func canAddSpell() -> Bool {
        guard generationSystem == .buildPoints else { return true }
        guard awakened.usesMagic else { return false }
        guard spells.count < maxSpellsAtChargen else { return false }
        return budget.buildPointsRemaining >= SR4BuildPointEngine.spellCost
    }

    public func addSpell(_ spell: SpellInstance) {
        if generationSystem == .buildPoints {
            guard canAddSpell() else { return }
            guard !spells.contains(where: { $0.catalogKey == spell.catalogKey || $0.name == spell.name }) else {
                return
            }
        }
        spells.append(spell)
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func removeSpell(id: UUID) {
        spells.removeAll { $0.id == id }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func contactBPCost(_ contact: Contact) -> Int {
        SR4BuildPointEngine.contactCost(connection: contact.connection, loyalty: contact.loyalty)
    }

    public func canAddContact(connection: Int, loyalty: Int) -> Bool {
        guard generationSystem == .buildPoints else { return true }
        let cost = SR4BuildPointEngine.contactCost(connection: connection, loyalty: loyalty)
        return budget.buildPointsRemaining >= cost
    }

    public func addContact(_ contact: Contact) {
        if generationSystem == .buildPoints {
            guard canAddContact(connection: contact.connection, loyalty: contact.loyalty) else { return }
        }
        contacts.append(contact)
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func updateContact(_ contact: Contact) {
        guard let idx = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let previous = contacts[idx]
        if generationSystem == .buildPoints {
            let oldCost = contactBPCost(previous)
            let newCost = contactBPCost(contact)
            let free = budget.buildPointsRemaining + oldCost
            guard free >= newCost else { return }
        }
        contacts[idx] = contact
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func removeContact(id: UUID) {
        contacts.removeAll { $0.id == id }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func buildCharacter() -> Character {
        let groupInstances = skillGroupRatings
            .filter { $0.value > 0 }
            .map { SkillGroupRating(group: $0.key, rating: $0.value) }
            .sorted { $0.group.rawValue < $1.group.rawValue }

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
                buildPointsSpent: generationSystem == .buildPoints
                    ? buildPointLedger.total
                    : max(0, budget.buildPointsTotal - budget.buildPointsRemaining),
                karmaBudget: budget.karmaTotal,
                nuyenBudget: generationSystem == .buildPoints ? nuyen : budget.nuyenTotal,
                nuyenSpent: generationSystem == .buildPoints
                    ? nuyen
                    : max(0, budget.nuyenTotal - nuyen),
                attributePoints: budget.attributePointsTotal,
                specialAttributePoints: budget.specialPointsTotal,
                skillPoints: budget.skillPointsTotal,
                skillGroupPoints: generationSystem == .buildPoints
                    ? groupInstances.reduce(0) { $0 + $1.rating }
                    : budget.skillGroupPointsTotal,
                isFinished: true
            ),
            houseRules: houseRules,
            attributes: attributes,
            skills: skills.filter { $0.rating > 0 },
            skillGroups: groupInstances,
            qualities: qualities,
            spells: spells,
            contacts: contacts,
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

    private func applySkillRankChange(
        catalogKey: String,
        displayName: String,
        clamped: Int,
        category: SkillCategory
    ) {
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

    /// Recompute SR4 BP remaining from live draft state (single source of truth).
    public func recomputeBuildPoints() {
        guard generationSystem == .buildPoints else { return }
        let budgetTotal = budget.buildPointsTotal > 0
            ? budget.buildPointsTotal
            : SR4BuildPointEngine.defaultBudget
        budget.buildPointsTotal = budgetTotal
        let result = SR4BuildPointEngine.ledger(
            metatype: metatype,
            attributes: attributes,
            awakened: awakened,
            skills: skills,
            skillRanks: skillRanks,
            skillGroupRatings: skillGroupRatings,
            spells: spells,
            contacts: contacts,
            qualities: qualities,
            nuyen: nuyen,
            budget: budgetTotal
        )
        budget.buildPointsRemaining = result.remaining
        // Reflect resource ceiling for UI (¥ that would cost all remaining + already spent resource BP).
        let resourceBP = result.ledger.resources
        let maxNuyen = SR4BuildPointEngine.nuyenForBuildPoints(
            max(0, resourceBP + max(0, result.remaining))
        )
        budget.nuyenTotal = max(nuyen, maxNuyen)
        budget.nuyenRemaining = max(0, budget.nuyenTotal - nuyen)
    }

    /// Adjust nuyen under BP mode (spends/refunds resource BP).
    public func setNuyenForBuildPoints(_ amount: Int) {
        let clamped = max(0, amount)
        if generationSystem == .buildPoints {
            let cost = SR4BuildPointEngine.resourceCost(nuyen: clamped)
            let currentResource = SR4BuildPointEngine.resourceCost(nuyen: nuyen)
            let delta = cost - currentResource
            if delta > 0 {
                // Temporarily ignore current resources when checking free BP.
                let withoutResources = budget.buildPointsRemaining + currentResource
                guard withoutResources >= cost else { return }
            }
            nuyen = clamped
            recomputeBuildPoints()
            return
        }
        nuyen = clamped
    }

    public func setQualitiesForBuildPoints(_ newQualities: [QualityInstance]) {
        qualities = newQualities
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

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

    /// Priority skill-group points: 1 point per rating rank across all groups.
    private func recomputeSkillGroupRemaining() {
        let spent = skillGroupRatings.values.reduce(0, +)
        budget.skillGroupPointsRemaining = max(0, budget.skillGroupPointsTotal - spent)
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
        ("first_aid", "First Aid / Biotech")
    ]
}
