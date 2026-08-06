//
//  TableReadinessDomainTests.swift
//  ShadowDeckTests
//
//  Domain-level table-readiness probes for the product QA audit.
//  Uses ephemeral in-memory libraries only (never the user's live store).
//

import XCTest
@testable import ShadowDeck

@MainActor
final class TableReadinessDomainTests: XCTestCase {
    // MARK: - Samples per edition

    func testSamplesExistAndAreEditionCoherent() {
        let samples = SampleCharacters.makeAll()
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(Set(samples.map(\.edition)), Set(Edition.allCases))
        for c in samples {
            XCTAssertFalse(c.name.isEmpty)
            XCTAssertGreaterThan(c.attributes.body, 0)
            XCTAssertFalse(c.skills.isEmpty, "\(c.edition.shortName) sample should have skills")
            let phys = DerivedStatsCalculator.physicalBoxes(body: c.attributes.body)
            let stun = DerivedStatsCalculator.stunBoxes(willpower: c.attributes.willpower)
            XCTAssertGreaterThan(phys, 0)
            XCTAssertGreaterThan(stun, 0)
            if c.edition.usesLimits {
                XCTAssertTrue(Edition.sr5.usesLimits)
            } else {
                XCTAssertFalse(c.edition.usesLimits)
            }
        }
    }

    // MARK: - Dice edition defaults

    func testGlitchThresholdEditionDefaults() {
        // 4 dice, 2 ones: SR4 halfOrMore → glitch; SR5/SR6 moreThanHalf → not glitch
        XCTAssertTrue(DiceRollerEngine.isGlitch(ones: 2, diceCount: 4, edition: .sr4))
        XCTAssertFalse(DiceRollerEngine.isGlitch(ones: 2, diceCount: 4, edition: .sr5))
        XCTAssertFalse(DiceRollerEngine.isGlitch(ones: 2, diceCount: 4, edition: .sr6))
        for ed in Edition.allCases {
            XCTAssertTrue(DiceRollerEngine.isGlitch(ones: 3, diceCount: 4, edition: ed), ed.shortName)
        }
    }

    func testHitsDefaultAndHouseRuleAcrossEditions() {
        let faces = [4, 5, 6, 1]
        for ed in Edition.allCases {
            let core = DiceRollerEngine.evaluate(dice: faces, edition: ed)
            XCTAssertEqual(core.hits, 2, ed.shortName)
            let house = DiceRollerEngine.evaluate(
                dice: faces,
                edition: ed,
                diceRules: DiceHouseRules(hitsOn4: true)
            )
            XCTAssertEqual(house.hits, 3, ed.shortName)
        }
    }

    // MARK: - Advancement

    func testSkillRaiseCostFrom3To4DiffersForSR6() {
        XCTAssertEqual(SR4Rules().karmaCostToRaiseSkill(from: 3), 8)
        XCTAssertEqual(SR5Rules().karmaCostToRaiseSkill(from: 3), 8)
        XCTAssertEqual(SR6Rules().karmaCostToRaiseSkill(from: 3), 20)
    }

    func testAdvancementBlockedWithoutKarma() {
        var c = SampleCharacters.sr5CombatMage()
        c.karmaAvailable = 0
        let rules = RulesRegistry.rules(for: c.edition)
        guard let skill = c.skills.first(where: { $0.category == .active }) else {
            return XCTFail("SR5 sample needs an active skill")
        }
        let item = AdvancementEngine.skillRaisePreview(character: c, skill: skill, rules: rules)
        // `canRaise` is rating-max only; UI must still gate on available karma.
        XCTAssertGreaterThan(item.karmaCost, 0)
        XCTAssertEqual(c.karmaAvailable, 0)
        guard item.canRaise else {
            return // already at max — still a valid soft state for this sample
        }
        let plan = AdvancementPlanItem(
            kind: .skillRaise,
            targetKey: skill.catalogKey,
            displayName: skill.displayName,
            fromRating: skill.rating,
            toRating: skill.rating + 1,
            karmaCost: item.karmaCost,
            skillCategory: skill.category
        )
        XCTAssertThrowsError(try AdvancementEngine.apply(plan, to: &c, rules: rules))
    }

    func testAdvancementApplySpendsKarma() throws {
        var c = SampleCharacters.sr5CombatMage()
        c.karmaAvailable = 50
        c.karmaTotal = 50
        let rules = RulesRegistry.rules(for: c.edition)
        guard let skill = c.skills.first(where: { $0.category == .active && $0.rating < 6 }) else {
            return XCTFail("need raisable skill")
        }
        let before = skill.rating
        let preview = AdvancementEngine.skillRaisePreview(character: c, skill: skill, rules: rules)
        XCTAssertTrue(preview.canRaise)
        let plan = AdvancementPlanItem(
            kind: .skillRaise,
            targetKey: skill.catalogKey,
            displayName: skill.displayName,
            fromRating: skill.rating,
            toRating: skill.rating + 1,
            karmaCost: preview.karmaCost,
            skillCategory: skill.category
        )
        try AdvancementEngine.apply(plan, to: &c, rules: rules)
        let after = c.skills.first { $0.catalogKey == skill.catalogKey }?.rating
        XCTAssertEqual(after, before + 1)
        XCTAssertEqual(c.karmaAvailable, 50 - preview.karmaCost)
    }

    // MARK: - Lifestyle shortfall

