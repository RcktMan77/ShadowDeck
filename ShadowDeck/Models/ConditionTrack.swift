//
//  ConditionTrack.swift
//  ShadowDeck
//
//  Play-state damage on physical / stun condition monitors.
//

import Foundation

/// Current damage taken on condition monitors (filled boxes).
/// Stored separately from derived box *capacity* (Body/Willpower).
public struct ConditionTrack: Codable, Sendable, Hashable {
    public var physicalDamage: Int
    public var stunDamage: Int

    public init(physicalDamage: Int = 0, stunDamage: Int = 0) {
        self.physicalDamage = max(0, physicalDamage)
        self.stunDamage = max(0, stunDamage)
    }

    public mutating func setPhysicalDamage(_ value: Int, maxBoxes: Int) {
        physicalDamage = min(max(0, value), max(0, maxBoxes))
    }

    public mutating func setStunDamage(_ value: Int, maxBoxes: Int) {
        stunDamage = min(max(0, value), max(0, maxBoxes))
    }
}
