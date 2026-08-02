//
//  EditionRulesTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class EditionRulesTests: XCTestCase {
    func testAllEditionsHavePeerRules() {
        for edition in Edition.allCases {
            let rules = RulesRegistry.rules(for: edition)
            XCTAssertEqual(rules.edition, edition)
            XCTAssertFalse(rules.defaultGenerationSystem.displayName.isEmpty)
        }
        XCTAssertEqual(RulesRegistry.all.count, 3)
    }

    func testEditionFlags() {
        XCTAssertFalse(Edition.sr4.usesPriorityGenerationByDefault)
        XCTAssertTrue(Edition.sr5.usesPriorityGenerationByDefault)
        XCTAssertTrue(Edition.sr6.usesPriorityGenerationByDefault)

        XCTAssertFalse(Edition.sr4.usesLimits)
        XCTAssertTrue(Edition.sr5.usesLimits)
        XCTAssertFalse(Edition.sr6.usesLimits)

        XCTAssertTrue(Edition.sr6.usesSessionEdgePool)
        XCTAssertFalse(Edition.sr5.usesSessionEdgePool)
    }

    func testSR5LimitsMath() {
        // STR 5, BOD 4, REA 5 → (10+4+5)/3 = 6.33 → 7
        XCTAssertEqual(DerivedStatsCalculator.physicalLimit(strength: 5, body: 4, reaction: 5), 7)
        // LOG 5, INT 4, WIL 5 → (10+4+5)/3 = 6.33 → 7
        XCTAssertEqual(DerivedStatsCalculator.mentalLimit(logic: 5, intuition: 4, willpower: 5), 7)
        // CHA 5, WIL 4, ESS 6 → (10+4+6)/3 = 6.66 → 7
        XCTAssertEqual(DerivedStatsCalculator.socialLimit(charisma: 5, willpower: 4, essence: 6), 7)
    }

    func testConditionMonitors() {
        // Body 5 → 8 + ceil(2.5) = 8+3 = 11
        XCTAssertEqual(DerivedStatsCalculator.physicalBoxes(body: 5), 11)
        // Willpower 3 → 8 + ceil(1.5) = 8+2 = 10
        XCTAssertEqual(DerivedStatsCalculator.stunBoxes(willpower: 3), 10)
    }

    func testKarmaCostsDifferByEditionForSkills() {
        let sr4 = SR4Rules()
        let sr5 = SR5Rules()
        let sr6 = SR6Rules()
        // Raise skill from 3 → 4
        XCTAssertEqual(sr4.karmaCostToRaiseSkill(from: 3), 8)
        XCTAssertEqual(sr5.karmaCostToRaiseSkill(from: 3), 8)
        XCTAssertEqual(sr6.karmaCostToRaiseSkill(from: 3), 20)
    }

    func testPriorityResourceTablesArePresent() {
        for rules in RulesRegistry.all {
            for letter in PriorityLetter.allCases {
                XCTAssertNotNil(
                    rules.resourceNuyen(for: letter),
                    "\(rules.edition) missing resources for \(letter)"
                )
                XCTAssertNotNil(
                    rules.attributePoints(for: letter),
                    "\(rules.edition) missing attribute points for \(letter)"
                )
            }
        }
    }

    func testSumToTenValues() {
        XCTAssertEqual(PriorityLetter.a.sumToTenValue, 4)
        XCTAssertEqual(PriorityLetter.b.sumToTenValue, 3)
        XCTAssertEqual(PriorityLetter.c.sumToTenValue, 2)
        XCTAssertEqual(PriorityLetter.d.sumToTenValue, 1)
        XCTAssertEqual(PriorityLetter.e.sumToTenValue, 0)

        let assignment = PriorityAssignment(values: [
            .metatype: .a,
            .attributes: .b,
            .magicOrResonance: .c,
            .skills: .d,
            .resources: .e
        ])
        XCTAssertEqual(assignment.sumToTenTotal, 10)
        XCTAssertTrue(assignment.usesUniqueLetters)
        XCTAssertTrue(assignment.isComplete)
    }
}
