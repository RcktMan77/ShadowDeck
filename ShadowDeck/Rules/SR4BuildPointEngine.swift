//
//  SR4BuildPointEngine.swift
//  ShadowDeck
//
//  SR4A-oriented Build Points accounting for character generation (400 BP).
//  Pure costs — no UI. See Docs/TABLE_READINESS_REMEDIATION.md and DESIGN.md.
//

import Foundation

/// Category breakdown of BP spent during SR4 chargen.
public struct SR4BuildPointLedger: Equatable, Sendable, Hashable {
    public var metatype: Int
    public var attributes: Int
    public var skills: Int
    public var qualities: Int
    public var resources: Int

    public init(
        metatype: Int = 0,
        attributes: Int = 0,
        skills: Int = 0,
        qualities: Int = 0,
        resources: Int = 0
    ) {
        self.metatype = metatype
        self.attributes = attributes
        self.skills = skills
        self.qualities = qualities
        self.resources = resources
    }

    public var total: Int {
        metatype + attributes + skills + qualities + resources
    }

    public var lines: [(label: String, bp: Int)] {
        [
            ("Metatype", metatype),
            ("Attributes", attributes),
            ("Skills", skills),
            ("Qualities", qualities),
            ("Resources", resources)
        ]
    }
}

/// SR4A Build Point costs for the ShadowDeck generation wizard (v1 scope).
public enum SR4BuildPointEngine {
    public static let defaultBudget = 400

    /// ¥ per BP for resources (SR4A).
    public static let nuyenPerBuildPoint = 5_000

    /// BP per point above racial/path minimum for BOD–WIL, Edge, Magic, Resonance.
    public static let attributePointCost = 10

    /// BP per rank of an active skill.
    public static let activeSkillRankCost = 4

    /// BP per rank of knowledge / language skills.
    public static let knowledgeSkillRankCost = 2

    // MARK: - Metatype (SR4A)

    public static func metatypeCost(_ metatype: MetatypeID) -> Int {
        switch metatype {
        case .human: 0
        case .ork: 20
        case .dwarf: 25
        case .elf: 30
        case .troll: 40
        }
    }

    // MARK: - Attributes

    /// BP for points purchased above metatype (or path) minimums.
    public static func attributeCost(
        attributes: AttributeRatings,
        metatype: MetatypeID,
        awakened: AwakenedPath,
        edition: Edition = .sr4
    ) -> Int {
        let profile = MetatypeCatalog.profile(for: metatype, edition: edition)
        var bp = 0
        for id in AttributeID.standardGenerationAttributes {
            let min = profile.bounds(for: id).minimum
            let purchased = max(0, attributes[id] - min)
            bp += purchased * attributePointCost
        }
        // Edge
        let edgeMin = profile.bounds(for: .edge).minimum
        bp += max(0, attributes.edge - edgeMin) * attributePointCost
        // Magic / Resonance above path floor
        if awakened.usesMagic {
            let magicMin = 1
            bp += max(0, attributes.magic - magicMin) * attributePointCost
        }
        if awakened.usesResonance {
            let resMin = 1
            bp += max(0, attributes.resonance - resMin) * attributePointCost
        }
        return bp
    }

    // MARK: - Skills

    public static func skillCost(_ skills: [SkillRating]) -> Int {
        skills.reduce(0) { partial, skill in
            let perRank: Int
            switch skill.category {
            case .active: perRank = activeSkillRankCost
            case .knowledge, .language: perRank = knowledgeSkillRankCost
            }
            return partial + max(0, skill.rating) * perRank
        }
    }

    public static func skillCost(ranks: [String: Int], skills: [SkillRating]) -> Int {
        // Prefer structured skills list when present; ranks map is source during wizard.
        if !skills.isEmpty {
            return skillCost(skills.filter { $0.rating > 0 })
        }
        // Fallback: treat all ranks as active (wizard chargen catalog is active).
        return ranks.values.reduce(0) { $0 + max(0, $1) * activeSkillRankCost }
    }

    // MARK: - Qualities

    /// Positive qualities cost BP; negative qualities refund BP (capped externally).
    public static func qualityNetCost(_ qualities: [QualityInstance]) -> Int {
        var positive = 0
        var negative = 0
        for q in qualities {
            let v = abs(q.karmaValue)
            switch q.kind {
            case .positive: positive += v
            case .negative: negative += v
            }
        }
        return positive - negative
    }

    // MARK: - Resources

    public static func resourceCost(nuyen: Int) -> Int {
        guard nuyen > 0 else { return 0 }
        // Ceiling division: partial 5k blocks still cost a BP.
        return (nuyen + nuyenPerBuildPoint - 1) / nuyenPerBuildPoint
    }

    public static func nuyenForBuildPoints(_ bp: Int) -> Int {
        max(0, bp) * nuyenPerBuildPoint
    }

    // MARK: - Ledger

    public static func ledger(
        metatype: MetatypeID,
        attributes: AttributeRatings,
        awakened: AwakenedPath,
        skills: [SkillRating],
        skillRanks: [String: Int] = [:],
        qualities: [QualityInstance],
        nuyen: Int,
        budget: Int = defaultBudget
    ) -> (ledger: SR4BuildPointLedger, remaining: Int) {
        let led = SR4BuildPointLedger(
            metatype: metatypeCost(metatype),
            attributes: attributeCost(
                attributes: attributes,
                metatype: metatype,
                awakened: awakened
            ),
            skills: skillCost(ranks: skillRanks, skills: skills),
            qualities: qualityNetCost(qualities),
            resources: resourceCost(nuyen: nuyen)
        )
        return (led, budget - led.total)
    }

    public static func isOverBudget(remaining: Int) -> Bool {
        remaining < 0
    }
}
