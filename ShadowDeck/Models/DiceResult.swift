//
//  DiceResult.swift
//  ShadowDeck
//
//  Edition-aware dice roll results and options for the in-app roller.
//

import Foundation

public enum DiceEdgeMode: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    /// Pre-roll: add Edge rating dice + Rule of Six.
    case pushTheLimit
    /// Post-roll: re-roll non-hits once.
    case secondChance

    public var displayName: String {
        switch self {
        case .none: "None"
        case .pushTheLimit: "Push the Limit"
        case .secondChance: "Second Chance"
        }
    }
}

public struct DiceRollOptions: Sendable, Hashable {
    /// Exploding 6s (Rule of Six). Typically on with Push the Limit.
    public var ruleOfSix: Bool
    /// Cap recursive explosions so a bad RNG loop cannot hang.
    public var maxExplosions: Int

    public init(ruleOfSix: Bool = false, maxExplosions: Int = 40) {
        self.ruleOfSix = ruleOfSix
        self.maxExplosions = max(0, maxExplosions)
    }

    public static let standard = Self(ruleOfSix: false)
    public static let pushTheLimit = Self(ruleOfSix: true)
}

public struct DiceResult: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var hits: Int
    public var ones: Int
    public var glitch: Bool
    public var criticalGlitch: Bool
    /// Final faces after explosions (each face is 1…6).
    public var dice: [Int]
    /// Dice requested before explosions.
    public var pool: Int
    public var modifier: Int
    public var edition: Edition
    public var edgeSpent: Int
    public var edgeMode: DiceEdgeMode
    public var timestamp: Date
    public var sourceLabel: String?

    public init(
        id: UUID = UUID(),
        hits: Int,
        ones: Int,
        glitch: Bool,
        criticalGlitch: Bool,
        dice: [Int],
        pool: Int,
        modifier: Int = 0,
        edition: Edition,
        edgeSpent: Int = 0,
        edgeMode: DiceEdgeMode = .none,
        timestamp: Date = Date(),
        sourceLabel: String? = nil
    ) {
        self.id = id
        self.hits = hits
        self.ones = ones
        self.glitch = glitch
        self.criticalGlitch = criticalGlitch
        self.dice = dice
        self.pool = pool
        self.modifier = modifier
        self.edition = edition
        self.edgeSpent = edgeSpent
        self.edgeMode = edgeMode
        self.timestamp = timestamp
        self.sourceLabel = sourceLabel
    }

    /// Effective dice count used for the pool field display (base + modifier).
    public var effectivePool: Int { max(0, pool + modifier) }

    public var outcomeSummary: String {
        if criticalGlitch { return "Critical glitch" }
        if glitch { return "Glitch · \(hits) hit\(hits == 1 ? "" : "s")" }
        return "\(hits) hit\(hits == 1 ? "" : "s")"
    }

    /// Clipboard-friendly one-liner.
    public var copyText: String {
        var parts: [String] = [edition.shortName]
        if let sourceLabel, !sourceLabel.isEmpty {
            parts.append(sourceLabel)
        }
        parts.append("pool \(effectivePool)")
        if edgeSpent > 0 {
            parts.append("Edge \(edgeMode.displayName)")
        }
        parts.append(outcomeSummary)
        if !dice.isEmpty {
            let faces = dice.map(String.init).joined(separator: " ")
            parts.append("[\(faces)]")
        }
        return parts.joined(separator: " · ")
    }
}

/// Request to open the roller with a prefilled pool.
public struct DiceRollRequest: Sendable, Hashable {
    public var pool: Int
    public var modifier: Int
    public var edition: Edition
    public var sourceLabel: String?
    public var edgeRating: Int

    public init(
        pool: Int,
        modifier: Int = 0,
        edition: Edition,
        sourceLabel: String? = nil,
        edgeRating: Int = 0
    ) {
        self.pool = max(0, pool)
        self.modifier = modifier
        self.edition = edition
        self.sourceLabel = sourceLabel
        self.edgeRating = max(0, edgeRating)
    }
}
