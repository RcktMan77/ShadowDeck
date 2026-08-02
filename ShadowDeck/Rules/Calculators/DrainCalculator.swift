//
//  DrainCalculator.swift
//  ShadowDeck
//
//  Quick-aid Drain DV math. Simplified original model — not a full spell database.
//  Label UI: “Quick aid — see your book for the full procedure.”
//

import Foundation

/// Common drain code shapes used at the table (Force-based).
public enum DrainCodeTemplate: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case halfForce
    case halfForcePlus1
    case halfForcePlus2
    case halfForcePlus3
    case halfForcePlus4
    case halfForceMinus1
    case forceMinus3
    case forceMinus2
    case forceMinus1
    case force
    case forcePlus1
    case forcePlus2

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .halfForce: "F/2"
        case .halfForcePlus1: "F/2 + 1"
        case .halfForcePlus2: "F/2 + 2"
        case .halfForcePlus3: "F/2 + 3"
        case .halfForcePlus4: "F/2 + 4"
        case .halfForceMinus1: "F/2 − 1"
        case .forceMinus3: "F − 3"
        case .forceMinus2: "F − 2"
        case .forceMinus1: "F − 1"
        case .force: "F"
        case .forcePlus1: "F + 1"
        case .forcePlus2: "F + 2"
        }
    }

    public var summary: String {
        "Drain value from Force using \(displayName) (half Force rounds up)."
    }
}

public enum DrainDamageType: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case stun
    case physical

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public struct DrainCalculatorResult: Sendable, Hashable {
    public var force: Int
    public var code: DrainCodeTemplate
    public var drainValue: Int
    public var damageType: DrainDamageType
    public var resistPoolHint: Int?
    public var note: String

    public init(
        force: Int,
        code: DrainCodeTemplate,
        drainValue: Int,
        damageType: DrainDamageType,
        resistPoolHint: Int?,
        note: String
    ) {
        self.force = force
        self.code = code
        self.drainValue = drainValue
        self.damageType = damageType
        self.resistPoolHint = resistPoolHint
        self.note = note
    }
}

public enum DrainCalculator {
    /// Half Force rounded **up** (common SR5-style F/2).
    public static func halfForceRoundedUp(_ force: Int) -> Int {
        let f = max(0, force)
        return (f + 1) / 2
    }

    public static func drainValue(force: Int, code: DrainCodeTemplate) -> Int {
        let f = max(0, force)
        let half = halfForceRoundedUp(f)
        let raw: Int
        switch code {
        case .halfForce: raw = half
        case .halfForcePlus1: raw = half + 1
        case .halfForcePlus2: raw = half + 2
        case .halfForcePlus3: raw = half + 3
        case .halfForcePlus4: raw = half + 4
        case .halfForceMinus1: raw = half - 1
        case .forceMinus3: raw = f - 3
        case .forceMinus2: raw = f - 2
        case .forceMinus1: raw = f - 1
        case .force: raw = f
        case .forcePlus1: raw = f + 1
        case .forcePlus2: raw = f + 2
        }
        return max(0, raw)
    }

    /// Resist pool hint: Willpower + tradition attribute (user-supplied).
    public static func resistPool(willpower: Int, traditionAttribute: Int) -> Int {
        max(0, willpower) + max(0, traditionAttribute)
    }

    public static func evaluate(
        force: Int,
        code: DrainCodeTemplate,
        damageType: DrainDamageType = .stun,
        willpower: Int? = nil,
        traditionAttribute: Int? = nil
    ) -> DrainCalculatorResult {
        let dv = drainValue(force: force, code: code)
        var resist: Int?
        if let w = willpower, let t = traditionAttribute {
            resist = resistPool(willpower: w, traditionAttribute: t)
        }
        return DrainCalculatorResult(
            force: max(0, force),
            code: code,
            drainValue: dv,
            damageType: damageType,
            resistPoolHint: resist,
            note: "Quick aid — see your book for the full procedure (tradition, reagents, overcasting, etc.)."
        )
    }
}
