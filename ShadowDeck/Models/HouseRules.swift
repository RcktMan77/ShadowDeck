//
//  HouseRules.swift
//  ShadowDeck
//
//  Popular table toggles. Core-book play = HouseRules.coreBook.
//  Enabled early so generation and validation stay data-driven.
//

import Foundation

/// Identifiers for well-known house rules (top community favorites).
public enum HouseRuleID: String, Codable, Sendable, CaseIterable, Hashable {
    /// Priority columns sum to 10 (A=4…E=0) instead of unique A–E.
    case sumToTen
    /// Full karma-based generation instead of priority / BP.
    case karmaGeneration
    /// Extra free karma after (or during) generation (street vs prime packages).
    case bonusStartingKarma
    /// Free or discounted knowledge / language points.
    case freeKnowledgeSkills
    /// Extra contact points or free loyalty/connection.
    case expandedContacts
    /// Allow Exceptional Attribute / Lucky-style maximum bumps at chargen.
    case exceptionalAttributeAtChargen
    /// Fractional essence rounding favor (e.g. round down costs).
    case essenceCostRounding
    /// Quality positive/negative karma budget adjustments.
    case qualityBudgetAdjustment
    /// Prime runner / higher resources package.
    case primeRunnerPackage
    /// Alternate attribute point costs (linear vs progressive).
    case alternateAttributeCosts

    public var displayName: String {
        switch self {
        case .sumToTen: "Sum-to-Ten Priorities"
        case .karmaGeneration: "Karma Generation"
        case .bonusStartingKarma: "Bonus Starting Karma"
        case .freeKnowledgeSkills: "Free Knowledge Skills"
        case .expandedContacts: "Expanded Contacts"
        case .exceptionalAttributeAtChargen: "Exceptional Attribute at Chargen"
        case .essenceCostRounding: "Favorable Essence Rounding"
        case .qualityBudgetAdjustment: "Quality Budget Adjustment"
        case .primeRunnerPackage: "Prime Runner Package"
        case .alternateAttributeCosts: "Alternate Attribute Costs"
        }
    }

    public var summary: String {
        switch self {
        case .sumToTen:
            "Assign priority letters so values sum to 10 (duplicates allowed)."
        case .karmaGeneration:
            "Build the character entirely with karma instead of priority/BP."
        case .bonusStartingKarma:
            "Grant additional starting karma after generation."
        case .freeKnowledgeSkills:
            "Provide free knowledge/language ranks based on Logic/Intuition."
        case .expandedContacts:
            "Extra contact points or free contacts at creation."
        case .exceptionalAttributeAtChargen:
            "Permit natural maximum +1 qualities during generation."
        case .essenceCostRounding:
            "Round augmentation essence costs down to a friendlier step."
        case .qualityBudgetAdjustment:
            "Raise/lower the positive quality karma cap."
        case .primeRunnerPackage:
            "Higher power level: extra karma and/or resources."
        case .alternateAttributeCosts:
            "Use a simplified (often linear) attribute advancement cost."
        }
    }
}

/// Concrete configuration for one campaign/table.
public struct HouseRules: Codable, Sendable, Hashable {
    public var enabled: Set<HouseRuleID>
    /// Used by `.bonusStartingKarma` and `.primeRunnerPackage`.
    public var bonusKarma: Int
    /// Extra free knowledge skill points (`.freeKnowledgeSkills`).
    public var freeKnowledgePoints: Int
    /// Extra contact points (`.expandedContacts`).
    public var extraContactPoints: Int
    /// Positive quality karma cap override; nil = edition default.
    public var positiveQualityKarmaCap: Int?
    /// Essence cost quantum when `.essenceCostRounding` is on (e.g. 0.1).
    public var essenceRoundingStep: Decimal
    /// Karma budget for full karmagen when enabled.
    public var karmaGenBudget: Int
    /// Dice-test house rules (glitch, Rule of Six, hit band). Optional for legacy payloads.
    public var dice: DiceHouseRules?

    public init(
        enabled: Set<HouseRuleID> = [],
        bonusKarma: Int = 0,
        freeKnowledgePoints: Int = 0,
        extraContactPoints: Int = 0,
        positiveQualityKarmaCap: Int? = nil,
        essenceRoundingStep: Decimal = Decimal(string: "0.1") ?? 0.1,
        karmaGenBudget: Int = 750,
        dice: DiceHouseRules? = nil
    ) {
        self.enabled = enabled
        self.bonusKarma = bonusKarma
        self.freeKnowledgePoints = freeKnowledgePoints
        self.extraContactPoints = extraContactPoints
        self.positiveQualityKarmaCap = positiveQualityKarmaCap
        self.essenceRoundingStep = essenceRoundingStep
        self.karmaGenBudget = karmaGenBudget
        self.dice = dice
    }

    /// Dice rules with core-book defaults when unset.
    public var resolvedDice: DiceHouseRules {
        dice ?? .coreBook
    }

    public func isEnabled(_ rule: HouseRuleID) -> Bool {
        enabled.contains(rule)
    }

    public mutating func enable(_ rule: HouseRuleID) {
        enabled.insert(rule)
    }

    public mutating func disable(_ rule: HouseRuleID) {
        enabled.remove(rule)
    }

    /// Strict core-book defaults — no house rules.
    public static let coreBook = Self()

    /// A sensible “popular table” preset covering the most common conveniences.
    public static let popularTable = Self(
        enabled: [
            .sumToTen,
            .bonusStartingKarma,
            .freeKnowledgeSkills,
            .expandedContacts,
            .qualityBudgetAdjustment
        ],
        bonusKarma: 25,
        freeKnowledgePoints: 0, // edition rules compute from Logic/Intuition when 0 means “auto”
        extraContactPoints: 3,
        positiveQualityKarmaCap: 35,
        dice: .popularTable
    )

    /// Prime-runner leaning preset.
    public static let primeRunner = Self(
        enabled: [
            .sumToTen,
            .primeRunnerPackage,
            .bonusStartingKarma,
            .expandedContacts,
            .exceptionalAttributeAtChargen
        ],
        bonusKarma: 50,
        freeKnowledgePoints: 0,
        extraContactPoints: 6,
        positiveQualityKarmaCap: 40,
        karmaGenBudget: 900
    )
}

// Custom Codable for Set<HouseRuleID> is automatic via synthesized Codable on Set when Element is Codable.
