//
//  EditionRules.swift
//  ShadowDeck
//
//  Strategy protocol for edition-specific rules. SR4, SR5, and SR6 are peers.
//

import Foundation

public protocol EditionRules: Sendable {
    var edition: Edition { get }

    /// Default generation system for core-book play.
    var defaultGenerationSystem: GenerationSystem { get }

    /// Standard BP budget (SR4); 0 if not applicable.
    var standardBuildPointBudget: Int { get }

    /// Standard leftover / quality karma at priority chargen.
    var standardPriorityKarma: Int { get }

    /// Default positive quality karma cap at generation.
    var positiveQualityKarmaCap: Int { get }

    /// Default negative quality karma cap (absolute value).
    var negativeQualityKarmaCap: Int { get }

    func metatypeProfile(_ metatype: MetatypeID) -> MetatypeProfile

    /// Attribute points granted by a priority letter (nil if N/A).
    func attributePoints(for priority: PriorityLetter) -> Int?

    /// Special/adjustment points for metatype priority (simplified core tables).
    func specialAttributePoints(for priority: PriorityLetter, metatype: MetatypeID) -> Int?

    /// Resource nuyen for a resources priority letter.
    func resourceNuyen(for priority: PriorityLetter) -> Int?

    /// Skill points (active) for skills priority.
    func skillPoints(for priority: PriorityLetter) -> (skills: Int, groups: Int)?

    /// Karma cost to raise an attribute from `from` to `from+1` after chargen.
    func karmaCostToRaiseAttribute(from current: Int) -> Int

    /// Karma cost to raise a skill from `from` to `from+1` after chargen.
    func karmaCostToRaiseSkill(from current: Int) -> Int

    /// Compute derived stats for a character snapshot.
    func deriveStats(for character: Character) -> DerivedStats

    /// Validate core invariants for the character under these rules + house rules.
    func validate(_ character: Character) -> ValidationResult

    /// Apply essence costs from augmentations (with house-rule rounding).
    func computeEssence(for character: Character) -> Decimal
}

public extension EditionRules {
    func bounds(for metatype: MetatypeID, attribute: AttributeID) -> AttributeBounds {
        metatypeProfile(metatype).bounds(for: attribute)
    }

    func isAttributeInBounds(_ value: Int, attribute: AttributeID, metatype: MetatypeID) -> Bool {
        bounds(for: metatype, attribute: attribute).contains(value)
    }

    /// Attribute raise cost, optionally linear under `.alternateAttributeCosts`.
    func karmaCostToRaiseAttribute(from current: Int, houseRules: HouseRules) -> Int {
        if houseRules.isEnabled(.alternateAttributeCosts) {
            // Flat cost per step (vs progressive new-rating × N).
            return 5
        }
        return karmaCostToRaiseAttribute(from: current)
    }
}

/// Resolves the rules strategy for an edition.
public enum RulesRegistry {
    public static func rules(for edition: Edition) -> any EditionRules {
        switch edition {
        case .sr4: SR4Rules()
        case .sr5: SR5Rules()
        case .sr6: SR6Rules()
        }
    }

    public static var all: [any EditionRules] {
        Edition.allCases.map { rules(for: $0) }
    }
}