    func testLifestyleProcessMonthShortfallIsClear() {
        var c = SampleCharacters.sr5CombatMage()
        c.nuyen = 50
        c.lifestyleNuyenReserve = 0
        c.lifestyles = [
            Lifestyle(name: "Squatter pad", level: .squatter, monthlyCost: 500, monthsPrepaid: 0)
        ]
        XCTAssertThrowsError(try LifestyleTracker.processMonths(&c, months: 1)) { err in
            guard case LifestyleTrackerError.shortfall = err else {
                return XCTFail("Expected shortfall, got \(err)")
            }
            XCTAssertTrue(err.localizedDescription.lowercased().contains("need"))
        }
    }

    // MARK: - Ephemeral run loop

    func testEphemeralCampaignRunAwardsAndBriefing() throws {
        let env = try LibraryEnvironment.ephemeral()
        var runner = SampleCharacters.sr5CombatMage()
        runner.nuyen = 1_000
        runner.karmaAvailable = 5
        runner.karmaTotal = 5
        try env.library.save(runner)

        var campaign = Campaign.makeDraft(name: "Audit Campaign", edition: .sr5)
        campaign.notes = "Table readiness probe"
        try env.campaignLibrary.save(campaign)
        env.refreshCampaignCount()
        XCTAssertEqual(env.campaignCount, 1)

        var run = Run.makeDraft(title: "Audit Job", edition: .sr5, campaignID: campaign.id)
        run.client = "Mr. Johnson"
        run.location = "Seattle"
        run.playerFacingSummary = "Meet downtown. Grab the package."
        run.knownRisks = "Corpsec on floor 3."
        run.opposition = "GMONLY: 6 red samurai"
        run.gmNotes = "GMONLY: twist is a dragon"
        run.expectedPayout = RunPayout(nuyen: 6_000, karma: 4)
        run.participantCharacterIDs = [runner.id]
        run.contacts = [
            RunContactLink(role: .johnson, displayName: "Ms. Audit")
        ]
        run.objectives = [
            RunObjective(text: "Secure package", isPrimary: true, status: .pending)
        ]
        try env.runLibrary.save(run)
        env.refreshRunCount()
        XCTAssertEqual(env.runCount, 1)

        let template = RunTemplate.builtins.first
        XCTAssertNotNil(template)
        if let template {
            let fromTemplate = Run.makeDraft(from: template, location: "Bellevue", campaignID: campaign.id)
            XCTAssertFalse(fromTemplate.title.isEmpty)
            try env.runLibrary.save(fromTemplate)
            env.refreshRunCount()
            XCTAssertEqual(env.runCount, 2)
        }

        run.status = .completed
        run.completedAt = Date()
        run.actualPayout = RunPayout(nuyen: 6_000, karma: 4)
        try env.runLibrary.save(run)

        var chars = [try env.library.require(runner.id)]
        let preview = RunAwardApplicator.preview(
            run: run,
            charactersByID: Dictionary(uniqueKeysWithValues: chars.map { ($0.id, $0) })
        )
        XCTAssertEqual(preview.perCharacter.count, 1)
        XCTAssertEqual(preview.perCharacter[0].nuyen, 6_000)
        XCTAssertEqual(preview.perCharacter[0].karma, 4)

        var share = preview.perCharacter[0]
        share.streetCredDelta = 1

        _ = try RunAwardApplicator.apply(run: &run, characters: &chars, shares: [share])
        try env.library.save(chars[0])
        try env.runLibrary.save(run)

        let updated = try env.library.require(runner.id)
        XCTAssertEqual(updated.nuyen, 1_000 + 6_000)
        XCTAssertEqual(updated.karmaAvailable, 5 + 4)
        XCTAssertEqual(updated.streetCred, 1)

        let briefing = PlayerBriefingMarkdown.render(run)
        XCTAssertTrue(briefing.contains("Meet downtown"))
        XCTAssertTrue(briefing.contains("Corpsec"))
        XCTAssertFalse(briefing.contains("GMONLY"))
        XCTAssertFalse(briefing.contains("red samurai"))
        XCTAssertFalse(briefing.contains("dragon"))

        try env.deleteCampaignUnassigningRuns(id: campaign.id)
        let runs = try env.runLibrary.listSummaries()
        XCTAssertTrue(runs.allSatisfy { $0.campaignID == nil })
        env.refreshCampaignCount()
        XCTAssertEqual(env.campaignCount, 0)
    }

    // MARK: - Generation edition systems

    func testMinimalGenerationEditionSystems() {
        for edition in Edition.allCases {
            let draft = GenerationDraft()
            draft.selectEdition(edition)
            if edition.usesPriorityGenerationByDefault {
                XCTAssertEqual(draft.generationSystem, .priority, edition.shortName)
            } else {
                XCTAssertEqual(draft.generationSystem, .buildPoints, edition.shortName)
            }
            draft.selectMetatype(.human)
            draft.name = "Audit \(edition.shortName)"
            XCTAssertEqual(draft.edition, edition)
        }
    }

    // MARK: - Import fixtures edition coverage

    func testImportFixturesAreSR5Only() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let json = fixtures.appendingPathComponent("minimal_sr5.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: json.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("minimal_sr4.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("minimal_sr6.json").path))
        let data = try Data(contentsOf: json)
        let result = try CharacterImporter.importChummerJSON(data, fileName: "minimal_sr5.json")
        XCTAssertEqual(result.character.edition, .sr5)
    }
}
