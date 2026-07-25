//
//  DerivedStatsCalculator.swift
//  ShadowDeck
//
//  Shared derived-stat math used by edition strategies.
//

import Foundation

public enum DerivedStatsCalculator {
    /// Physical condition monitor boxes: 8 + ceil(Body/2) — used by SR4/SR5; SR6 similar baseline.
    public static func physicalBoxes(body: Int) -> Int {
        8 + Int(ceil(Double(body) / 2.0))
    }

    /// Stun condition monitor boxes: 8 + ceil(Willpower/2).
    public static func stunBoxes(willpower: Int) -> Int {
        8 + Int(ceil(Double(willpower) / 2.0))
    }

    /// SR5 Physical Limit: ceil((STR*2 + BOD + REA)/3)
    public static func physicalLimit(strength: Int, body: Int, reaction: Int) -> Int {
        Int(ceil(Double(strength * 2 + body + reaction) / 3.0))
    }

    /// SR5 Mental Limit: ceil((LOG*2 + INT + WIL)/3)
    public static func mentalLimit(logic: Int, intuition: Int, willpower: Int) -> Int {
        Int(ceil(Double(logic * 2 + intuition + willpower) / 3.0))
    }

    /// SR5 Social Limit: ceil((CHA*2 + WIL + ESS)/3) — ESS as integer floor for limit math.
    public static func socialLimit(charisma: Int, willpower: Int, essence: Decimal) -> Int {
        let ess = NSDecimalNumber(decimal: essence).doubleValue
        return Int(ceil((Double(charisma * 2 + willpower) + ess) / 3.0))
    }

    public static func composure(charisma: Int, willpower: Int) -> Int {
        charisma + willpower
    }

    public static func judgeIntentions(charisma: Int, intuition: Int) -> Int {
        charisma + intuition
    }

    public static func memory(logic: Int, willpower: Int) -> Int {
        logic + willpower
    }

    public static func initiativeBase(reaction: Int, intuition: Int) -> Int {
        reaction + intuition
    }

    public static func equippedArmor(from gear: [GearItem]) -> Int {
        gear.filter(\.equipped).compactMap(\.armorRating).max() ?? 0
    }

    public static func totalEssenceCost(augmentations: [Augmentation], houseRules: HouseRules) -> Decimal {
        var total: Decimal = 0
        for aug in augmentations {
            var cost = aug.essenceCost
            if houseRules.isEnabled(.essenceCostRounding) {
                cost = roundDown(cost, step: houseRules.essenceRoundingStep)
            }
            total += cost
        }
        return total
    }

    public static func roundDown(_ value: Decimal, step: Decimal) -> Decimal {
        guard step > 0 else { return value }
        let units = (value / step) as Decimal
        let floored = Decimal(NSDecimalNumber(decimal: units).intValue)
        return floored * step
    }

    public static func dicePool(attribute: Int, skill: Int) -> Int {
        attribute + skill
    }
}
