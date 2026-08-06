//
//  DiceRollerEngine.swift
//  ShadowDeck
//
//  Pure edition-aware dice resolution (hits, glitches, Rule of Six, Second Chance).
//  House rules from `DiceHouseRules` adjust hit band, glitch math, and explosions.
//

import Foundation

public enum DiceRollerEngine {
    public static let dieFaces = 6

    // MARK: - Roll

    /// Roll `pool` d6 (after any pre-roll Edge dice have already been added to `pool`).
    public static func roll(
        pool: Int,
        edition: Edition,
        diceRules: DiceHouseRules = .coreBook,
        options: DiceRollOptions = .standard,
        edgeSpent: Int = 0,
        edgeMode: DiceEdgeMode = .none,
        modifier: Int = 0,
        sourceLabel: String? = nil,
        rng: inout some RandomNumberGenerator
    ) -> DiceResult {
        let basePool = max(0, pool)
        var opts = options
        // Always-on Rule of Six overrides edge-only options.
        if diceRules.ruleOfSix == .always {
            opts.ruleOfSix = true
        }
        let faces = rollDice(count: basePool, options: opts, rng: &rng)
        return makeResult(
            faces: faces,
            originalPool: basePool,
            pool: basePool,
            modifier: modifier,
            edition: edition,
            diceRules: diceRules,
            edgeSpent: edgeSpent,
            edgeMode: edgeMode,
            sourceLabel: sourceLabel
        )
    }

