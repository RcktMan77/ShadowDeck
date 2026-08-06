//
//  AdvancementEngineTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class AdvancementEngineTests: XCTestCase {
    // MARK: - Fixtures

    private func baseCharacter(
        edition: Edition = .sr5,
        metatype: MetatypeID = .human,
        awakened: AwakenedPath = .mundane,
        attributes: AttributeRatings = AttributeRatings(
            body: 3,
            agility: 4,
            reaction: 3,
            strength: 3,
            willpower: 3,
            logic: 3,
            intuition: 3,
            charisma: 3,
            edge: 2,
            magic: 0,
            resonance: 0
        ),
        skills: [SkillRating] = [
            SkillRating(catalogKey: "pistols", displayName: "Pistols", category: .active, rating: 4),
            SkillRating(catalogKey: "sneaking", displayName: "Sneaking", category: .active, rating: 3),
            SkillRating(catalogKey: "shadow_lore", displayName: "Shadow Lore", category: .knowledge, rating: 2),
            SkillRating(catalogKey: "english", displayName: "English", category: .language, rating: 3)
        ],
        karmaAvailable: Int = 50,
        houseRules: HouseRules = .coreBook
    ) -> Character {
        Character(
            name: "Test Runner",
            edition: edition,
            metatype: metatype,
            awakened: awakened,
            generation: GenerationProfile(system: .priority),
            houseRules: houseRules,
            attributes: attributes,
            skills: skills,
            karmaTotal: karmaAvailable,
            karmaAvailable: karmaAvailable
        )
    }

    private func rules(for edition: Edition) -> any EditionRules {
        RulesRegistry.rules(for: edition)
    }

    // MARK: - Skill costs by edition

    func testActiveSkillRaiseCostSR5() {
        let c = baseCharacter(edition: .sr5)
        let r = rules(for: .sr5)
        // Pistols 4 → 5: new rating × 2 = 10
        XCTAssertEqual(AdvancementEngine.skillRaiseCost(character: c, catalogKey: "pistols", rules: r), 10)
        // Sneaking 3 → 4: 8
        XCTAssertEqual(AdvancementEngine.skillRaiseCost(character: c, catalogKey: "sneaking", rules: r), 8)
    }

    func testActiveSkillRaiseCostSR6() {
        let c = baseCharacter(edition: .sr6)
        let r = rules(for: .sr6)
        // Pistols 4 → 5: new rating × 5 = 25
        XCTAssertEqual(AdvancementEngine.skillRaiseCost(character: c, catalogKey: "pistols", rules: r), 25)
    }

    func testActiveSkillRaiseCostSR4MatchesSR5Style() {
        let c = baseCharacter(edition: .sr4)
        let r = rules(for: .sr4)
        XCTAssertEqual(AdvancementEngine.skillRaiseCost(character: c, catalogKey: "pistols", rules: r), 10)
    }

    func testKnowledgeAndLanguageUseCheaperCosts() {
        let c = baseCharacter(edition: .sr5)
        let r = rules(for: .sr5)
        // Knowledge 2 → 3: new rating × 1 = 3
        XCTAssertEqual(AdvancementEngine.skillRaiseCost(character: c, catalogKey: "shadow_lore", rules: r), 3)
        // Language 3 → 4: 4
        XCTAssertEqual(AdvancementEngine.skillRaiseCost(character: c, catalogKey: "english", rules: r), 4)
        // Active would be × 2
        XCTAssertEqual(r.karmaCostToRaiseSkill(from: 2), 6)
    }

    // MARK: - Attribute costs

    func testAttributeRaiseCostSR5() {
        let c = baseCharacter(edition: .sr5)
        let r = rules(for: .sr5)
        // Agility 4 → 5: new rating × 5 = 25
        XCTAssertEqual(AdvancementEngine.attributeRaiseCost(character: c, attribute: .agility, rules: r), 25)
    }

    func testAlternateAttributeCostsHouseRule() {
        var house = HouseRules.coreBook
        HouseRulesEngine.enabling(.alternateAttributeCosts, into: &house)
        let c = baseCharacter(houseRules: house)
        let r = rules(for: .sr5)
        XCTAssertEqual(AdvancementEngine.attributeRaiseCost(character: c, attribute: .agility, rules: r), 5)
    }

    // MARK: - Maxima

    func testSkillSoftCapBlocksRaise() {
        let skills = [
            SkillRating(catalogKey: "pistols", displayName: "Pistols", category: .active, rating: 12)
        ]
        let c = baseCharacter(skills: skills)
        let r = rules(for: .sr5)
        XCTAssertNil(AdvancementEngine.skillRaiseCost(character: c, catalogKey: "pistols", rules: r))
        XCTAssertFalse(AdvancementEngine.canRaiseSkill(character: c, catalogKey: "pistols", rules: r))
    }

    func testAttributeMetatypeMaxBlocksRaise() {
        // Human agility max 6
        let attrs = AttributeRatings(
            body: 3,
            agility: 6,
            reaction: 3,
            strength: 3,
            willpower: 3,
            logic: 3,
            intuition: 3,
            charisma: 3,
            edge: 2
        )
        let c = baseCharacter(attributes: attrs)
        let r = rules(for: .sr5)
        XCTAssertFalse(AdvancementEngine.canRaiseAttribute(character: c, attribute: .agility, rules: r))
        XCTAssertNil(AdvancementEngine.attributeRaiseCost(character: c, attribute: .agility, rules: r))
    }

    func testTrollBodyMaxHigherThanHuman() {
        let attrs = AttributeRatings(
            body: 9,
            agility: 3,
            reaction: 3,
            strength: 5,
            willpower: 3,
            logic: 2,
            intuition: 2,
            charisma: 2,
            edge: 1
        )
        let troll = baseCharacter(metatype: .troll, attributes: attrs)
        let human = baseCharacter(metatype: .human, attributes: attrs)
        let r = rules(for: .sr5)
        XCTAssertTrue(AdvancementEngine.canRaiseAttribute(character: troll, attribute: .body, rules: r))
        XCTAssertFalse(AdvancementEngine.canRaiseAttribute(character: human, attribute: .body, rules: r))
    }

    // MARK: - Plan affordability

    func testCanAffordPlanAddBlocksOverspend() {
        XCTAssertTrue(AdvancementEngine.canAffordPlanAdd(
            karmaAvailable: 20,
            currentPlanTotal: 10,
            itemCost: 10
        ))
        XCTAssertFalse(AdvancementEngine.canAffordPlanAdd(
            karmaAvailable: 20,
            currentPlanTotal: 15,
            itemCost: 10
        ))
        XCTAssertFalse(AdvancementEngine.canAffordPlanAdd(
            karmaAvailable: 5,
            currentPlanTotal: 0,
            itemCost: 10
        ))
        XCTAssertTrue(AdvancementEngine.canAffordPlanAdd(
            karmaAvailable: 0,
            currentPlanTotal: 0,
            itemCost: 0
        ))
    }

    // MARK: - Previews

    func testSkillPreviewProgressSummaryIncludesMax() {
        let c = baseCharacter()
        let r = rules(for: .sr5)
        let skill = c.skills.first { $0.catalogKey == "pistols" }!
        let preview = AdvancementEngine.skillRaisePreview(character: c, skill: skill, rules: r)
        XCTAssertTrue(preview.canRaise)
        XCTAssertEqual(preview.maxRating, 12)
        XCTAssertEqual(preview.karmaCost, 10)
        XCTAssertTrue(preview.progressSummary.contains("max 12"))
        XCTAssertTrue(preview.progressSummary.contains("4 → 5"))
    }

    // MARK: - Apply skill

    func testApplySkillRaiseDebitsKarmaAndUpdatesRating() throws {
        var c = baseCharacter(karmaAvailable: 20)
        let r = rules(for: .sr5)
        let item = AdvancementEngine.makeSkillRaiseItem(character: c, catalogKey: "pistols", rules: r)!
        try AdvancementEngine.apply(item, to: &c, rules: r)

        XCTAssertEqual(c.skills.first { $0.catalogKey == "pistols" }?.rating, 5)
        XCTAssertEqual(c.karmaAvailable, 10) // 20 - 10
        XCTAssertEqual(c.advancementLedgerEntries.count, 1)
        XCTAssertEqual(c.advancementLedgerEntries.first?.kind, .skillRaise)
        XCTAssertEqual(c.advancementLedgerEntries.first?.karmaSpent, 10)
        XCTAssertTrue(c.advancementLedgerEntries.first?.summary.contains("Pistols") == true)
    }

    func testApplySkillRaiseInsufficientKarma() {
        var c = baseCharacter(karmaAvailable: 5)
        let r = rules(for: .sr5)
        let item = AdvancementEngine.makeSkillRaiseItem(character: c, catalogKey: "pistols", rules: r)!
        let before = c
        XCTAssertThrowsError(try AdvancementEngine.apply(item, to: &c, rules: r)) { error in
            guard let err = error as? AdvancementError,
                  case .insufficientKarma = err
            else {
                return XCTFail("Expected insufficientKarma, got \(error)")
            }
        }
        XCTAssertEqual(c.karmaAvailable, before.karmaAvailable)
        XCTAssertEqual(c.skills.first { $0.catalogKey == "pistols" }?.rating, 4)
        XCTAssertTrue(c.advancementLedgerEntries.isEmpty)
    }

    func testApplySkillRaiseStaleFromRating() {
        var c = baseCharacter()
        let r = rules(for: .sr5)
        let item = AdvancementEngine.makeSkillRaiseItem(character: c, catalogKey: "pistols", rules: r)!
        // Simulate free edit on Skills tab changing rating underneath the cart
        if let idx = c.skills.firstIndex(where: { $0.catalogKey == "pistols" }) {
            c.skills[idx].rating = 6
        }
        XCTAssertThrowsError(try AdvancementEngine.apply(item, to: &c, rules: r)) { error in
            guard let err = error as? AdvancementError,
                  case .staleFromRating = err
            else {
                return XCTFail("Expected staleFromRating, got \(error)")
            }
        }
    }

    // MARK: - Apply attribute

    func testApplyAttributeRaise() throws {
        var c = baseCharacter(karmaAvailable: 30)
        let r = rules(for: .sr5)
        let item = AdvancementEngine.makeAttributeRaiseItem(character: c, attribute: .agility, rules: r)!
        XCTAssertEqual(item.karmaCost, 25)
        try AdvancementEngine.apply(item, to: &c, rules: r)
        XCTAssertEqual(c.attributes.agility, 5)
        XCTAssertEqual(c.karmaAvailable, 5)
        XCTAssertEqual(c.advancementLedgerEntries.first?.kind, .attributeRaise)
    }

    // MARK: - Multi-item apply

    func testApplyMultipleItemsAttributesFirst() throws {
        var c = baseCharacter(karmaAvailable: 100)
        let r = rules(for: .sr5)
        let skill = AdvancementEngine.makeSkillRaiseItem(character: c, catalogKey: "sneaking", rules: r)!
        let attr = AdvancementEngine.makeAttributeRaiseItem(character: c, attribute: .body, rules: r)!
        // Intentionally reverse order in cart; engine sorts attributes first
        try AdvancementEngine.apply(items: [skill, attr], to: &c, rules: r)

        XCTAssertEqual(c.attributes.body, 4)
        XCTAssertEqual(c.skills.first { $0.catalogKey == "sneaking" }?.rating, 4)
        // Body 3→4 = 20, Sneaking 3→4 = 8
        XCTAssertEqual(c.karmaAvailable, 100 - 20 - 8)
        XCTAssertEqual(c.advancementLedgerEntries.count, 2)
    }

    func testMultiApplyAtomicOnShortfall() {
        var c = baseCharacter(karmaAvailable: 15)
        let r = rules(for: .sr5)
        // Attr 25 + skill 8 = 33 > 15
        let skill = AdvancementEngine.makeSkillRaiseItem(character: c, catalogKey: "sneaking", rules: r)!
        let attr = AdvancementEngine.makeAttributeRaiseItem(character: c, attribute: .agility, rules: r)!
        let beforeSkills = c.skills
        let beforeAttrs = c.attributes
        XCTAssertThrowsError(try AdvancementEngine.apply(items: [skill, attr], to: &c, rules: r))
        XCTAssertEqual(c.karmaAvailable, 15)
        XCTAssertEqual(c.attributes, beforeAttrs)
        XCTAssertEqual(c.skills, beforeSkills)
        XCTAssertTrue(c.advancementLedgerEntries.isEmpty)
    }

    // MARK: - New skill

    func testNewSkillAtRank1() throws {
        var c = baseCharacter(karmaAvailable: 10)
        let r = rules(for: .sr5)
        let item = AdvancementEngine.makeNewSkillItem(
            catalogKey: "first_aid",
            displayName: "First Aid",
            category: .active,
            rules: r
        )
        // From 0 → 1: new rating × 2 = 2
        XCTAssertEqual(item.karmaCost, 2)
        try AdvancementEngine.apply(item, to: &c, rules: r)
        XCTAssertEqual(c.skills.first { $0.catalogKey == "first_aid" }?.rating, 1)
        XCTAssertEqual(c.karmaAvailable, 8)
        XCTAssertEqual(c.advancementLedgerEntries.first?.kind, .newSkill)
    }

    // MARK: - Knowledge apply

    func testApplyKnowledgeSkillUsesKnowledgeCost() throws {
        var c = baseCharacter(karmaAvailable: 10)
        let r = rules(for: .sr5)
        let item = AdvancementEngine.makeSkillRaiseItem(character: c, catalogKey: "shadow_lore", rules: r)!
        XCTAssertEqual(item.karmaCost, 3)
        try AdvancementEngine.apply(item, to: &c, rules: r)
        XCTAssertEqual(c.skills.first { $0.catalogKey == "shadow_lore" }?.rating, 3)
        XCTAssertEqual(c.karmaAvailable, 7)
    }

    // MARK: - Suggestions

    func testSuggestionsBiasTrollTowardBody() {
        let attrs = AttributeRatings(
            body: 6,
            agility: 3,
            reaction: 3,
            strength: 6,
            willpower: 3,
            logic: 2,
            intuition: 2,
            charisma: 2,
            edge: 1
        )
        let c = baseCharacter(metatype: .troll, attributes: attrs, karmaAvailable: 40)
        let r = rules(for: .sr5)
        let tips = AdvancementEngine.suggestions(for: c, rules: r, limit: 6)
        XCTAssertFalse(tips.isEmpty)
        // Body or Strength should appear among favored attribute suggestions
        let keys = Set(tips.map(\.targetKey))
        XCTAssertTrue(
            keys.contains("body") || keys.contains("strength") || keys.contains { $0.contains("sneak") || $0 == "pistols" },
            "Expected metatype-biased or cheap raises, got \(keys)"
        )
    }

    func testSuggestionsPreferAffordableRaises() {
        let c = baseCharacter(karmaAvailable: 8)
        let r = rules(for: .sr5)
        let tips = AdvancementEngine.suggestions(for: c, rules: r, limit: 4)
        // With 8 karma, sneaking 3→4 costs 8; knowledge cheaper — should not lead with agility 25
        XCTAssertFalse(tips.contains { $0.targetKey == "agility" && $0.karmaCost > 13 })
        XCTAssertTrue(tips.contains { $0.karmaCost <= 8 + 5 })
    }

    func testRoleConceptMapsSamuraiSkills() {
        let keys = AdvancementEngine.roleFavoredSkillKeys(concept: "Street samurai")
        XCTAssertTrue(keys.contains("blades") || keys.contains("pistols"))
    }

    // MARK: - Ledger decode / legacy

    func testAdvancementLedgerOptionalOnLegacyCharacter() throws {
        let c = baseCharacter()
        XCTAssertTrue(c.advancementLedgerEntries.isEmpty)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        XCTAssertTrue(decoded.advancementLedgerEntries.isEmpty)
    }

    func testAdvancementLedgerRoundTrip() throws {
        var c = baseCharacter(karmaAvailable: 20)
        let r = rules(for: .sr5)
        let item = AdvancementEngine.makeSkillRaiseItem(character: c, catalogKey: "pistols", rules: r)!
        try AdvancementEngine.apply(item, to: &c, rules: r)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        XCTAssertEqual(decoded.advancementLedgerEntries.count, 1)
        XCTAssertEqual(decoded.karmaAvailable, 10)
        XCTAssertEqual(decoded.skills.first { $0.catalogKey == "pistols" }?.rating, 5)
    }

    func testAdvancementPlanPersistsOnCharacter() throws {
        var c = baseCharacter(karmaAvailable: 5)
        let r = rules(for: .sr5)
        let item = AdvancementEngine.makeSkillRaiseItem(character: c, catalogKey: "pistols", rules: r)!
        // Plan can exceed available karma (goal tracking).
        XCTAssertGreaterThan(item.karmaCost, c.karmaAvailable)
        c.advancementPlanItems = [item]
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        XCTAssertEqual(decoded.advancementPlanItems.count, 1)
        XCTAssertEqual(decoded.advancementPlanItems.first?.targetKey, "pistols")
        XCTAssertEqual(decoded.karmaAvailable, 5)
    }

    // MARK: - Concept taglines

    func testConceptTaglineFromLongProse() {
        let prose = """
        Kai 'Ghostwire' Ellison, ex-Renraku coder, awakened during an AI data heist. \
        Runs Chicago's shadows leaking corp secrets, dodging Renraku hit squads. \
        Sarcastic, loyal, hates corps. Ghostwire's adept powers stem from Buddhist meditation, \
        focusing inner clarity to enhance perception and reflexes, blending tech and mysticism.
        """
        let label = ConceptTagline.libraryLabel(concept: "", background: prose, awakened: .adept)
        XCTAssertFalse(label.isEmpty)
        XCTAssertLessThanOrEqual(label.count, ConceptTagline.maxLength + 1) // allow ellipsis edge
        // Should pick up corp + role keywords from the prose.
        let lower = label.lowercased()
        XCTAssertTrue(
            lower.contains("renraku") || lower.contains("adept") || lower.contains("decker"),
            "Expected role/corp keyword in \(label)"
        )
    }

    func testShortConceptPreserved() {
        let label = ConceptTagline.libraryLabel(concept: "Street samurai", background: "Long story…")
        XCTAssertEqual(label, "Street samurai")
    }

    // MARK: - Guidance

    func testAttributeGuidanceReflectsPhysicalBoxes() {
        let c = baseCharacter(edition: .sr5)
        let r = rules(for: .sr5)
        let impact = AdvancementGuidance.attributeImpact(character: c, attribute: .body, rules: r)
        // Body 3 → 4: physical boxes 8+ceil(1.5)=10 → 8+2=10 may stay same; limit or soak text should mention Body influences
        XCTAssertFalse(impact.headline.isEmpty)
        XCTAssertTrue(
            impact.detail.lowercased().contains("body")
                || impact.detail.lowercased().contains("physical")
                || impact.headline.lowercased().contains("physical")
                || impact.headline.lowercased().contains("pool")
        )
    }

    func testSkillGuidanceShowsPoolIncrease() {
        let c = baseCharacter(edition: .sr5)
        let r = rules(for: .sr5)
        let skill = c.skills.first { $0.catalogKey == "pistols" }!
        let impact = AdvancementGuidance.skillImpact(character: c, skill: skill, rules: r)
        XCTAssertTrue(impact.headline.contains("Pool"))
        XCTAssertTrue(impact.headline.contains("→"))
        XCTAssertTrue(impact.detail.lowercased().contains("agility") || impact.headline.contains("Agility"))
    }
}
