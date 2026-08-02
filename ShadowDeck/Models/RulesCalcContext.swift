//
//  RulesCalcContext.swift
//  ShadowDeck
//
//  Optional character snapshot for Rules Reference calculators (prefills only).
//

import Foundation

/// Values copied from an open character so calculators start from real sheet numbers.
public struct RulesCalcContext: Sendable, Equatable, Hashable {
    public var edition: Edition
    public var houseRules: HouseRules
    public var diceRules: DiceHouseRules

    public var body: Int
    public var agility: Int
    public var reaction: Int
    public var strength: Int
    public var willpower: Int
    public var logic: Int
    public var intuition: Int
    public var charisma: Int
    public var essence: Double
    public var magic: Int
    public var resonance: Int

    /// Highest active skill rating (for karma / glitch pool hints).
    public var sampleSkillRating: Int
    /// Sum of active lifestyle monthly costs.
    public var lifestyleMonthlyTotal: Int

    public init(
        edition: Edition = .sr5,
        houseRules: HouseRules = .coreBook,
        diceRules: DiceHouseRules = .coreBook,
        body: Int = 3,
        agility: Int = 3,
        reaction: Int = 3,
        strength: Int = 3,
        willpower: Int = 3,
        logic: Int = 3,
        intuition: Int = 3,
        charisma: Int = 3,
        essence: Double = 6,
        magic: Int = 0,
        resonance: Int = 0,
        sampleSkillRating: Int = 3,
        lifestyleMonthlyTotal: Int = 0
    ) {
        self.edition = edition
        self.houseRules = houseRules
        self.diceRules = diceRules
        self.body = max(1, body)
        self.agility = max(1, agility)
        self.reaction = max(1, reaction)
        self.strength = max(1, strength)
        self.willpower = max(1, willpower)
        self.logic = max(1, logic)
        self.intuition = max(1, intuition)
        self.charisma = max(1, charisma)
        self.essence = min(6, max(0, essence))
        self.magic = max(0, magic)
        self.resonance = max(0, resonance)
        self.sampleSkillRating = max(0, sampleSkillRating)
        self.lifestyleMonthlyTotal = max(0, lifestyleMonthlyTotal)
    }

    public static let neutral = RulesCalcContext()

    public static func from(character: Character) -> RulesCalcContext {
        let effects = CharacterEffectsEngine.resolve(character)
        let a = effects.effectiveAttributes
        let topSkill = character.skills.map(\.rating).max() ?? 3
        let life = character.lifestyles
            .filter(\.isActive)
            .reduce(0) { $0 + max(0, $1.monthlyCost) }
        let ess = NSDecimalNumber(decimal: a.essence).doubleValue
        return RulesCalcContext(
            edition: character.edition,
            houseRules: character.houseRules,
            diceRules: character.houseRules.dice ?? .coreBook,
            body: a.body,
            agility: a.agility,
            reaction: a.reaction,
            strength: a.strength,
            willpower: a.willpower,
            logic: a.logic,
            intuition: a.intuition,
            charisma: a.charisma,
            essence: ess > 0 ? min(6, ess) : 6,
            magic: a.magic,
            resonance: a.resonance,
            sampleSkillRating: topSkill,
            lifestyleMonthlyTotal: life
        )
    }
}
