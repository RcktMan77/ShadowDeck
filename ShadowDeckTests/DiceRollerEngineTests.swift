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

    func testHitsOn4HouseRule() {
        let faces = [1, 2, 3, 4, 5, 6]
        let rules = DiceHouseRules(hitsOn4: true)
        let eval = DiceRollerEngine.evaluate(dice: faces, edition: .sr5, diceRules: rules)
        XCTAssertEqual(eval.hits, 3) // 4, 5, 6
    }

    func testIgnoreExplodedDiceForGlitch() {
        // Faces include explosion: original pool 2, faces [1, 6, 1]
        let faces = [1, 6, 1]
        let countAll = DiceHouseRules(countExplodedDiceForGlitch: true)
        let ignoreExtra = DiceHouseRules(countExplodedDiceForGlitch: false)
        // 2 ones of 3 → more than half → glitch when counting all
        let withAll = DiceRollerEngine.evaluate(
            dice: faces, edition: .sr5, diceRules: countAll, originalPool: 2
        )
        XCTAssertTrue(withAll.glitch)
        // Only original pool 2: 2 ones of 2 → more than half? 2*2 > 2 → yes still glitch
        // Use faces [1, 6, 5] — 1 one of 3 if count all, no glitch; original pool 2 with 1 one → no glitch either
        let faces2 = [1, 6, 5]
        let a = DiceRollerEngine.evaluate(dice: faces2, edition: .sr5, diceRules: countAll, originalPool: 2)
        let b = DiceRollerEngine.evaluate(dice: faces2, edition: .sr5, diceRules: ignoreExtra, originalPool: 2)
        XCTAssertFalse(a.glitch) // 1 of 3
        XCTAssertFalse(b.glitch) // 1 of 2
        // [1,1,6,1] original 2: count all 3 ones of 4 → glitch; ignore → ones still 3 but count 2 → glitch half
        // Better: original 4 dice, explosions add 2 ones making 6 dice with 3 ones (half, SR5 no glitch)
        // original 4, faces [1,1,2,3,1,1] if explosions... simpler:
        // originalPool 4, faces count 6 with 4 ones → more than half of 6 (4>3) glitch if count all
        // if ignore: 4 ones vs original 4 → half, SR5 moreThanHalf → 4*2>4 → glitch still
        // original 6, faces 8 with 4 ones: 4>4 false no glitch all; original 6: 4*2>6 → glitch ignore
        let faces3 = [1, 1, 1, 1, 2, 3, 5, 6] // 4 ones, 8 dice
        let all = DiceRollerEngine.evaluate(
            dice: faces3, edition: .sr5, diceRules: countAll, originalPool: 6
        )
        let ign = DiceRollerEngine.evaluate(
            dice: faces3, edition: .sr5, diceRules: ignoreExtra, originalPool: 6
        )
        // 4 ones / 8 dice: 8 > 8 false → no glitch when counting all
        XCTAssertFalse(all.glitch)
        // 4 ones / 6 original: 8 > 6 true → glitch when ignoring explosions
        XCTAssertTrue(ign.glitch)
    }

    func testGlitchThresholdOverrideHalfOrMoreOnSR5() {
        // 4 dice, 2 ones: edition default moreThanHalf → no; house halfOrMore → yes
        XCTAssertFalse(DiceRollerEngine.isGlitch(ones: 2, diceCount: 4, edition: .sr5))
        let rules = DiceHouseRules(glitchThreshold: .halfOrMore)
        XCTAssertTrue(DiceRollerEngine.isGlitch(ones: 2, diceCount: 4, edition: .sr5, diceRules: rules))
    }

    func testRuleOfSixAlwaysFromHouseRules() {
        let rules = DiceHouseRules(ruleOfSix: .always)
        XCTAssertTrue(rules.ruleOfSixEnabled(pushingTheLimit: false))
        XCTAssertTrue(rules.ruleOfSixEnabled(pushingTheLimit: true))
        let edgeOnly = DiceHouseRules(ruleOfSix: .edgeOnly)
        XCTAssertFalse(edgeOnly.ruleOfSixEnabled(pushingTheLimit: false))
        XCTAssertTrue(edgeOnly.ruleOfSixEnabled(pushingTheLimit: true))
    }

    func testLegacyHouseRulesDecodeWithoutDice() throws {
        // Encode core book, drop the optional `dice` key, re-decode (legacy payloads).
        let encoder = PortableCharacterCoding.encoder()
        var obj = try JSONSerialization.jsonObject(
            with: encoder.encode(HouseRules.coreBook)
        ) as! [String: Any]
        obj.removeValue(forKey: "dice")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let rules = try PortableCharacterCoding.decoder().decode(HouseRules.self, from: data)
        XCTAssertNil(rules.dice)
        XCTAssertEqual(rules.resolvedDice.glitchThreshold, .editionDefault)
        XCTAssertEqual(rules.resolvedDice.ruleOfSix, .edgeOnly)
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
        XCTAssertEqual(DiceRollerEngine.addEdgeDicePool(basePool: 10, edgeRating: 3), 13)
    }

    // MARK: - SR6 Edge Actions

    func testBuyHitAddsOneHitAndSpendsEdge() {
        let previous = DiceResult(
            hits: 2,
            ones: 0,
            glitch: false,
            criticalGlitch: false,
            dice: [5, 6, 2],
            pool: 3,
            edition: .sr6,
            edgeSpent: 0
        )
        let next = DiceRollerEngine.buyHit(previous: previous)
        XCTAssertEqual(next.hits, 3)
        XCTAssertEqual(next.dice, previous.dice)
        XCTAssertEqual(next.edgeMode, .buyHit)
        XCTAssertEqual(next.edgeSpent, 1)
    }

    func testCloseCallClearsGlitch() {
        let previous = DiceResult(
            hits: 1,
            ones: 2,
            glitch: true,
            criticalGlitch: false,
            dice: [5, 1, 1],
            pool: 3,
            edition: .sr6
        )
        let next = DiceRollerEngine.closeCall(previous: previous)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.hits, 1)
        XCTAssertFalse(next?.glitch ?? true)
        XCTAssertEqual(next?.edgeMode, .closeCall)
        XCTAssertEqual(next?.edgeSpent, 1)
        XCTAssertNil(DiceRollerEngine.closeCall(previous: DiceResult(
            hits: 2,
            ones: 0,
            glitch: false,
            criticalGlitch: false,
            dice: [5, 6],
            pool: 2,
            edition: .sr6
        )))
    }

    func testFullSR6EdgeIsDefaultAndSimplifiedIsHouseRule() {
        XCTAssertFalse(DiceHouseRules.coreBook.simplifiedSR6Edge)
        XCTAssertTrue(DiceHouseRules.coreBook.usesFullSR6EdgeActions(for: .sr6))
        XCTAssertFalse(DiceHouseRules.coreBook.usesFullSR6EdgeActions(for: .sr5))
        let simplified = DiceHouseRules(simplifiedSR6Edge: true)
        XCTAssertFalse(simplified.usesFullSR6EdgeActions(for: .sr6))
        XCTAssertTrue(simplified.isNonDefault)
        XCTAssertEqual(
            DiceEdgeMode.pushTheLimit.displayName(edition: .sr6, fullSR6Edge: true),
            "Add Edge Dice"
        )
        XCTAssertEqual(
            DiceEdgeMode.secondChance.displayName(edition: .sr6, fullSR6Edge: true),
            "Reroll Failures"
        )
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
