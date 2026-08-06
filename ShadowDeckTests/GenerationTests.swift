//
//  GenerationTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

@MainActor
final class GenerationTests: XCTestCase {
    func testDraftDefaultsPerEdition() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        XCTAssertEqual(draft.generationSystem, .buildPoints)
        draft.selectEdition(.sr5)
        XCTAssertEqual(draft.generationSystem, .priority)
        draft.selectEdition(.sr6)
        XCTAssertEqual(draft.generationSystem, .priority)
    }

    func testPriorityAssignmentUniqueAndBudget() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr5)
        draft.selectMetatype(.human)
        draft.assignPriority(.a, to: .attributes)
        draft.assignPriority(.b, to: .skills)
        draft.assignPriority(.c, to: .resources)
        draft.assignPriority(.d, to: .magicOrResonance)
        draft.assignPriority(.e, to: .metatype)

        XCTAssertTrue(draft.priority.usesUniqueLetters)
        XCTAssertTrue(draft.priorityValid)
        XCTAssertEqual(draft.budget.attributePointsTotal, 24) // SR5 A
        XCTAssertEqual(draft.budget.attributePointsRemaining, 24)
        XCTAssertGreaterThan(draft.budget.nuyenTotal, 0)
    }

    func testAttributeStepperRespectsPoolAndMax() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr5)
        draft.selectMetatype(.human)
        draft.assignPriority(.e, to: .attributes) // 12 points
        draft.assignPriority(.a, to: .metatype)
        draft.assignPriority(.b, to: .skills)
        draft.assignPriority(.c, to: .resources)
        draft.assignPriority(.d, to: .magicOrResonance)
        draft.recomputeBudgetsFromPriorities()
        draft.resetAttributesToMinima()

        let start = draft.budget.attributePointsRemaining
        XCTAssertGreaterThan(start, 0)

        while draft.canIncreaseAttribute(.body) {
            draft.increaseAttribute(.body)
        }
        XCTAssertFalse(draft.canIncreaseAttribute(.body))
        // Either pool empty or at max 6 for human
        XCTAssertTrue(
            draft.budget.attributePointsRemaining == 0
                || draft.attributes.body == 6
        )
        XCTAssertTrue(draft.canDecreaseAttribute(.body) || draft.attributes.body == 1)
    }

    func testSkillStepperConsumesPoints() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr5)
        draft.assignPriority(.a, to: .skills)
        draft.assignPriority(.b, to: .attributes)
        draft.assignPriority(.c, to: .metatype)
        draft.assignPriority(.d, to: .resources)
        draft.assignPriority(.e, to: .magicOrResonance)
        draft.recomputeBudgetsFromPriorities()

        let before = draft.budget.skillPointsRemaining
        XCTAssertGreaterThanOrEqual(before, 3)
        draft.setSkillRank(catalogKey: "pistols", displayName: "Pistols", rank: 3)
        XCTAssertEqual(draft.budget.skillPointsRemaining, before - 3)
        XCTAssertEqual(draft.skillRanks["pistols"], 3)
        XCTAssertTrue(draft.canIncreaseSkill(catalogKey: "pistols"))
        draft.setSkillRank(catalogKey: "pistols", displayName: "Pistols", rank: 6)
        XCTAssertEqual(draft.skillRanks["pistols"], 6)
        XCTAssertFalse(draft.canIncreaseSkill(catalogKey: "pistols"))
    }

    func testBuildCharacterRequiresNameAndProducesValidCore() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr5)
        draft.selectArchetype(.decker)
        draft.selectMetatype(.elf)
        draft.assignPriority(.a, to: .skills)
        draft.assignPriority(.b, to: .attributes)
        draft.assignPriority(.c, to: .resources)
        draft.assignPriority(.d, to: .metatype)
        draft.assignPriority(.e, to: .magicOrResonance)
        draft.recomputeBudgetsFromPriorities()
        draft.resetAttributesToMinima()
        draft.name = "Nova"
        draft.streetName = "Packet"
        draft.setSkillRank(catalogKey: "hacking", displayName: "Hacking", rank: 4)

        XCTAssertTrue(draft.canGoNext || draft.step != .finish)
        let character = draft.buildCharacter()
        XCTAssertEqual(character.name, "Nova")
        XCTAssertEqual(character.streetName, "Packet")
        XCTAssertEqual(character.edition, .sr5)
        XCTAssertEqual(character.metatype, .elf)
        XCTAssertEqual(character.concept, RunnerArchetype.decker.displayName)
        XCTAssertTrue(character.skills.contains { $0.catalogKey == "hacking" && $0.rating == 4 })

        let validation = RulesRegistry.rules(for: .sr5).validate(character)
        // Chargen mid-spend may warn; should not hard-error on identity/edition.
        XCTAssertFalse(validation.errors.contains { $0.code == "identity.name" })
        XCTAssertFalse(validation.errors.contains { $0.code == "edition.mismatch" })
    }

    func testSumToTenMode() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr5)
        draft.houseRules = .popularTable
        draft.generationSystem = .sumToTen
        // A+A+B+C+E = 4+4+3+2+0 = 13 — invalid
        draft.priority = PriorityAssignment(values: [
            .metatype: .a,
            .attributes: .a,
            .magicOrResonance: .b,
            .skills: .c,
            .resources: .e
        ])
        XCTAssertFalse(draft.priorityValid)

        draft.priority = PriorityAssignment(values: [
            .metatype: .c,
            .attributes: .b,
            .magicOrResonance: .e,
            .skills: .a,
            .resources: .d
        ])
        // 2+3+0+4+1 = 10
        XCTAssertEqual(draft.priority.sumToTenTotal, 10)
        XCTAssertTrue(draft.priorityValid)
    }

    func testPrioritySummariesExistForAllCells() {
        let rules = SR5Rules()
        let summaries = PrioritySummaryBuilder.summaries(for: .sr5, metatype: .ork, rules: rules)
        XCTAssertEqual(summaries.count, PriorityColumn.allCases.count * PriorityLetter.allCases.count)
        XCTAssertTrue(summaries.contains { !$0.detailLines.isEmpty })
    }

    func testArchetypeDefaults() {
        XCTAssertEqual(RunnerArchetype.combatMage.defaultAwakened, .fullMagician)
        XCTAssertEqual(RunnerArchetype.technomancer.defaultAwakened, .technomancer)
        XCTAssertEqual(RunnerArchetype.streetSamurai.defaultAwakened, .mundane)
        XCTAssertEqual(RunnerArchetype.allCases.count, 8)
        XCTAssertTrue(RunnerArchetype.streetSamurai.summaryMarkdown.contains("wares"))
        XCTAssertTrue(RunnerArchetype.streetSamurai.defaultPathLabel.lowercased().contains("mundane"))
    }

    func testApplyRecommendations() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr5)
        draft.selectArchetype(.decker)
        draft.selectMetatype(.human)
        draft.applyRecommendedPriorities()
        XCTAssertTrue(draft.priority.isComplete)
        XCTAssertTrue(draft.priorityValid)
        draft.applyRecommendedAttributes()
        XCTAssertGreaterThan(draft.budget.attributePointsSpent, 0)
        draft.applyRecommendedSkills()
        XCTAssertFalse(draft.skills.isEmpty)
        XCTAssertNotNil(draft.skillRanks["hacking"] ?? draft.skillRanks["electronics"])
        // Skill recommend must exhaust the active skill pool when the catalog can absorb it.
        XCTAssertEqual(
            draft.budget.skillPointsRemaining,
            0,
            "Recommended skills should spend the full priority skill pool (had \(draft.budget.skillPointsTotal))"
        )
    }

    func testSR6RecommendedSkillsExhaustPool() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr6)
        draft.selectArchetype(.streetSamurai)
        draft.selectMetatype(.human)
        draft.applyRecommendedPriorities()
        draft.applyRecommendedSkills()
        XCTAssertEqual(draft.budget.skillPointsTotal, draft.budget.skillPointsSpent)
        XCTAssertEqual(draft.budget.skillPointsRemaining, 0)
        // Package + fill still prefers combat skills.
        XCTAssertGreaterThan(draft.skillRanks["pistols"] ?? 0, 0)
    }

    func testSR5SkillGroupPointsSpendAndChip() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr5)
        draft.selectArchetype(.decker)
        draft.selectMetatype(.human)
        draft.applyRecommendedPriorities()
        // Skills A/B/C grant group points; ensure we have some.
        XCTAssertGreaterThan(draft.budget.skillGroupPointsTotal, 0)
        XCTAssertEqual(draft.budget.skillGroupPointsRemaining, draft.budget.skillGroupPointsTotal)
        XCTAssertTrue(draft.canIncreaseSkillGroup(.electronics))
        draft.setSkillGroupRating(.electronics, rating: 3)
        XCTAssertEqual(draft.skillGroupRating(.electronics), 3)
        XCTAssertEqual(draft.budget.skillGroupPointsRemaining, draft.budget.skillGroupPointsTotal - 3)
        draft.setSkillGroupRating(.electronics, rating: 0)
        XCTAssertEqual(draft.budget.skillGroupPointsRemaining, draft.budget.skillGroupPointsTotal)

        draft.applyRecommendedSkills()
        XCTAssertEqual(draft.budget.skillGroupPointsRemaining, 0, "Recommend should spend all group points")
        let groupSpent = draft.skillGroupRatings.values.reduce(0, +)
        XCTAssertEqual(groupSpent, draft.budget.skillGroupPointsTotal)
    }

    func testSkillRecommendationUsesFullBudget() {
        let budget = 32
        let rec = ChargenRecommendations.skills(archetype: .technomancer, pointBudget: budget)
        let spent = rec.ranks.values.reduce(0, +)
        XCTAssertEqual(spent, budget)
        XCTAssertLessThanOrEqual(rec.ranks.values.max() ?? 0, 6)
    }

    /// BP recommend budgets must ignore current attribute/skill spends so re-apply is stable.
    func testSR4RecommendedAttributesAndSkillsAreIdempotent() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        draft.selectArchetype(.technomancer)
        draft.selectMetatype(.ork)
        draft.setAwakenedPath(.technomancer)
        draft.recomputeBuildPoints()

        draft.applyRecommendedAttributes()
        let attrsOnce = draft.attributes
        let attrBudgetOnce = draft.recommendedAttributePointBudget
        draft.applyRecommendedAttributes()
        XCTAssertEqual(draft.attributes, attrsOnce, "Second Apply Recommended Attributes must not change values")
        XCTAssertEqual(draft.recommendedAttributePointBudget, attrBudgetOnce)

        draft.applyRecommendedSkills()
        let skillsOnce = draft.skillRanks
        let skillBudgetOnce = draft.recommendedSkillPointBudget
        draft.applyRecommendedSkills()
        XCTAssertEqual(draft.skillRanks, skillsOnce, "Second Apply Recommended Skills must not change ranks")
        XCTAssertEqual(draft.recommendedSkillPointBudget, skillBudgetOnce)
    }

    func testHelpCatalogCoversCoreAttributes() {
        for id in AttributeID.standardGenerationAttributes {
            XCTAssertFalse(ChargenHelpCatalog.attributeDescription(id).isEmpty)
        }
        XCTAssertTrue(ChargenHelpCatalog.pathDescription(.mundane).lowercased().contains("no magic"))
    }

    // MARK: - SR4 Build Points (real accounting)

    func testSR4BuildPointEngineMetatypeAndResources() {
        XCTAssertEqual(SR4BuildPointEngine.metatypeCost(.human), 0)
        XCTAssertEqual(SR4BuildPointEngine.metatypeCost(.troll), 40)
        XCTAssertEqual(SR4BuildPointEngine.resourceCost(nuyen: 0), 0)
        XCTAssertEqual(SR4BuildPointEngine.resourceCost(nuyen: 5_000), 1)
        XCTAssertEqual(SR4BuildPointEngine.resourceCost(nuyen: 5_001), 2)
        XCTAssertEqual(SR4BuildPointEngine.nuyenForBuildPoints(3), 15_000)
    }

    func testSR4DraftBudgetIs400AndMetatypeSpendsBP() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        XCTAssertEqual(draft.generationSystem, .buildPoints)
        XCTAssertEqual(draft.budget.buildPointsTotal, 400)
        draft.selectMetatype(.human)
        XCTAssertEqual(draft.budget.buildPointsRemaining, 400)
        draft.selectMetatype(.elf)
        // Elf 30 BP; attributes at minima should add 0 beyond metatype.
        XCTAssertEqual(draft.buildPointLedger.metatype, 30)
        XCTAssertEqual(draft.budget.buildPointsRemaining, 370)
    }

    func testSR4AttributeSpends10BPAndBlocksOverspend() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        draft.selectMetatype(.human)
        draft.resetAttributesToMinima()
        draft.recomputeBuildPoints()
        let before = draft.budget.buildPointsRemaining
        XCTAssertTrue(draft.canIncreaseAttribute(.body))
        draft.increaseAttribute(.body)
        XCTAssertEqual(draft.budget.buildPointsRemaining, before - 10)
        XCTAssertEqual(draft.buildPointLedger.attributes, 10)

        // Exhaust BP by purchasing attributes until cannot increase.
        while draft.canIncreaseAttribute(.agility) {
            draft.increaseAttribute(.agility)
        }
        // Either at metatype max or insufficient BP for another 10.
        XCTAssertFalse(draft.canIncreaseAttribute(.agility))
        XCTAssertGreaterThanOrEqual(draft.budget.buildPointsRemaining, 0)
    }

    func testSR4SkillSpends4BPPerRank() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        draft.selectMetatype(.human)
        draft.recomputeBuildPoints()
        let before = draft.budget.buildPointsRemaining
        draft.setSkillRank(catalogKey: "pistols", displayName: "Pistols", rank: 3)
        XCTAssertEqual(draft.budget.buildPointsRemaining, before - 12)
        XCTAssertEqual(draft.buildPointLedger.skills, 12)
        draft.setSkillRank(catalogKey: "pistols", displayName: "Pistols", rank: 0)
        XCTAssertEqual(draft.budget.buildPointsRemaining, before)
    }

    func testSR4ResourcesAndQualitiesAffectBP() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        draft.selectMetatype(.human)
        draft.recomputeBuildPoints()
        draft.setNuyenForBuildPoints(50_000)
        XCTAssertEqual(draft.nuyen, 50_000)
        XCTAssertEqual(draft.buildPointLedger.resources, 10)
        XCTAssertEqual(draft.budget.buildPointsRemaining, 390)

        XCTAssertTrue(draft.canAddQuality(kind: .positive, karmaValue: 10))
        draft.qualities.append(
            QualityInstance(catalogKey: "toughness", name: "Toughness", kind: .positive, karmaValue: 10)
        )
        draft.recomputeBuildPoints()
        XCTAssertEqual(draft.buildPointLedger.qualities, 10)
        XCTAssertEqual(draft.budget.buildPointsRemaining, 380)

        draft.qualities.append(
            QualityInstance(catalogKey: "sinner", name: "SINner", kind: .negative, karmaValue: 5)
        )
        draft.recomputeBuildPoints()
        XCTAssertEqual(draft.buildPointLedger.qualities, 5) // 10 - 5
        XCTAssertEqual(draft.budget.buildPointsRemaining, 385)
    }

    func testSR4OverspendBlocksFinishAndBuildRecordsSpent() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        draft.selectMetatype(.troll) // 40 BP
        draft.selectArchetype(.streetSamurai)
        draft.name = "Brick"
        // Force overspend: more nuyen than remaining BP can buy after heavy attrs/skills.
        draft.resetAttributesToMinima()
        for _ in 0..<30 {
            if draft.canIncreaseAttribute(.body) { draft.increaseAttribute(.body) }
            if draft.canIncreaseAttribute(.strength) { draft.increaseAttribute(.strength) }
            if draft.canIncreaseAttribute(.agility) { draft.increaseAttribute(.agility) }
        }
        draft.setSkillRank(catalogKey: "unarmed", displayName: "Unarmed", rank: 6)
        draft.setSkillRank(catalogKey: "pistols", displayName: "Pistols", rank: 6)
        draft.setSkillRank(catalogKey: "athletics", displayName: "Athletics", rank: 6)
        draft.setSkillRank(catalogKey: "perception", displayName: "Perception", rank: 6)
        draft.setSkillRank(catalogKey: "sneaking", displayName: "Sneaking", rank: 6)
        // Spend remaining on nuyen.
        draft.setNuyenForBuildPoints(
            SR4BuildPointEngine.nuyenForBuildPoints(max(0, draft.budget.buildPointsRemaining))
        )
        XCTAssertGreaterThanOrEqual(draft.budget.buildPointsRemaining, 0)
        XCTAssertFalse(draft.isBuildPointsOverBudget)

        // Manually force ledger overspend path: set nuyen without guard by raw assignment then recompute.
        draft.nuyen = 5_000_000
        draft.recomputeBuildPoints()
        XCTAssertTrue(draft.isBuildPointsOverBudget)
        draft.step = .finish
        XCTAssertFalse(draft.canGoNext)

        // Fix overspend and save path.
        draft.setNuyenForBuildPoints(0)
        // setNuyen only applies if BP mode guard allows; force clear:
        draft.nuyen = 0
        draft.recomputeBuildPoints()
        XCTAssertFalse(draft.isBuildPointsOverBudget)
        XCTAssertTrue(draft.canGoNext)

        let character = draft.buildCharacter()
        XCTAssertEqual(character.generation.system, .buildPoints)
        XCTAssertEqual(character.generation.buildPointBudget, 400)
        XCTAssertEqual(character.generation.buildPointsSpent, draft.buildPointLedger.total)
        XCTAssertLessThanOrEqual(character.generation.buildPointsSpent, 400)
    }

    func testSR4FullDraftToCharacterHappyPath() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        draft.selectArchetype(.face)
        draft.selectMetatype(.elf)
        draft.setAwakenedPath(.mundane)
        draft.applyRecommendedAttributes()
        draft.applyRecommendedSkills()
        draft.setNuyenForBuildPoints(25_000)
        draft.name = "Glitter"
        draft.streetName = "Chrome Smile"
        XCTAssertFalse(draft.isBuildPointsOverBudget)
        XCTAssertGreaterThanOrEqual(draft.budget.buildPointsRemaining, 0)
        let character = draft.buildCharacter()
        XCTAssertEqual(character.edition, .sr4)
        XCTAssertEqual(character.metatype, .elf)
        XCTAssertEqual(character.generation.buildPointBudget, 400)
        XCTAssertEqual(character.generation.buildPointsSpent, draft.buildPointLedger.total)
        XCTAssertEqual(character.nuyen, 25_000)
        XCTAssertFalse(character.skills.isEmpty)
    }

    func testSR4SkillGroupSpellAndContactBP() {
        let draft = GenerationDraft()
        draft.selectEdition(.sr4)
        draft.selectMetatype(.human)
        draft.recomputeBuildPoints()
        let start = draft.budget.buildPointsRemaining

        draft.setSkillGroupRating(.fireArarms, rating: 3)
        XCTAssertEqual(draft.buildPointLedger.skillGroups, 30)
        XCTAssertEqual(draft.budget.buildPointsRemaining, start - 30)

        draft.setSkillRank(catalogKey: "spellcasting", displayName: "Spellcasting", rank: 4)
        draft.setAwakenedPath(.fullMagician)
        // Magician quality not auto-added; still can buy spells if usesMagic
        XCTAssertEqual(draft.maxSpellsAtChargen, 8)
        let beforeSpell = draft.budget.buildPointsRemaining
        draft.addSpell(SpellInstance(catalogKey: "manabolt", name: "Manabolt", category: "Combat Spell"))
        XCTAssertEqual(draft.spells.count, 1)
        XCTAssertEqual(draft.buildPointLedger.spells, 3)
        XCTAssertEqual(draft.budget.buildPointsRemaining, beforeSpell - 3)

        let beforeContact = draft.budget.buildPointsRemaining
        draft.addContact(Contact(name: "Fixer Jax", role: "Fixer", loyalty: 2, connection: 4))
        XCTAssertEqual(draft.buildPointLedger.contacts, 6)
        XCTAssertEqual(draft.budget.buildPointsRemaining, beforeContact - 6)

        let character = draft.buildCharacter()
        XCTAssertEqual(character.skillGroups.first?.group, .fireArarms)
        XCTAssertEqual(character.skillGroups.first?.rating, 3)
        XCTAssertEqual(character.spells.count, 1)
        XCTAssertEqual(character.contacts.count, 1)
        XCTAssertEqual(character.contacts.first?.connection, 4)
    }

    func testSR4ContactCostFormula() {
        XCTAssertEqual(SR4BuildPointEngine.contactCost(connection: 3, loyalty: 5), 8)
        XCTAssertEqual(SR4BuildPointEngine.spellCost(count: 6), 18)
        XCTAssertEqual(SR4BuildPointEngine.skillGroupCost(ratings: [.sorcery: 3]), 30)
    }
}
