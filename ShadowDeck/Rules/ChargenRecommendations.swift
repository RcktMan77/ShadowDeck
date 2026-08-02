//
//  ChargenRecommendations.swift
//  ShadowDeck
//
//  Suggested priorities, attributes, and skills from role + metatype.
//  Applied only when the user clicks “Apply recommended …”.
//

import Foundation

public struct PriorityRecommendation: Equatable, Sendable {
    public var assignment: PriorityAssignment
    public var rationale: String

    public init(assignment: PriorityAssignment, rationale: String) {
        self.assignment = assignment
        self.rationale = rationale
    }
}

public struct AttributeRecommendation: Equatable, Sendable {
    public var values: [AttributeID: Int]
    public var rationale: String

    public init(values: [AttributeID: Int], rationale: String) {
        self.values = values
        self.rationale = rationale
    }
}

public struct SkillRecommendation: Equatable, Sendable {
    public var ranks: [String: Int]
    public var rationale: String

    public init(ranks: [String: Int], rationale: String) {
        self.ranks = ranks
        self.rationale = rationale
    }
}

public enum ChargenRecommendations {
    public static func priorities(archetype: RunnerArchetype, metatype: MetatypeID) -> PriorityRecommendation {
        // Letters: A=highest … E=lowest. Unique A–E for core priority.
        // Columns: metatype, attributes, magicOrResonance, skills, resources
        let map: [PriorityColumn: PriorityLetter]
        let why: String

        switch archetype {
        case .streetSamurai:
            map = [.attributes: .a, .resources: .b, .skills: .c, .metatype: metatypePriority(for: metatype, preferred: .d), .magicOrResonance: .e]
            why = "Street samurai lean on Attributes and Resources for combat stats and cyberware budget; Magic stays E (mundane)."
        case .adept:
            map = [.magicOrResonance: .a, .attributes: .b, .skills: .c, .metatype: metatypePriority(for: metatype, preferred: .d), .resources: .e]
            why = "Adepts need high Magic priority for power points; Attributes and combat skills next; gear budget can be lean."
        case .combatMage:
            map = [.magicOrResonance: .a, .skills: .b, .attributes: .c, .metatype: metatypePriority(for: metatype, preferred: .d), .resources: .e]
            why = "Magicians prioritize Magic, then Skills (sorcery), then mental Attributes; Resources often last."
        case .face:
            map = [.attributes: .a, .skills: .b, .resources: .c, .metatype: metatypePriority(for: metatype, preferred: .d), .magicOrResonance: .e]
            why = "Faces want Charisma-linked Attributes and social Skills; moderate Resources for lifestyle and looks."
        case .decker:
            map = [.skills: .a, .resources: .b, .attributes: .c, .metatype: metatypePriority(for: metatype, preferred: .d), .magicOrResonance: .e]
            why = "Deckers need skill ranks and nuyen for a deck; Logic-focused Attributes; usually mundane."
        case .rigger:
            map = [.resources: .a, .skills: .b, .attributes: .c, .metatype: metatypePriority(for: metatype, preferred: .d), .magicOrResonance: .e]
            why = "Riggers burn Resources on vehicles/drones, then Piloting skills and Reaction."
        case .technomancer:
            map = [.magicOrResonance: .a, .skills: .b, .attributes: .c, .metatype: metatypePriority(for: metatype, preferred: .d), .resources: .e]
            why = "Technomancers need Resonance priority and Tasking skills; heavy cyberware budgets are usually a trap."
        case .spy:
            map = [.skills: .a, .attributes: .b, .resources: .c, .metatype: metatypePriority(for: metatype, preferred: .d), .magicOrResonance: .e]
            why = "Infiltrators prioritize Stealth/Perception skills and Agility, with moderate gear money."
        }

        // Ensure unique letters after metatype adjustment.
        var assignment = PriorityAssignment(values: map)
        assignment = uniquify(assignment)
        return PriorityRecommendation(assignment: assignment, rationale: why)
    }

