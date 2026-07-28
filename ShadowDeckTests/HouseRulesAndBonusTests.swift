//
//  HouseRulesAndBonusTests.swift
//  ShadowDeckTests
//
//  House-rules multi-select + tighter Chummer bonus expression parsing.
//

import XCTest
@testable import ShadowDeck

final class HouseRulesAndBonusTests: XCTestCase {
    func testHouseRulesStackAndPresets() {
        var rules = HouseRules.coreBook
        HouseRulesEngine.enabling(.sumToTen, into: &rules)
        HouseRulesEngine.enabling(.freeKnowledgeSkills, into: &rules)
        HouseRulesEngine.enabling(.expandedContacts, into: &rules)
        XCTAssertTrue(rules.isEnabled(.sumToTen))
        XCTAssertTrue(rules.isEnabled(.freeKnowledgeSkills))
        XCTAssertTrue(rules.isEnabled(.expandedContacts))
        XCTAssertEqual(rules.extraContactPoints, 3)
    }

    func testKarmaGenExcludesSumToTen() {
        var rules = HouseRules.coreBook
        HouseRulesEngine.enabling(.sumToTen, into: &rules)
        HouseRulesEngine.enabling(.karmaGeneration, into: &rules)
        XCTAssertTrue(rules.isEnabled(.karmaGeneration))
        XCTAssertFalse(rules.isEnabled(.sumToTen))
    }

    func testStartingKarmaAndContactPoints() {
        let popular = HouseRules.popularTable
        let karma = HouseRulesEngine.startingKarma(editionBaseline: 25, houseRules: popular)
        XCTAssertEqual(karma, 50) // 25 + 25 bonus
        let contacts = HouseRulesEngine.contactPoints(charisma: 5, houseRules: popular)
        XCTAssertEqual(contacts, 5 * 3 + 3)
    }

    func testFreeKnowledgeAutoFormula() {
        var rules = HouseRules.coreBook
        HouseRulesEngine.enabling(.freeKnowledgeSkills, into: &rules)
        rules.freeKnowledgePoints = 0
        let attrs = AttributeRatings(logic: 5, intuition: 4)
        XCTAssertEqual(
            HouseRulesEngine.freeKnowledgePoints(attributes: attrs, houseRules: rules),
            18
        )
    }

    func testPrimePackageNuyenBump() {
        let base = 50_000
        let n = HouseRulesEngine.resourceNuyen(base: base, houseRules: .primeRunner)
        XCTAssertEqual(n, 55_000)
    }

    func testAlternateAttributeCostsLinear() {
        let rules = RulesRegistry.rules(for: .sr5)
        var house = HouseRules.coreBook
        XCTAssertEqual(rules.karmaCostToRaiseAttribute(from: 3, houseRules: house), 20)
        house.enable(.alternateAttributeCosts)
        XCTAssertEqual(rules.karmaCostToRaiseAttribute(from: 3, houseRules: house), 5)
    }

    func testBonusParserRatingOffset() {
        let parsed = BonusParser.parseAmount("Rating-1")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.amount, 1)
        XCTAssertEqual(parsed?.usesRating, true)
        XCTAssertEqual(parsed?.ratingOffset, -1)
        let mod = parsed!.asModifier(target: .body)
        XCTAssertEqual(mod.resolvedAmount(rating: 3), 2) // 3 - 1
    }

    func testBonusParserNegRatingAndTimes() {
        let neg = BonusParser.parseAmount("-Rating")
        XCTAssertEqual(neg?.resolvedForTest(rating: 2), -2)
        let times = BonusParser.parseAmount("Rating*2")
        XCTAssertEqual(times?.resolvedForTest(rating: 3), 6)
    }

    func testBonusParserFixedValues() {
        let parsed = BonusParser.parseAmount("FixedValues(3,6,9)")
        XCTAssertEqual(parsed?.ratingTable, [3, 6, 9])
        let mod = parsed!.asModifier(target: .initiative)
        XCTAssertEqual(mod.resolvedAmount(rating: 1), 3)
        XCTAssertEqual(mod.resolvedAmount(rating: 2), 6)
        XCTAssertEqual(mod.resolvedAmount(rating: 3), 9)
        XCTAssertEqual(mod.resolvedAmount(rating: 9), 9) // clamp high
    }

    func testCatalogMoveByWireHasTables() {
        CatalogLookup.resetCache()
        let mods = CatalogLookup.modifiers(named: "Move-by-Wire System")
        XCTAssertFalse(mods.isEmpty)
        XCTAssertTrue(mods.contains { $0.ratingTable != nil })
    }

    func testCatalogImprovedReflexes() {
        CatalogLookup.resetCache()
        let mods = CatalogLookup.modifiers(named: "Improved Reflexes")
        XCTAssertTrue(mods.contains { $0.target == .reaction && $0.usesRating })
        XCTAssertTrue(mods.contains { $0.target == .initiativeDice && $0.usesRating })
    }
}

private extension BonusParser.ParsedAmount {
    func resolvedForTest(rating: Int) -> Int {
        asModifier(target: .body).resolvedAmount(rating: rating)
    }
}
