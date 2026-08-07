//
//  SR4BuildPointEngine.swift
//  ShadowDeck
//
//  SR4A-oriented Build Points accounting for character generation (400 BP).
//  Pure costs — no UI. See local design notes (Docs/).
//

import Foundation

/// Category breakdown of BP spent during SR4 chargen.
public struct SR4BuildPointLedger: Equatable, Sendable, Hashable {
    public var metatype: Int
    public var attributes: Int
    public var skills: Int
    public var skillGroups: Int
    public var spells: Int
    public var contacts: Int
    public var qualities: Int
    public var resources: Int

    public init(
        metatype: Int = 0,
        attributes: Int = 0,
        skills: Int = 0,
        skillGroups: Int = 0,
        spells: Int = 0,
        contacts: Int = 0,
        qualities: Int = 0,
        resources: Int = 0
    ) {
        self.metatype = metatype
        self.attributes = attributes
        self.skills = skills
        self.skillGroups = skillGroups
        self.spells = spells
        self.contacts = contacts
        self.qualities = qualities
        self.resources = resources
    }

    public var total: Int {
        metatype + attributes + skills + skillGroups + spells + contacts + qualities + resources
    }

    public var lines: [(label: String, bp: Int)] {
        [
            ("Metatype", metatype),
            ("Attributes", attributes),
            ("Skills", skills),
            ("Skill groups", skillGroups),
            ("Spells", spells),
            ("Contacts", contacts),
            ("Qualities", qualities),
            ("Resources", resources)
        ]
    }
}

/// SR4A Build Point costs for the ShadowDeck generation wizard.
public enum SR4BuildPointEngine {
    public static let defaultBudget = 400

    /// ¥ per BP for resources (SR4A).
    public static let nuyenPerBuildPoint = 5_000

    /// BP per point above racial/path minimum for BOD–WIL, Edge, Magic, Resonance.
    public static let attributePointCost = 10

    /// BP per rank of an active skill.
    public static let activeSkillRankCost = 4

    /// BP per rank of knowledge / language skills (extra points beyond free pool).
    public static let knowledgeSkillRankCost = 2

    /// BP per skill group rating (chargen max 4).
    public static let skillGroupRankCost = 10

    public static let skillGroupMaxAtChargen = 4

    /// BP to learn one spell at chargen.
    public static let spellCost = 3

    /// BP per rating point of a complex form at chargen.
    public static let complexFormBPPerRating = 1

    public static let positiveQualityCap = 35
    public static let negativeQualityCap = 35

    /// Skill groups offered in the SR4A core chargen wizard.
    public static let chargenSkillGroups: [SkillGroupID] = [
        .athletics,
        .biotech,
        .closeCombat,
        .conjuring,
        .cracking,
        .electronics,
        .fireArarms,
        .influence,
        .outdoors,
        .sorcery,
        .stealth,
        .tasking
    ]

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
        let edgeMin = profile.bounds(for: .edge).minimum
        bp += max(0, attributes.edge - edgeMin) * attributePointCost
        if awakened.usesMagic {
            bp += max(0, attributes.magic - 1) * attributePointCost
        }
        if awakened.usesResonance {
            bp += max(0, attributes.resonance - 1) * attributePointCost
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
        if !skills.isEmpty {
            return skillCost(skills.filter { $0.rating > 0 })
        }
        return ranks.values.reduce(0) { $0 + max(0, $1) * activeSkillRankCost }
    }

    public static func skillGroupCost(_ groups: [SkillGroupRating]) -> Int {
        groups.reduce(0) { $0 + max(0, $1.rating) * skillGroupRankCost }
    }

    public static func skillGroupCost(ratings: [SkillGroupID: Int]) -> Int {
        ratings.values.reduce(0) { $0 + max(0, $1) * skillGroupRankCost }
    }

    // MARK: - Spells & contacts

    public static func spellCost(count: Int) -> Int {
        max(0, count) * spellCost
    }

    public static func spellCost(_ spells: [SpellInstance]) -> Int {
        spellCost(count: spells.count)
    }

    /// SR4A: contact BP = Connection + Loyalty (each 1–6).
    public static func contactCost(connection: Int, loyalty: Int) -> Int {
        max(0, connection) + max(0, loyalty)
    }

    public static func contactCost(_ contacts: [Contact]) -> Int {
        contacts.reduce(0) { $0 + contactCost(connection: $1.connection, loyalty: $1.loyalty) }
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
        skillGroups: [SkillGroupRating] = [],
        skillGroupRatings: [SkillGroupID: Int] = [:],
        spells: [SpellInstance] = [],
        contacts: [Contact] = [],
        qualities: [QualityInstance],
        nuyen: Int,
        budget: Int = defaultBudget
    ) -> (ledger: SR4BuildPointLedger, remaining: Int) {
        let groupBP: Int
        if !skillGroups.isEmpty {
            groupBP = skillGroupCost(skillGroups)
        } else {
            groupBP = skillGroupCost(ratings: skillGroupRatings)
        }
        let led = SR4BuildPointLedger(
            metatype: metatypeCost(metatype),
            attributes: attributeCost(
                attributes: attributes,
                metatype: metatype,
                awakened: awakened
            ),
            skills: skillCost(ranks: skillRanks, skills: skills),
            skillGroups: groupBP,
            spells: spellCost(spells),
            contacts: contactCost(contacts),
            qualities: qualityNetCost(qualities),
            resources: resourceCost(nuyen: nuyen)
        )
        return (led, budget - led.total)
    }

    public static func isOverBudget(remaining: Int) -> Bool {
        remaining < 0
    }

    /// Max spells at chargen = 2 × highest of Spellcasting / Ritual Spellcasting.
    public static func maxSpellsAtChargen(skillRanks: [String: Int], skills: [SkillRating]) -> Int {
        let spellcasting = skillRanks["spellcasting"]
            ?? skills.first { $0.catalogKey == "spellcasting" }?.rating
            ?? 0
        let ritual = skillRanks["ritual_spellcasting"]
            ?? skills.first { $0.catalogKey == "ritual_spellcasting" }?.rating
            ?? 0
        let peak = max(spellcasting, ritual)
        return max(0, peak * 2)
    }
}
