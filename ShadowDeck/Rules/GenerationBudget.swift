//
//  GenerationBudget.swift
//  ShadowDeck
//
//  Live allocation counters for the character generation wizard.
//

import Foundation

/// Mutable point pools during chargen. UI greys out increments when exhausted.
public struct GenerationBudget: Equatable, Sendable {
    public var attributePointsRemaining: Int
    public var attributePointsTotal: Int
    public var specialPointsRemaining: Int
    public var specialPointsTotal: Int
    public var skillPointsRemaining: Int
    public var skillPointsTotal: Int
    public var skillGroupPointsRemaining: Int
    public var skillGroupPointsTotal: Int
    public var buildPointsRemaining: Int
    public var buildPointsTotal: Int
    public var karmaRemaining: Int
    public var karmaTotal: Int
    public var nuyenRemaining: Int
    public var nuyenTotal: Int
    public var positiveQualityKarmaUsed: Int
    public var positiveQualityKarmaCap: Int
    public var negativeQualityKarmaGained: Int
    public var negativeQualityKarmaCap: Int

    public init(
        attributePointsRemaining: Int = 0,
        attributePointsTotal: Int = 0,
        specialPointsRemaining: Int = 0,
        specialPointsTotal: Int = 0,
        skillPointsRemaining: Int = 0,
        skillPointsTotal: Int = 0,
        skillGroupPointsRemaining: Int = 0,
        skillGroupPointsTotal: Int = 0,
        buildPointsRemaining: Int = 0,
        buildPointsTotal: Int = 0,
        karmaRemaining: Int = 0,
        karmaTotal: Int = 0,
        nuyenRemaining: Int = 0,
        nuyenTotal: Int = 0,
        positiveQualityKarmaUsed: Int = 0,
        positiveQualityKarmaCap: Int = 25,
        negativeQualityKarmaGained: Int = 0,
        negativeQualityKarmaCap: Int = 25
    ) {
        self.attributePointsRemaining = attributePointsRemaining
        self.attributePointsTotal = attributePointsTotal
        self.specialPointsRemaining = specialPointsRemaining
        self.specialPointsTotal = specialPointsTotal
        self.skillPointsRemaining = skillPointsRemaining
        self.skillPointsTotal = skillPointsTotal
        self.skillGroupPointsRemaining = skillGroupPointsRemaining
        self.skillGroupPointsTotal = skillGroupPointsTotal
        self.buildPointsRemaining = buildPointsRemaining
        self.buildPointsTotal = buildPointsTotal
        self.karmaRemaining = karmaRemaining
        self.karmaTotal = karmaTotal
        self.nuyenRemaining = nuyenRemaining
        self.nuyenTotal = nuyenTotal
        self.positiveQualityKarmaUsed = positiveQualityKarmaUsed
        self.positiveQualityKarmaCap = positiveQualityKarmaCap
        self.negativeQualityKarmaGained = negativeQualityKarmaGained
        self.negativeQualityKarmaCap = negativeQualityKarmaCap
    }

    public var attributePointsSpent: Int { max(0, attributePointsTotal - attributePointsRemaining) }
    public var skillPointsSpent: Int { max(0, skillPointsTotal - skillPointsRemaining) }

    public mutating func resetAttributes(total: Int) {
        attributePointsTotal = total
        attributePointsRemaining = total
    }

    public mutating func resetSpecial(total: Int) {
        specialPointsTotal = total
        specialPointsRemaining = total
    }

    public mutating func resetSkills(points: Int, groups: Int) {
        skillPointsTotal = points
        skillPointsRemaining = points
        skillGroupPointsTotal = groups
        skillGroupPointsRemaining = groups
    }

    public mutating func resetNuyen(total: Int) {
        nuyenTotal = total
        nuyenRemaining = total
    }

    public mutating func resetBuildPoints(total: Int) {
        buildPointsTotal = total
        buildPointsRemaining = total
    }
}

/// Snapshot of what a priority letter grants for a column (for option cards).
public struct PriorityGrantSummary: Equatable, Sendable, Identifiable {
    public var id: String { "\(column.rawValue)-\(letter.rawValue)" }
    public var column: PriorityColumn
    public var letter: PriorityLetter
    public var title: String
    public var detailLines: [String]

    public init(column: PriorityColumn, letter: PriorityLetter, title: String, detailLines: [String]) {
        self.column = column
        self.letter = letter
        self.title = title
        self.detailLines = detailLines
    }
}

public enum PrioritySummaryBuilder {
    public static func summaries(
        for edition: Edition,
        metatype: MetatypeID,
        rules: any EditionRules
    ) -> [PriorityGrantSummary] {
        var result: [PriorityGrantSummary] = []
        for column in PriorityColumn.allCases {
            for letter in PriorityLetter.allCases {
                var lines: [String] = []
                switch column {
                case .metatype:
                    if let pts = rules.specialAttributePoints(for: letter, metatype: metatype) {
                        lines.append("\(metatype.displayName) available")
                        lines.append("\(pts) special / adjustment points")
                    } else {
                        lines.append("\(metatype.displayName) not available at \(letter.rawValue)")
                    }
                case .attributes:
                    if let pts = rules.attributePoints(for: letter) {
                        lines.append("\(pts) attribute points")
                    }
                case .magicOrResonance:
                    lines.append(magicLine(edition: edition, letter: letter))
                case .skills:
                    if let sk = rules.skillPoints(for: letter) {
                        lines.append("\(sk.skills) skill points")
                        if sk.groups > 0 {
                            lines.append("\(sk.groups) skill group points")
                        }
                    }
                case .resources:
                    if let nuyen = rules.resourceNuyen(for: letter) {
                        lines.append(formatNuyen(nuyen))
                    }
                }
                result.append(
                    PriorityGrantSummary(
                        column: column,
                        letter: letter,
                        title: "\(column.displayName) · \(letter.rawValue)",
                        detailLines: lines
                    )
                )
            }
        }
        return result
    }

    private static func magicLine(edition: Edition, letter: PriorityLetter) -> String {
        // High-level guidance; full tables are data-driven later.
        switch (edition, letter) {
        case (_, .a): return "Full Magician / Mystic Adept / high Resonance options"
        case (_, .b): return "Magician / Adept / Technomancer mid options"
        case (_, .c): return "Adept / Aspected / limited Magic or Resonance"
        case (_, .d): return "Minimal Magic/Resonance or mundane Edge focus"
        case (_, .e): return "Mundane (special points to Edge only)"
        }
    }

    private static func formatNuyen(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let n = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "¥\(n)"
    }
}
