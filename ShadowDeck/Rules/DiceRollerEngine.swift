//
//  DiceRollerEngine.swift
//  ShadowDeck
//
//  Pure edition-aware dice resolution (hits, glitches, Rule of Six, Second Chance).
//

import Foundation

public enum DiceRollerEngine {
    public static let hitThreshold = 5
    public static let dieFaces = 6

    // MARK: - Roll

    /// Roll `pool` d6 (after any pre-roll Edge dice have already been added to `pool`).
    public static func roll(
        pool: Int,
        edition: Edition,
        options: DiceRollOptions = .standard,
        edgeSpent: Int = 0,
        edgeMode: DiceEdgeMode = .none,
        modifier: Int = 0,
        sourceLabel: String? = nil,
        rng: inout some RandomNumberGenerator
    ) -> DiceResult {
        let basePool = max(0, pool)
        let faces = rollDice(count: basePool, options: options, rng: &rng)
        return makeResult(
            faces: faces,
            pool: basePool,
            modifier: modifier,
            edition: edition,
            edgeSpent: edgeSpent,
            edgeMode: edgeMode,
            sourceLabel: sourceLabel
        )
    }

    public static func roll(
        pool: Int,
        edition: Edition,
        options: DiceRollOptions = .standard,
        edgeSpent: Int = 0,
        edgeMode: DiceEdgeMode = .none,
        modifier: Int = 0,
        sourceLabel: String? = nil
    ) -> DiceResult {
        var rng = SystemRandomNumberGenerator()
        return roll(
            pool: pool,
            edition: edition,
            options: options,
            edgeSpent: edgeSpent,
            edgeMode: edgeMode,
            modifier: modifier,
            sourceLabel: sourceLabel,
            rng: &rng
        )
    }

    // MARK: - Evaluate (pure)

    public static func evaluate(dice: [Int], edition: Edition) -> (hits: Int, ones: Int, glitch: Bool, criticalGlitch: Bool) {
        let hits = dice.reduce(0) { $0 + (isHit($1) ? 1 : 0) }
        let ones = dice.reduce(0) { $0 + ($1 == 1 ? 1 : 0) }
        let glitch = isGlitch(ones: ones, diceCount: dice.count, edition: edition)
        let critical = glitch && hits == 0
        return (hits, ones, glitch, critical)
    }

    public static func isHit(_ face: Int) -> Bool {
        face >= hitThreshold
    }

    /// SR5 / SR6 (v1): more than half ones. SR4: half or more ones.
    public static func isGlitch(ones: Int, diceCount: Int, edition: Edition) -> Bool {
        guard diceCount > 0, ones > 0 else { return false }
        switch edition {
        case .sr4:
            // SR4A-style: half or more of the dice are 1s.
            return ones * 2 >= diceCount
        case .sr5, .sr6:
            // SR5 CRB: more than half the dice show a one.
            return ones * 2 > diceCount
        }
    }

    // MARK: - Second Chance

    /// Re-roll every non-hit; keep existing hits. Rule of Six does not apply to Second Chance re-rolls in v1.
    public static func secondChance(
        previous: DiceResult,
        rng: inout some RandomNumberGenerator
    ) -> DiceResult {
        var newFaces: [Int] = []
        newFaces.reserveCapacity(previous.dice.count)
        for face in previous.dice {
            if isHit(face) {
                newFaces.append(face)
            } else {
                newFaces.append(Int.random(in: 1...dieFaces, using: &rng))
            }
        }
        return makeResult(
            faces: newFaces,
            pool: previous.pool,
            modifier: previous.modifier,
            edition: previous.edition,
            edgeSpent: previous.edgeSpent + 1,
            edgeMode: .secondChance,
            sourceLabel: previous.sourceLabel
        )
    }

    public static func secondChance(previous: DiceResult) -> DiceResult {
        var rng = SystemRandomNumberGenerator()
        return secondChance(previous: previous, rng: &rng)
    }

    // MARK: - Push the Limit helpers

    /// Pool size when spending Edge pre-roll: base pool + Edge rating.
    public static func pushTheLimitPool(basePool: Int, edgeRating: Int) -> Int {
        max(0, basePool) + max(0, edgeRating)
    }

    // MARK: - Internals

    private static func rollDice(
        count: Int,
        options: DiceRollOptions,
        rng: inout some RandomNumberGenerator
    ) -> [Int] {
        expandPool(count: count, options: options) {
            Int.random(in: 1...dieFaces, using: &rng)
        }
    }

    /// Expand an initial pool with optional Rule of Six. `nextFace` supplies each d6 (clamped 1…6).
    /// Exposed for deterministic tests.
    public static func expandPool(
        count: Int,
        options: DiceRollOptions = .standard,
        nextFace: () -> Int
    ) -> [Int] {
        guard count > 0 else { return [] }
        var faces: [Int] = []
        faces.reserveCapacity(count)
        var pending = count
        var explosions = 0
        while pending > 0 {
            let face = min(dieFaces, max(1, nextFace()))
            faces.append(face)
            pending -= 1
            if options.ruleOfSix, face == dieFaces, explosions < options.maxExplosions {
                pending += 1
                explosions += 1
            }
        }
        return faces
    }

    /// Second Chance using a predetermined re-roll sequence for non-hits (tests).
    public static func secondChance(
        previous: DiceResult,
        nextReroll: () -> Int
    ) -> DiceResult {
        var newFaces: [Int] = []
        newFaces.reserveCapacity(previous.dice.count)
        for face in previous.dice {
            if isHit(face) {
                newFaces.append(face)
            } else {
                newFaces.append(min(dieFaces, max(1, nextReroll())))
            }
        }
        return makeResult(
            faces: newFaces,
            pool: previous.pool,
            modifier: previous.modifier,
            edition: previous.edition,
            edgeSpent: previous.edgeSpent + 1,
            edgeMode: .secondChance,
            sourceLabel: previous.sourceLabel
        )
    }

    private static func makeResult(
        faces: [Int],
        pool: Int,
        modifier: Int,
        edition: Edition,
        edgeSpent: Int,
        edgeMode: DiceEdgeMode,
        sourceLabel: String?
    ) -> DiceResult {
        let eval = evaluate(dice: faces, edition: edition)
        return DiceResult(
            hits: eval.hits,
            ones: eval.ones,
            glitch: eval.glitch,
            criticalGlitch: eval.criticalGlitch,
            dice: faces,
            pool: pool,
            modifier: modifier,
            edition: edition,
            edgeSpent: edgeSpent,
            edgeMode: edgeMode,
            sourceLabel: sourceLabel
        )
    }
}