    public static func attributes(
        archetype: RunnerArchetype,
        metatype: MetatypeID,
        edition: Edition,
        pointBudget: Int
    ) -> AttributeRecommendation {
        let profile = MetatypeCatalog.profile(for: metatype, edition: edition)
        var targets: [AttributeID: Int] = [:]
        for id in AttributeID.standardGenerationAttributes {
            targets[id] = profile.bounds(for: id).minimum
        }

        // Priority order of attributes to pump for each role.
        let order: [AttributeID]
        switch archetype {
        case .streetSamurai:
            order = [.reaction, .agility, .body, .strength, .intuition, .willpower, .logic, .charisma]
        case .adept:
            order = [.agility, .reaction, .strength, .body, .intuition, .willpower, .logic, .charisma]
        case .combatMage:
            order = [.willpower, .logic, .intuition, .charisma, .body, .reaction, .agility, .strength]
        case .face:
            order = [.charisma, .intuition, .willpower, .logic, .reaction, .agility, .body, .strength]
        case .decker:
            order = [.logic, .intuition, .willpower, .reaction, .agility, .charisma, .body, .strength]
        case .rigger:
            order = [.reaction, .intuition, .logic, .agility, .willpower, .body, .strength, .charisma]
        case .technomancer:
            order = [.logic, .willpower, .intuition, .charisma, .reaction, .agility, .body, .strength]
        case .spy:
            order = [.agility, .intuition, .reaction, .logic, .charisma, .willpower, .body, .strength]
        }

        var remaining = max(0, pointBudget)
        // First pass: raise each in order up to min+2 or max
        for id in order {
            guard remaining > 0 else { break }
            let bounds = profile.bounds(for: id)
            let softCap = min(bounds.maximum, bounds.minimum + 3)
            while remaining > 0, (targets[id] ?? bounds.minimum) < softCap {
                targets[id, default: bounds.minimum] += 1
                remaining -= 1
            }
        }
        // Second pass: dump remainder into top stats
        for id in order {
            guard remaining > 0 else { break }
            let bounds = profile.bounds(for: id)
            while remaining > 0, (targets[id] ?? bounds.minimum) < bounds.maximum {
                targets[id, default: bounds.minimum] += 1
                remaining -= 1
            }
        }

        return AttributeRecommendation(
            values: targets,
            rationale: "Suggested spread for a \(archetype.displayName) \(metatype.displayName), spending \(pointBudget - remaining) of \(pointBudget) attribute points. Adjust freely."
        )
    }

    public static func skills(archetype: RunnerArchetype, pointBudget: Int) -> SkillRecommendation {
        let packages: [RunnerArchetype: [(String, Int)]] = [
            .streetSamurai: [("pistols", 5), ("unarmed", 4), ("perception", 3), ("athletics", 3), ("sneaking", 2)],
            .adept: [("unarmed", 5), ("athletics", 4), ("perception", 3), ("sneaking", 3), ("pistols", 2)],
            .combatMage: [("spellcasting", 6), ("summoning", 4), ("perception", 3), ("negotiation", 2)],
            .face: [("negotiation", 6), ("perception", 4), ("sneaking", 2), ("pistols", 2)],
            .decker: [("hacking", 6), ("electronics", 5), ("perception", 3), ("sneaking", 2)],
            .rigger: [("piloting", 6), ("electronics", 4), ("perception", 3), ("pistols", 2)],
            .technomancer: [("hacking", 5), ("electronics", 5), ("perception", 3), ("negotiation", 2)],
            .spy: [("sneaking", 6), ("perception", 5), ("athletics", 3), ("pistols", 2)]
        ]
        var ranks: [String: Int] = [:]
        var remaining = max(0, pointBudget)
        for (key, desired) in packages[archetype] ?? [] {
            let take = min(desired, remaining, 6)
            if take > 0 {
                ranks[key] = take
                remaining -= take
            }
        }
        return SkillRecommendation(
            ranks: ranks,
            rationale: "Suggested skill package for \(archetype.displayName). Uses \(pointBudget - remaining) of \(pointBudget) skill points."
        )
    }

    // MARK: - Helpers

    private static func metatypePriority(for metatype: MetatypeID, preferred: PriorityLetter) -> PriorityLetter {
        // Non-humans often need higher metatype priority in SR5 tables.
        switch metatype {
        case .human: return preferred
        case .elf: return maxLetter(preferred, .d)
        case .dwarf, .ork: return maxLetter(preferred, .c)
        case .troll: return maxLetter(preferred, .b)
        }
    }

    private static func maxLetter(_ a: PriorityLetter, _ b: PriorityLetter) -> PriorityLetter {
        a.rankValue >= b.rankValue ? a : b
    }

    private static func uniquify(_ input: PriorityAssignment) -> PriorityAssignment {
        var used = Set<PriorityLetter>()
        var values: [PriorityColumn: PriorityLetter] = [:]
        let order = PriorityColumn.allCases
        for col in order {
            if let letter = input[col], !used.contains(letter) {
                values[col] = letter
                used.insert(letter)
            }
        }
        let remaining = PriorityLetter.allCases.filter { !used.contains($0) }
        var ri = 0
        for col in order where values[col] == nil {
            if ri < remaining.count {
                values[col] = remaining[ri]
                ri += 1
            }
        }
        return PriorityAssignment(values: values)
    }
}
