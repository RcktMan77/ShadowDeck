//
//  Metatype.swift
//  ShadowDeck
//
//  Core metatypes with edition-aware attribute ranges.
//

import Foundation

public enum MetatypeID: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case human
    case elf
    case dwarf
    case ork
    case troll

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .human: "Human"
        case .elf: "Elf"
        case .dwarf: "Dwarf"
        case .ork: "Ork"
        case .troll: "Troll"
        }
    }
}

/// Attribute min/max for a single attribute on a metatype (natural, unmodified).
public struct AttributeBounds: Codable, Sendable, Hashable {
    public var minimum: Int
    public var maximum: Int

    public init(minimum: Int, maximum: Int) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public func contains(_ value: Int) -> Bool {
        (minimum...maximum).contains(value)
    }

    public var range: ClosedRange<Int> { minimum...maximum }
}

/// Edition-specific natural attribute bounds for a metatype.
public struct MetatypeProfile: Codable, Sendable, Hashable, Identifiable {
    public var id: MetatypeID
    public var edition: Edition
    public var bounds: [AttributeID: AttributeBounds]

    public init(id: MetatypeID, edition: Edition, bounds: [AttributeID: AttributeBounds]) {
        self.id = id
        self.edition = edition
        self.bounds = bounds
    }

    public func bounds(for attribute: AttributeID) -> AttributeBounds {
        bounds[attribute] ?? AttributeBounds(minimum: 1, maximum: 6)
    }
}

/// Factory for core-book metatype profiles. Values follow common core baselines;
/// exact tables live in edition rules and can be data-driven later.
public enum MetatypeCatalog {
    public static func profile(for metatype: MetatypeID, edition: Edition) -> MetatypeProfile {
        MetatypeProfile(id: metatype, edition: edition, bounds: boundsTable(metatype, edition))
    }

    public static func allProfiles(for edition: Edition) -> [MetatypeProfile] {
        MetatypeID.allCases.map { profile(for: $0, edition: edition) }
    }

    // MARK: - Core tables

    /// Shared core-book style mins/maxes. SR4A / SR5 / SR6 share the classic metatype
    /// spread for the five core metatypes; edition rules may overlay chargen caps.
    private static func boundsTable(_ metatype: MetatypeID, _ edition: Edition) -> [AttributeID: AttributeBounds] {
        // Edge maxima: humans get higher natural Edge in all modern editions.
        let humanEdgeMax = 7
        let otherEdgeMax = 6

        switch metatype {
        case .human:
            return base(
                body: 1...6,
                agility: 1...6,
                reaction: 1...6,
                strength: 1...6,
                willpower: 1...6,
                logic: 1...6,
                intuition: 1...6,
                charisma: 1...6,
                edge: 1...humanEdgeMax,
                magic: 0...6,
                resonance: 0...6
            )
        case .elf:
            return base(
                body: 1...6,
                agility: 2...7,
                reaction: 1...6,
                strength: 1...6,
                willpower: 1...6,
                logic: 1...6,
                intuition: 1...6,
                charisma: 3...8,
                edge: 1...otherEdgeMax,
                magic: 0...6,
                resonance: 0...6
            )
        case .dwarf:
            return base(
                body: 3...8,
                agility: 1...6,
                reaction: 1...5,
                strength: 3...8,
                willpower: 2...7,
                logic: 1...6,
                intuition: 1...6,
                charisma: 1...6,
                edge: 1...otherEdgeMax,
                magic: 0...6,
                resonance: 0...6
            )
        case .ork:
            return base(
                body: 4...9,
                agility: 1...6,
                reaction: 1...6,
                strength: 3...8,
                willpower: 1...6,
                logic: 1...5,
                intuition: 1...6,
                charisma: 1...5,
                edge: 1...otherEdgeMax,
                magic: 0...6,
                resonance: 0...6
            )
        case .troll:
            // SR5/6 troll Body/Strength maxima are higher; keep peer-level core tables.
            let bodyMax = edition == .sr4 ? 10 : 10
            let strengthMax = edition == .sr4 ? 10 : 10
            return base(
                body: 5...bodyMax,
                agility: 1...5,
                reaction: 1...6,
                strength: 5...strengthMax,
                willpower: 1...6,
                logic: 1...5,
                intuition: 1...5,
                charisma: 1...4,
                edge: 1...otherEdgeMax,
                magic: 0...6,
                resonance: 0...6
            )
        }
    }

    private static func base(
        body: ClosedRange<Int>,
        agility: ClosedRange<Int>,
        reaction: ClosedRange<Int>,
        strength: ClosedRange<Int>,
        willpower: ClosedRange<Int>,
        logic: ClosedRange<Int>,
        intuition: ClosedRange<Int>,
        charisma: ClosedRange<Int>,
        edge: ClosedRange<Int>,
        magic: ClosedRange<Int>,
        resonance: ClosedRange<Int>
    ) -> [AttributeID: AttributeBounds] {
        [
            .body: AttributeBounds(minimum: body.lowerBound, maximum: body.upperBound),
            .agility: AttributeBounds(minimum: agility.lowerBound, maximum: agility.upperBound),
            .reaction: AttributeBounds(minimum: reaction.lowerBound, maximum: reaction.upperBound),
            .strength: AttributeBounds(minimum: strength.lowerBound, maximum: strength.upperBound),
            .willpower: AttributeBounds(minimum: willpower.lowerBound, maximum: willpower.upperBound),
            .logic: AttributeBounds(minimum: logic.lowerBound, maximum: logic.upperBound),
            .intuition: AttributeBounds(minimum: intuition.lowerBound, maximum: intuition.upperBound),
            .charisma: AttributeBounds(minimum: charisma.lowerBound, maximum: charisma.upperBound),
            .edge: AttributeBounds(minimum: edge.lowerBound, maximum: edge.upperBound),
            .magic: AttributeBounds(minimum: magic.lowerBound, maximum: magic.upperBound),
            .resonance: AttributeBounds(minimum: resonance.lowerBound, maximum: resonance.upperBound)
        ]
    }
}
