//
//  DiceRollerEngineTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class DiceRollerEngineTests: XCTestCase {

    // MARK: - Hits / evaluate

    func testHitsOnFiveAndSix() {
        let faces = [1, 2, 3, 4, 5, 6]
        let eval = DiceRollerEngine.evaluate(dice: faces, edition: .sr5)
        XCTAssertEqual(eval.hits, 2)
        XCTAssertEqual(eval.ones, 1)
    }

    func testEmptyPool() {
        let result = DiceRollerEngine.roll(pool: 0, edition: .sr5)
        XCTAssertEqual(result.hits, 0)
        XCTAssertTrue(result.dice.isEmpty)
        XCTAssertFalse(result.glitch)
    }

    // MARK: - Glitch thresholds

    func testSR5GlitchMoreThanHalfOnes() {
        // 3 dice, 2 ones → more than half → glitch
        XCTAssertTrue(DiceRollerEngine.isGlitch(ones: 2, diceCount: 3, edition: .sr5))
        // 4 dice, 2 ones → half, not more → no glitch (SR5 CRB)
        XCTAssertFalse(DiceRollerEngine.isGlitch(ones: 2, diceCount: 4, edition: .sr5))
        // 4 dice, 3 ones → glitch
        XCTAssertTrue(DiceRollerEngine.isGlitch(ones: 3, diceCount: 4, edition: .sr5))
    }

    func testSR4GlitchHalfOrMoreOnes() {
        XCTAssertTrue(DiceRollerEngine.isGlitch(ones: 2, diceCount: 4, edition: .sr4))
        XCTAssertFalse(DiceRollerEngine.isGlitch(ones: 1, diceCount: 3, edition: .sr4))
        XCTAssertTrue(DiceRollerEngine.isGlitch(ones: 2, diceCount: 3, edition: .sr4))
    }

    func testSR6UsesMoreThanHalfLikeSR5() {
        XCTAssertFalse(DiceRollerEngine.isGlitch(ones: 2, diceCount: 4, edition: .sr6))
        XCTAssertTrue(DiceRollerEngine.isGlitch(ones: 3, diceCount: 4, edition: .sr6))
    }

    func testCriticalGlitchIsGlitchWithZeroHits() {
        let eval = DiceRollerEngine.evaluate(dice: [1, 1, 1, 2], edition: .sr5)
        XCTAssertEqual(eval.hits, 0)
        XCTAssertTrue(eval.glitch)
        XCTAssertTrue(eval.criticalGlitch)
    }

    func testGlitchWithHitsIsNotCritical() {
        let eval = DiceRollerEngine.evaluate(dice: [1, 1, 1, 5], edition: .sr5)
        XCTAssertEqual(eval.hits, 1)
        XCTAssertTrue(eval.glitch)
        XCTAssertFalse(eval.criticalGlitch)
    }

    // MARK: - Rule of Six

    func testRuleOfSixAddsExtraDice() {
        var queue = [6, 3].makeIterator()
        let faces = DiceRollerEngine.expandPool(count: 1, options: .pushTheLimit) {
            queue.next() ?? 1
        }
        XCTAssertEqual(faces, [6, 3])
        XCTAssertEqual(DiceRollerEngine.evaluate(dice: faces, edition: .sr5).hits, 1)
    }

    func testWithoutRuleOfSixNoExplosion() {
        var queue = [6, 6, 6].makeIterator()
        let faces = DiceRollerEngine.expandPool(count: 1, options: .standard) {
            queue.next() ?? 1
        }
        XCTAssertEqual(faces, [6])
    }

    func testExplodedDiceCountTowardGlitch() {
        // Initial 2 dice: 1 and 6→explode to 1. Faces [1,6,1] → 2 ones of 3 → SR5 glitch
        var queue = [1, 6, 1].makeIterator()
        let faces = DiceRollerEngine.expandPool(count: 2, options: .pushTheLimit) {
            queue.next() ?? 1
        }
        XCTAssertEqual(faces, [1, 6, 1])
        let eval = DiceRollerEngine.evaluate(dice: faces, edition: .sr5)
        XCTAssertTrue(eval.glitch)
        XCTAssertEqual(eval.hits, 1)
        XCTAssertFalse(eval.criticalGlitch)
    }

    // MARK: - Second Chance

    func testSecondChanceRerollsNonHitsKeepsHits() {
        let previous = DiceResult(
            hits: 1,
            ones: 1,
            glitch: false,
            criticalGlitch: false,
            dice: [5, 1, 3],
            pool: 3,
            edition: .sr5
        )
        var queue = [6, 2].makeIterator()
        let next = DiceRollerEngine.secondChance(previous: previous) {
            queue.next() ?? 1
        }
        XCTAssertEqual(next.dice, [5, 6, 2])
        XCTAssertEqual(next.hits, 2)
        XCTAssertEqual(next.edgeMode, .secondChance)
        XCTAssertEqual(next.edgeSpent, 1)
    }

    func testPushTheLimitPoolAddsEdge() {
        XCTAssertEqual(DiceRollerEngine.pushTheLimitPool(basePool: 10, edgeRating: 3), 13)
        XCTAssertEqual(DiceRollerEngine.pushTheLimitPool(basePool: 0, edgeRating: 2), 2)
    }

    func testCopyTextIncludesEditionAndHits() {
        let r = DiceResult(
            hits: 3,
            ones: 0,
            glitch: false,
            criticalGlitch: false,
            dice: [5, 6, 5, 2],
            pool: 4,
            edition: .sr5,
            sourceLabel: "Pistols · pool 4"
        )
        let text = r.copyText
        XCTAssertTrue(text.contains("SR5"))
        XCTAssertTrue(text.contains("3 hits"))
        XCTAssertTrue(text.contains("Pistols"))
    }

    func testPoolResolverAttribute() {
        let c = SampleCharacters.sr5CombatMage()
        let (pool, label) = DicePoolResolver.attributePool(character: c, attribute: .logic)
        XCTAssertEqual(pool, c.effectiveAttributes.logic)
        XCTAssertTrue(label.contains("Logic"))
    }
}
