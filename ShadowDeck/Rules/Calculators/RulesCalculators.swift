//
//  RulesCalculators.swift
//  ShadowDeck
//
//  Pure quick-aid calculators for Rules Reference (karma, glitch, lifestyle,
//  condition monitors, SR5 limits). Drain / Overwatch live in sibling files.
//

import Foundation

// MARK: - Karma raise

public enum KarmaRaiseCalculator {
    /// Total karma to raise from `fromRating` to `toRating` (exclusive of from, inclusive of each step to to).
    /// Returns nil if range is invalid (to <= from, or from < 0).
    public static func cost(
        from fromRating: Int,
        to toRating: Int,
        category: SkillCategory,
        rules: any EditionRules,
        houseRules: HouseRules = .coreBook
    ) -> Int? {
        guard fromRating >= 0, toRating > fromRating else { return nil }
        var total = 0
        for current in fromRating..<toRating {
            total += rules.karmaCostToRaiseSkill(from: current, category: category)
        }
        return total
    }

    public static func attributeCost(
        from fromRating: Int,
        to toRating: Int,
        rules: any EditionRules,
        houseRules: HouseRules = .coreBook
    ) -> Int? {
        guard fromRating >= 1, toRating > fromRating else { return nil }
        var total = 0
        for current in fromRating..<toRating {
            total += rules.karmaCostToRaiseAttribute(from: current, houseRules: houseRules)
        }
        return total
    }

    /// Single step cost (current → current+1).
    public static func skillStepCost(
        current: Int,
        category: SkillCategory,
        rules: any EditionRules
    ) -> Int {
        rules.karmaCostToRaiseSkill(from: max(0, current), category: category)
    }

    public static func attributeStepCost(
        current: Int,
        rules: any EditionRules,
        houseRules: HouseRules = .coreBook
    ) -> Int {
        rules.karmaCostToRaiseAttribute(from: max(1, current), houseRules: houseRules)
    }
}

// MARK: - Glitch threshold

public enum GlitchThresholdCalculator {
    public struct Result: Sendable, Hashable {
        /// Minimum ones that trigger a glitch for this pool size.
        public var onesNeeded: Int
        public var mode: DiceGlitchThresholdMode
        public var pool: Int
        public var explanation: String

        public init(onesNeeded: Int, mode: DiceGlitchThresholdMode, pool: Int, explanation: String) {
            self.onesNeeded = onesNeeded
            self.mode = mode
            self.pool = pool
            self.explanation = explanation
        }
    }

    /// Minimum number of 1s that cause a glitch on a pool of `pool` dice.
    public static func evaluate(
        pool: Int,
        edition: Edition,
        diceRules: DiceHouseRules = .coreBook
    ) -> Result {
        let p = max(0, pool)
        let mode = diceRules.resolvedGlitchThreshold(for: edition)
        guard p > 0 else {
            return Result(
                onesNeeded: 0,
                mode: mode,
                pool: 0,
                explanation: "Empty pool — no glitch possible."
            )
        }
        let ones: Int
        let explanation: String
        switch mode {
        case .moreThanHalf:
            // ones * 2 > pool → ones > pool/2
            ones = (pool / 2) + 1
            explanation = "More than half ones: need \(ones)+ ones on \(pool) dice."
        case .halfOrMore, .editionDefault:
            // ones * 2 >= pool → ones >= ceil(pool/2)
            ones = (pool + 1) / 2
            explanation = "Half or more ones: need \(ones)+ ones on \(pool) dice."
        }
        // Sanity: first ones that isGlitch is true
        var verified = ones
        while verified > 0,
              !DiceRollerEngine.isGlitch(ones: verified, diceCount: p, edition: edition, diceRules: diceRules) {
            verified += 1
            if verified > p { break }
        }
        while verified > 1,
              DiceRollerEngine.isGlitch(ones: verified - 1, diceCount: p, edition: edition, diceRules: diceRules) {
            verified -= 1
        }
        return Result(
            onesNeeded: min(p, max(1, verified)),
            mode: mode == .editionDefault ? diceRules.resolvedGlitchThreshold(for: edition) : mode,
            pool: p,
            explanation: explanation
        )
    }

    public static func isGlitch(
        ones: Int,
        pool: Int,
        edition: Edition,
        diceRules: DiceHouseRules = .coreBook
    ) -> Bool {
        DiceRollerEngine.isGlitch(
            ones: ones,
            diceCount: max(0, pool),
            edition: edition,
            diceRules: diceRules
        )
    }
}

// MARK: - Lifestyle burn

public enum LifestyleBurnCalculator {
    public static func suggestedMonthlyCost(level: LifestyleLevel) -> Int {
        level.suggestedMonthlyCostSR5
    }

    public static func totalSuggested(levels: [LifestyleLevel]) -> Int {
        levels.reduce(0) { $0 + $1.suggestedMonthlyCostSR5 }
    }

    public static func totalCustom(costs: [Int]) -> Int {
        costs.reduce(0) { $0 + max(0, $1) }
    }
}

// MARK: - Condition monitors

public enum ConditionMonitorCalculator {
    public static func physicalBoxes(body: Int) -> Int {
        DerivedStatsCalculator.physicalBoxes(body: max(0, body))
    }

    public static func stunBoxes(willpower: Int) -> Int {
        DerivedStatsCalculator.stunBoxes(willpower: max(0, willpower))
    }
}

// MARK: - SR5 limits

public enum LimitsSR5Calculator {
    public struct Result: Sendable, Hashable {
        public var physical: Int
        public var mental: Int
        public var social: Int

        public init(physical: Int, mental: Int, social: Int) {
            self.physical = physical
            self.mental = mental
            self.social = social
        }
    }

    public static func evaluate(
        body: Int,
        reaction: Int,
        strength: Int,
        willpower: Int,
        logic: Int,
        intuition: Int,
        charisma: Int,
        essence: Decimal = 6
    ) -> Result {
        Result(
            physical: DerivedStatsCalculator.physicalLimit(
                strength: max(0, strength),
                body: max(0, body),
                reaction: max(0, reaction)
            ),
            mental: DerivedStatsCalculator.mentalLimit(
                logic: max(0, logic),
                intuition: max(0, intuition),
                willpower: max(0, willpower)
            ),
            social: DerivedStatsCalculator.socialLimit(
                charisma: max(0, charisma),
                willpower: max(0, willpower),
                essence: max(0, essence)
            )
        )
    }
}
