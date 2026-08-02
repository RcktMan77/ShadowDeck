//
//  RulesCalculatorTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class RulesCalculatorTests: XCTestCase {
    // MARK: - Karma

    func testKarmaActiveSkillSR5SingleStep() {
        let rules = RulesRegistry.rules(for: .sr5)
        // from 3 → 4: new rating 4 × 2 = 8
        XCTAssertEqual(
            KarmaRaiseCalculator.cost(from: 3, to: 4, category: .active, rules: rules),
            8
        )
        XCTAssertEqual(
            KarmaRaiseCalculator.skillStepCost(current: 3, category: .active, rules: rules),
            8
        )
    }

    func testKarmaMultiStepSums() {
        let rules = RulesRegistry.rules(for: .sr5)
        // 2→3 = 3×2=6; 3→4 = 4×2=8; total 14
        XCTAssertEqual(
            KarmaRaiseCalculator.cost(from: 2, to: 4, category: .active, rules: rules),
            14
        )
    }

    func testKarmaKnowledgeCheaper() {
        let rules = RulesRegistry.rules(for: .sr5)
        let active = KarmaRaiseCalculator.skillStepCost(current: 3, category: .active, rules: rules)
        let know = KarmaRaiseCalculator.skillStepCost(current: 3, category: .knowledge, rules: rules)
        XCTAssertEqual(know, 4) // new rating × 1
        XCTAssertLessThan(know, active)
    }

    func testKarmaAttributeSR5() {
        let rules = RulesRegistry.rules(for: .sr5)
        // 3→4: 4×5 = 20
        XCTAssertEqual(
            KarmaRaiseCalculator.attributeCost(from: 3, to: 4, rules: rules),
            20
        )
    }

    func testKarmaAttributeHouseRuleFlat() {
        let rules = RulesRegistry.rules(for: .sr5)
        var hr = HouseRules.coreBook
        hr.enable(.alternateAttributeCosts)
        XCTAssertEqual(
            KarmaRaiseCalculator.attributeStepCost(current: 5, rules: rules, houseRules: hr),
            5
        )
    }

    func testKarmaInvalidRange() {
        let rules = RulesRegistry.rules(for: .sr5)
        XCTAssertNil(KarmaRaiseCalculator.cost(from: 4, to: 4, category: .active, rules: rules))
        XCTAssertNil(KarmaRaiseCalculator.cost(from: 5, to: 3, category: .active, rules: rules))
    }

    // MARK: - Glitch

    func testGlitchMoreThanHalfSR5() {
        let r = GlitchThresholdCalculator.evaluate(pool: 12, edition: .sr5, diceRules: .coreBook)
        XCTAssertEqual(r.mode, .moreThanHalf)
        XCTAssertEqual(r.onesNeeded, 7)
        XCTAssertTrue(GlitchThresholdCalculator.isGlitch(ones: 7, pool: 12, edition: .sr5))
        XCTAssertFalse(GlitchThresholdCalculator.isGlitch(ones: 6, pool: 12, edition: .sr5))
    }

    func testGlitchHalfOrMoreSR4() {
        let r = GlitchThresholdCalculator.evaluate(pool: 12, edition: .sr4, diceRules: .coreBook)
        XCTAssertEqual(r.mode, .halfOrMore)
        XCTAssertEqual(r.onesNeeded, 6)
        XCTAssertTrue(GlitchThresholdCalculator.isGlitch(ones: 6, pool: 12, edition: .sr4))
        XCTAssertFalse(GlitchThresholdCalculator.isGlitch(ones: 5, pool: 12, edition: .sr4))
    }

    func testGlitchHouseRuleOverride() {
        var dice = DiceHouseRules.coreBook
        dice.glitchThreshold = .halfOrMore
        let r = GlitchThresholdCalculator.evaluate(pool: 10, edition: .sr5, diceRules: dice)
        XCTAssertEqual(r.mode, .halfOrMore)
        XCTAssertEqual(r.onesNeeded, 5)
    }

    // MARK: - Lifestyle / monitors / limits

    func testLifestyleSuggested() {
        XCTAssertEqual(LifestyleBurnCalculator.suggestedMonthlyCost(level: .middle), 5_000)
        XCTAssertEqual(
            LifestyleBurnCalculator.totalSuggested(levels: [.low, .middle]),
            7_000
        )
    }

    func testConditionMonitors() {
        // Body 3 → 8 + 2 = 10
        XCTAssertEqual(ConditionMonitorCalculator.physicalBoxes(body: 3), 10)
        // WIL 5 → 8 + 3 = 11
        XCTAssertEqual(ConditionMonitorCalculator.stunBoxes(willpower: 5), 11)
    }

    func testLimitsSR5() {
        let r = LimitsSR5Calculator.evaluate(
            body: 3,
            reaction: 3,
            strength: 3,
            willpower: 3,
            logic: 3,
            intuition: 3,
            charisma: 3,
            essence: 6
        )
        // Physical ceil((6+3+3)/3)=4
        XCTAssertEqual(r.physical, 4)
        XCTAssertEqual(r.mental, 4)
        // Social ceil((6+3+6)/3)=5
        XCTAssertEqual(r.social, 5)
    }

    // MARK: - Drain

    func testDrainHalfForceRounding() {
        XCTAssertEqual(DrainCalculator.halfForceRoundedUp(5), 3)
        XCTAssertEqual(DrainCalculator.halfForceRoundedUp(6), 3)
        XCTAssertEqual(DrainCalculator.drainValue(force: 6, code: .halfForcePlus2), 5)
        XCTAssertEqual(DrainCalculator.drainValue(force: 6, code: .forceMinus2), 4)
    }

    func testDrainEvaluateResistHint() {
        let r = DrainCalculator.evaluate(
            force: 6,
            code: .halfForce,
            willpower: 4,
            traditionAttribute: 5
        )
        XCTAssertEqual(r.drainValue, 3)
        XCTAssertEqual(r.resistPoolHint, 9)
        XCTAssertTrue(r.note.lowercased().contains("quick aid"))
    }

    func testDrainNonNegative() {
        XCTAssertEqual(DrainCalculator.drainValue(force: 1, code: .forceMinus3), 0)
    }

    // MARK: - Overwatch

    func testOverwatchAccumulateAndThreshold() {
        var score = 0
        let hack = OverwatchCalculator.action(id: "hack_on_fly")!
        score = OverwatchCalculator.apply(score: score, action: hack)
        XCTAssertEqual(score, 3)
        score = OverwatchCalculator.apply(score: score, delta: 37)
        let snap = OverwatchCalculator.snapshot(score: score)
        XCTAssertTrue(snap.converged)
        XCTAssertEqual(snap.threshold, OverwatchCalculator.defaultGODThreshold)
    }

    func testOverwatchDefaultActionsNonEmpty() {
        XCTAssertFalse(OverwatchCalculator.defaultActions.isEmpty)
        XCTAssertTrue(OverwatchCalculator.defaultActions.allSatisfy { $0.osCost >= 0 })
    }
}
