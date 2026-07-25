//
//  DerivedStats.swift
//  ShadowDeck
//
//  Calculated fields produced by the edition rules engine.
//

import Foundation

public struct ConditionMonitor: Codable, Sendable, Hashable {
    public var physicalBoxes: Int
    public var stunBoxes: Int
    public var physicalFilled: Int
    public var stunFilled: Int
    public var overflowBoxes: Int

    public init(
        physicalBoxes: Int,
        stunBoxes: Int,
        physicalFilled: Int = 0,
        stunFilled: Int = 0,
        overflowBoxes: Int = 0
    ) {
        self.physicalBoxes = physicalBoxes
        self.stunBoxes = stunBoxes
        self.physicalFilled = physicalFilled
        self.stunFilled = stunFilled
        self.overflowBoxes = overflowBoxes
    }

    public var physicalRemaining: Int { max(0, physicalBoxes - physicalFilled) }
    public var stunRemaining: Int { max(0, stunBoxes - stunFilled) }
}

/// Edition-aware derived values (limits, initiative, pools placeholders).
public struct DerivedStats: Codable, Sendable, Hashable {
    public var initiativeDice: Int
    public var initiativeBase: Int
    public var composure: Int
    public var judgeIntentions: Int
    public var memory: Int
    public var liftCarry: Int
    public var movementWalk: Int
    public var movementRun: Int

    /// SR5-style limits; nil when edition does not use them.
    public var physicalLimit: Int?
    public var mentalLimit: Int?
    public var socialLimit: Int?

    public var condition: ConditionMonitor
    public var currentEssence: Decimal
    public var magicOrResonanceEffective: Int
    public var armor: Int

    /// Placeholder dice pools for key checks (skill key → pool). Filled by rules as data grows.
    public var dicePools: [String: Int]

    public init(
        initiativeDice: Int = 1,
        initiativeBase: Int = 0,
        composure: Int = 0,
        judgeIntentions: Int = 0,
        memory: Int = 0,
        liftCarry: Int = 0,
        movementWalk: Int = 0,
        movementRun: Int = 0,
        physicalLimit: Int? = nil,
        mentalLimit: Int? = nil,
        socialLimit: Int? = nil,
        condition: ConditionMonitor = ConditionMonitor(physicalBoxes: 9, stunBoxes: 9),
        currentEssence: Decimal = 6,
        magicOrResonanceEffective: Int = 0,
        armor: Int = 0,
        dicePools: [String: Int] = [:]
    ) {
        self.initiativeDice = initiativeDice
        self.initiativeBase = initiativeBase
        self.composure = composure
        self.judgeIntentions = judgeIntentions
        self.memory = memory
        self.liftCarry = liftCarry
        self.movementWalk = movementWalk
        self.movementRun = movementRun
        self.physicalLimit = physicalLimit
        self.mentalLimit = mentalLimit
        self.socialLimit = socialLimit
        self.condition = condition
        self.currentEssence = currentEssence
        self.magicOrResonanceEffective = magicOrResonanceEffective
        self.armor = armor
        self.dicePools = dicePools
    }
}
