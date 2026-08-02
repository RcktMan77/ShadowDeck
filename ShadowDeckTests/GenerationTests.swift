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
    }

    func testHelpCatalogCoversCoreAttributes() {
        for id in AttributeID.standardGenerationAttributes {
            XCTAssertFalse(ChargenHelpCatalog.attributeDescription(id).isEmpty)
        }
        XCTAssertTrue(ChargenHelpCatalog.pathDescription(.mundane).lowercased().contains("no magic"))
    }
}
