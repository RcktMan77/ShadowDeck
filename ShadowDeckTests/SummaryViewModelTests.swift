//
//  SummaryViewModelTests.swift
//  ShadowDeckTests
//
//  Phase 5 — derived dashboard data stays coherent for at-a-glance display.
//

import XCTest
@testable import ShadowDeck

final class SummaryViewModelTests: XCTestCase {

    func testDerivedStatsPresentForAllSampleEditions() {
        for sample in SampleCharacters.makeAll() {
            let rules = RulesRegistry.rules(for: sample.edition)
            let derived = rules.deriveStats(for: sample)
            XCTAssertGreaterThan(derived.condition.physicalBoxes, 0, sample.edition.rawValue)
            XCTAssertGreaterThan(derived.condition.stunBoxes, 0, sample.edition.rawValue)
            XCTAssertGreaterThan(derived.initiativeBase, 0, sample.edition.rawValue)
            XCTAssertGreaterThanOrEqual(derived.initiativeDice, 1, sample.edition.rawValue)
            XCTAssertGreaterThan(NSDecimalNumber(decimal: derived.currentEssence).doubleValue, 0, sample.edition.rawValue)
        }
    }

    func testSR5SampleHasLimitsOnSummary() {
        let c = SampleCharacters.sr5CombatMage()
        let d = RulesRegistry.rules(for: .sr5).deriveStats(for: c)
        XCTAssertNotNil(d.physicalLimit)
        XCTAssertNotNil(d.mentalLimit)
        XCTAssertNotNil(d.socialLimit)
        XCTAssertTrue(c.edition.usesLimits)
    }

    func testSR4AndSR6DoNotRequireLimits() {
        XCTAssertFalse(SampleCharacters.sr4StreetSamurai().edition.usesLimits)
        XCTAssertFalse(SampleCharacters.sr6FaceHacker().edition.usesLimits)
        let d4 = RulesRegistry.rules(for: .sr4).deriveStats(for: SampleCharacters.sr4StreetSamurai())
        let d6 = RulesRegistry.rules(for: .sr6).deriveStats(for: SampleCharacters.sr6FaceHacker())
        XCTAssertNil(d4.physicalLimit)
        XCTAssertNil(d6.physicalLimit)
    }

    func testDisplayTitleForSummaryHeader() {
        let c = SampleCharacters.sr5CombatMage()
        XCTAssertTrue(c.displayTitle.contains("Hex") || c.displayTitle.contains("Elena"))
    }

    func testTopSkillsOrderingForDashboard() {
        let c = SampleCharacters.sr6FaceHacker()
        let top = c.skills.filter { $0.rating > 0 }.sorted { $0.rating > $1.rating }
        XCTAssertFalse(top.isEmpty)
        if top.count >= 2 {
            XCTAssertGreaterThanOrEqual(top[0].rating, top[1].rating)
        }
    }
}
