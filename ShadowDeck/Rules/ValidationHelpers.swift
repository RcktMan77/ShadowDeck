//
//  ValidationHelpers.swift
//  ShadowDeck
//
//  Shared validation helpers used by edition rules and import soft-checks.
//

import Foundation

public enum ValidationHelpers {
    /// SR4/SR5/SR6 core: augmented attribute maximum is natural maximum + 4.
    public static let standardAugmentedBonus = 4

    /// Qualities granted by Magic/Resonance priority (or equivalent), not the
    /// positive quality karma budget at chargen.
    public static let freePathQualityCatalogKeys: Set<String> = [
        "adept",
        "magician",
        "full_magician",
        "mystic_adept",
        "technomancer",
        "aspected_magician",
        "aspected_mage",
        "enchanter",
        "sorcerer",
        "conjurer",
        "explorer",
    ]

    /// Maximum allowed attribute rating for a *play sheet* (natural max + aug bonus,
    /// optional Exceptional Attribute bump).
    public static func augmentedAttributeMaximum(
        naturalMaximum: Int,
        houseRules: HouseRules
    ) -> Int {
        var max = naturalMaximum + standardAugmentedBonus
        if houseRules.isEnabled(.exceptionalAttributeAtChargen) {
            max += 1
        }
        return max
    }

    /// Whether a positive quality counts against the chargen positive-karma cap.
    public static func countsTowardPositiveQualityCap(_ quality: QualityInstance) -> Bool {
        guard quality.kind == .positive else { return false }
        if freePathQualityCatalogKeys.contains(quality.catalogKey) {
            return false
        }
        let name = quality.name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Free path markers (with or without parenthetical extras).
        let freeNames: Set<String> = [
            "adept",
            "magician",
            "mystic adept",
            "technomancer",
            "aspected magician",
            "aspected mage",
            "enchanter",
            "sorcerer",
            "conjurer",
            "explorer",
        ]
        if freeNames.contains(name) { return false }
        if name.hasPrefix("aspected ") { return false }
        return true
    }

    public static func positiveQualityKarmaSpend(qualities: [QualityInstance]) -> Int {
        qualities
            .filter(countsTowardPositiveQualityCap)
            .reduce(0) { $0 + max(0, $1.karmaValue) }
    }

    /// Validate a single attribute for campaign/play sheets (allows augmented totals).
    public static func attributeOutOfPlayBounds(
        value: Int,
        bounds: AttributeBounds,
        houseRules: HouseRules
    ) -> Bool {
        let maxAllowed = augmentedAttributeMaximum(
            naturalMaximum: bounds.maximum,
            houseRules: houseRules
        )
        return value < bounds.minimum || value > maxAllowed
    }
}