    public static func roll(
        pool: Int,
        edition: Edition,
        diceRules: DiceHouseRules = .coreBook,
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
            diceRules: diceRules,
            options: options,
            edgeSpent: edgeSpent,
            edgeMode: edgeMode,
            modifier: modifier,
            sourceLabel: sourceLabel,
            rng: &rng
        )
    }

    // MARK: - Evaluate (pure)

    public static func evaluate(
        dice: [Int],
        edition: Edition,
        diceRules: DiceHouseRules = .coreBook,
        originalPool: Int? = nil
    ) -> (hits: Int, ones: Int, glitch: Bool, criticalGlitch: Bool) {
        let hitMin = diceRules.hitMinimum
        let hits = dice.reduce(0) { $0 + (isHit($1, minimum: hitMin) ? 1 : 0) }
        let ones = dice.reduce(0) { $0 + ($1 == 1 ? 1 : 0) }
        let diceCountForGlitch: Int
        if diceRules.countExplodedDiceForGlitch {
            diceCountForGlitch = dice.count
        } else {
            diceCountForGlitch = max(0, originalPool ?? dice.count)
        }
        let glitch = isGlitch(
            ones: ones,
            diceCount: diceCountForGlitch,
            edition: edition,
            diceRules: diceRules
        )
        let critical = glitch && hits == 0
        return (hits, ones, glitch, critical)
    }

    public static func isHit(_ face: Int, minimum: Int = 5) -> Bool {
        face >= minimum
    }

    public static func isGlitch(
        ones: Int,
        diceCount: Int,
        edition: Edition,
        diceRules: DiceHouseRules = .coreBook
    ) -> Bool {
        guard diceCount > 0, ones > 0 else { return false }
        switch diceRules.resolvedGlitchThreshold(for: edition) {
        case .halfOrMore, .editionDefault:
            // editionDefault is resolved above; keep halfOrMore math here.
            // half or more: ones * 2 >= diceCount
            return ones * 2 >= diceCount
        case .moreThanHalf:
            // ones * 2 > diceCount
            return ones * 2 > diceCount
        }
    }

    // MARK: - Second Chance

    /// Re-roll every non-hit; keep existing hits. Rule of Six does not apply to Second Chance re-rolls in v1.
    public static func secondChance(
        previous: DiceResult,
        diceRules: DiceHouseRules = .coreBook,
        rng: inout some RandomNumberGenerator
    ) -> DiceResult {
        let hitMin = diceRules.hitMinimum
        var newFaces: [Int] = []
        newFaces.reserveCapacity(previous.dice.count)
        for face in previous.dice {
            if isHit(face, minimum: hitMin) {
                newFaces.append(face)
            } else {
                newFaces.append(Int.random(in: 1...dieFaces, using: &rng))
            }
        }
        return makeResult(
            faces: newFaces,
            originalPool: previous.pool,
            pool: previous.pool,
            modifier: previous.modifier,
            edition: previous.edition,
            diceRules: diceRules,
            edgeSpent: previous.edgeSpent + 1,
            edgeMode: .secondChance,
            sourceLabel: previous.sourceLabel
        )
    }

    public static func secondChance(
        previous: DiceResult,
        diceRules: DiceHouseRules = .coreBook
    ) -> DiceResult {
        var rng = SystemRandomNumberGenerator()
        return secondChance(previous: previous, diceRules: diceRules, rng: &rng)
    }

    /// Second Chance using a predetermined re-roll sequence for non-hits (tests).
    public static func secondChance(
        previous: DiceResult,
        diceRules: DiceHouseRules = .coreBook,
        nextReroll: () -> Int
    ) -> DiceResult {
        let hitMin = diceRules.hitMinimum
        var newFaces: [Int] = []
        newFaces.reserveCapacity(previous.dice.count)
        for face in previous.dice {
            if isHit(face, minimum: hitMin) {
                newFaces.append(face)
            } else {
                newFaces.append(min(dieFaces, max(1, nextReroll())))
            }
        }
        return makeResult(
            faces: newFaces,
            originalPool: previous.pool,
            pool: previous.pool,
            modifier: previous.modifier,
            edition: previous.edition,
            diceRules: diceRules,
            edgeSpent: previous.edgeSpent + 1,
            edgeMode: .secondChance,
            sourceLabel: previous.sourceLabel
        )
    }

    // MARK: - SR6 Edge Actions (post-roll)

    /// Spend 1 Edge to add one automatic hit (does not change faces).
    public static func buyHit(previous: DiceResult, diceRules: DiceHouseRules = .coreBook) -> DiceResult {
        var next = previous
        next.id = UUID()
        next.hits = previous.hits + 1
        next.edgeSpent = previous.edgeSpent + 1
        next.edgeMode = .buyHit
        next.timestamp = Date()
        // Buying a hit after a critical glitch: still a glitch unless Close Call is used.
        // Critical glitch requires 0 hits — if we now have hits, drop critical flag.
        if next.hits > 0 {
            next.criticalGlitch = false
        }
        return next
    }

    /// Spend 1 Edge to clear glitch / critical glitch while keeping hits and faces.
    public static func closeCall(previous: DiceResult) -> DiceResult? {
        guard previous.glitch || previous.criticalGlitch else { return nil }
        var next = previous
        next.id = UUID()
        next.glitch = false
        next.criticalGlitch = false
        next.edgeSpent = previous.edgeSpent + 1
        next.edgeMode = .closeCall
        next.timestamp = Date()
        return next
    }

    // MARK: - Push the Limit helpers

    /// Pool size when spending Edge pre-roll: base pool + Edge rating.
    /// SR6 full mode uses the same math as “Add Edge Dice”.
    public static func pushTheLimitPool(basePool: Int, edgeRating: Int) -> Int {
        max(0, basePool) + max(0, edgeRating)
    }

    public static func addEdgeDicePool(basePool: Int, edgeRating: Int) -> Int {
        pushTheLimitPool(basePool: basePool, edgeRating: edgeRating)
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

    private static func makeResult(
        faces: [Int],
        originalPool: Int,
        pool: Int,
        modifier: Int,
        edition: Edition,
        diceRules: DiceHouseRules,
        edgeSpent: Int,
        edgeMode: DiceEdgeMode,
        sourceLabel: String?
    ) -> DiceResult {
        let eval = evaluate(
            dice: faces,
            edition: edition,
            diceRules: diceRules,
            originalPool: originalPool
        )
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
