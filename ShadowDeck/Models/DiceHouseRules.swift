//
//  DiceHouseRules.swift
//  ShadowDeck
//
//  Dice-test house rules applied by the in-app roller (and future resolution UI).
//

import Foundation

// MARK: - Modes

public enum DiceGlitchThresholdMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    /// SR4 → halfOrMore; SR5/SR6 → moreThanHalf.
    case editionDefault
    /// ones > diceCount/2 (SR5 CRB-style).
    case moreThanHalf
    /// ones >= diceCount/2 (SR4A-style / common house rule).
    case halfOrMore

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .editionDefault: "Edition default"
        case .moreThanHalf: "More than half ones"
        case .halfOrMore: "Half or more ones"
        }
    }

    public var summary: String {
        switch self {
        case .editionDefault:
            "SR4 uses half-or-more; SR5/SR6 use more-than-half."
        case .moreThanHalf:
            "Glitch when ones > half the dice checked (SR5 core)."
        case .halfOrMore:
            "Glitch when ones ≥ half the dice checked (SR4 / common table)."
        }
    }
}

public enum DiceRuleOfSixMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    /// Exploding 6s only when spending Edge (Push the Limit).
    case edgeOnly
    /// Every 6 explodes on every test.
    case always

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .edgeOnly: "Edge only (default)"
        case .always: "Always on"
        }
    }

    public var summary: String {
        switch self {
        case .edgeOnly:
            "Rule of Six only when Push the Limit spends Edge."
        case .always:
            "Every 6 explodes on every roll; Push the Limit still adds Edge dice."
        }
    }
}

// MARK: - Bundle

/// Dice-resolution house rules. Stored on `HouseRules.dice`.
public struct DiceHouseRules: Codable, Sendable, Hashable {
    public var glitchThreshold: DiceGlitchThresholdMode
    public var ruleOfSix: DiceRuleOfSixMode
    /// When false, only the original (pre-explosion) pool size is used for glitch checks.
    public var countExplodedDiceForGlitch: Bool
    /// When true, hits on 4–6 instead of 5–6. Ones still glitch.
    public var hitsOn4: Bool
    /// SR6: treat Edge like SR5 Push / Second Chance (already the app default).
    public var simplifiedSR6Edge: Bool

    public init(
        glitchThreshold: DiceGlitchThresholdMode = .editionDefault,
        ruleOfSix: DiceRuleOfSixMode = .edgeOnly,
        countExplodedDiceForGlitch: Bool = true,
        hitsOn4: Bool = false,
        simplifiedSR6Edge: Bool = true
    ) {
        self.glitchThreshold = glitchThreshold
        self.ruleOfSix = ruleOfSix
        self.countExplodedDiceForGlitch = countExplodedDiceForGlitch
        self.hitsOn4 = hitsOn4
        self.simplifiedSR6Edge = simplifiedSR6Edge
    }

    /// Strict core-book dice defaults (edition still chooses glitch mode via `.editionDefault`).
    public static let coreBook = Self()

    /// Popular table: half-or-more glitches, count exploded dice.
    public static let popularTable = Self(
        glitchThreshold: .halfOrMore,
        ruleOfSix: .edgeOnly,
        countExplodedDiceForGlitch: true,
        hitsOn4: false,
        simplifiedSR6Edge: true
    )

    /// Resolve glitch mode for a concrete edition.
    public func resolvedGlitchThreshold(for edition: Edition) -> DiceGlitchThresholdMode {
        switch glitchThreshold {
        case .editionDefault:
            switch edition {
            case .sr4: return .halfOrMore
            case .sr5, .sr6: return .moreThanHalf
            }
        case .moreThanHalf, .halfOrMore:
            return glitchThreshold
        }
    }

    /// Whether Rule of Six applies for this roll.
    public func ruleOfSixEnabled(pushingTheLimit: Bool) -> Bool {
        switch ruleOfSix {
        case .always: return true
        case .edgeOnly: return pushingTheLimit
        }
    }

    public var hitMinimum: Int { hitsOn4 ? 4 : 5 }

    public var isNonDefault: Bool {
        glitchThreshold != .editionDefault
            || ruleOfSix != .edgeOnly
            || countExplodedDiceForGlitch != true
            || hitsOn4
            || simplifiedSR6Edge != true
    }

    /// Non-default overrides shown in the roller chrome (edition default glitch is resolved separately).
    public var activeSummaryLines: [String] {
        var lines: [String] = []
        if glitchThreshold != .editionDefault {
            lines.append(glitchThreshold.displayName)
        }
        if ruleOfSix == .always {
            lines.append("Rule of Six always on")
        }
        if !countExplodedDiceForGlitch {
            lines.append("Exploded dice ignored for glitch")
        }
        if hitsOn4 {
            lines.append("Hits on 4+")
        }
        // simplifiedSR6Edge defaults true (matches the roller’s Edge model); omit from banner noise.
        if !simplifiedSR6Edge {
            lines.append("Full SR6 Edge (unsupported in v1 roller)")
        }
        return lines
    }
}
