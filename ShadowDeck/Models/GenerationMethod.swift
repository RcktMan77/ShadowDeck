//
//  GenerationMethod.swift
//  ShadowDeck
//
//  How a character was (or is being) built — edition peers share these concepts
//  with different default tables.
//

import Foundation

public enum PriorityLetter: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"

    public var rankValue: Int {
        switch self {
        case .a: 4
        case .b: 3
        case .c: 2
        case .d: 1
        case .e: 0
        }
    }

    /// Point value used by the Sum-to-Ten house rule (A=4 … E=0).
    public var sumToTenValue: Int { rankValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rankValue < rhs.rankValue
    }
}

public enum PriorityColumn: String, Codable, Sendable, CaseIterable, Hashable {
    case metatype
    case attributes
    case magicOrResonance
    case skills
    case resources

    public var displayName: String {
        switch self {
        case .metatype: "Metatype"
        case .attributes: "Attributes"
        case .magicOrResonance: "Magic/Resonance"
        case .skills: "Skills"
        case .resources: "Resources"
        }
    }
}

/// Classic unique A–E assignment or sum-to-ten multi-assign.
public struct PriorityAssignment: Codable, Sendable, Hashable {
    public var values: [PriorityColumn: PriorityLetter]

    public init(values: [PriorityColumn: PriorityLetter] = [:]) {
        self.values = values
    }

    public subscript(_ column: PriorityColumn) -> PriorityLetter? {
        get { values[column] }
        set { values[column] = newValue }
    }

    public var isComplete: Bool {
        PriorityColumn.allCases.allSatisfy { values[$0] != nil }
    }

    /// True when each letter A–E appears exactly once (core priority rules).
    public var usesUniqueLetters: Bool {
        let letters = values.values.map(\.rawValue)
        return letters.count == PriorityColumn.allCases.count
            && Set(letters).count == PriorityColumn.allCases.count
    }

    public var sumToTenTotal: Int {
        values.values.reduce(0) { $0 + $1.sumToTenValue }
    }
}

public enum GenerationSystem: String, Codable, Sendable, CaseIterable, Hashable {
    /// SR4 default: Build Points.
    case buildPoints
    /// Priority table (SR5 / SR6 default; optional for SR4 via house rules / optional books).
    case priority
    /// Sum-to-Ten variant of priority (popular house rule).
    case sumToTen
    /// Pure karma generation (SR4 official variant; popular house rule in 5e/6e).
    case karmaGen
    /// Point-buy style custom budgets (house rule).
    case pointBuy

    public var displayName: String {
        switch self {
        case .buildPoints: "Build Points"
        case .priority: "Priority"
        case .sumToTen: "Sum-to-Ten"
        case .karmaGen: "Karma Generation"
        case .pointBuy: "Point Buy"
        }
    }
}

/// Snapshot of chargen configuration attached to a character for validation & resume.
public struct GenerationProfile: Codable, Sendable, Hashable {
    public var system: GenerationSystem
    public var priority: PriorityAssignment
    /// SR4 BP budget (typically 400).
    public var buildPointBudget: Int
    public var buildPointsSpent: Int
    /// Karma available at chargen (quality buy, leftover, or full karmagen).
    public var karmaBudget: Int
    public var karmaSpent: Int
    public var nuyenBudget: Int
    public var nuyenSpent: Int
    public var attributePoints: Int
    public var specialAttributePoints: Int
    public var skillPoints: Int
    public var skillGroupPoints: Int
    public var isFinished: Bool

    public init(
        system: GenerationSystem,
        priority: PriorityAssignment = PriorityAssignment(),
        buildPointBudget: Int = 0,
        buildPointsSpent: Int = 0,
        karmaBudget: Int = 0,
        karmaSpent: Int = 0,
        nuyenBudget: Int = 0,
        nuyenSpent: Int = 0,
        attributePoints: Int = 0,
        specialAttributePoints: Int = 0,
        skillPoints: Int = 0,
        skillGroupPoints: Int = 0,
        isFinished: Bool = false
    ) {
        self.system = system
        self.priority = priority
        self.buildPointBudget = buildPointBudget
        self.buildPointsSpent = buildPointsSpent
        self.karmaBudget = karmaBudget
        self.karmaSpent = karmaSpent
        self.nuyenBudget = nuyenBudget
        self.nuyenSpent = nuyenSpent
        self.attributePoints = attributePoints
        self.specialAttributePoints = specialAttributePoints
        self.skillPoints = skillPoints
        self.skillGroupPoints = skillGroupPoints
        self.isFinished = isFinished
    }
}
