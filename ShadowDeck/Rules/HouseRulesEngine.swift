//
//  HouseRulesEngine.swift
//  ShadowDeck
//
//  Apply selected house-rule toggles to chargen budgets and play-sheet limits.
//  Individual rules stack (multi-select); presets only seed the set.
//

import Foundation

public enum HouseRulesEngine {
    /// Starting karma after edition baseline + house-rule bonuses.
    public static func startingKarma(editionBaseline: Int, houseRules: HouseRules) -> Int {
        var karma = editionBaseline
        if houseRules.isEnabled(.bonusStartingKarma) || houseRules.isEnabled(.primeRunnerPackage) {
            karma += max(0, houseRules.bonusKarma)
        }
        return karma
    }

    /// Free knowledge/language ranks at chargen.
    /// When the rule is on and `freeKnowledgePoints == 0`, uses SR5-style (LOG+INT)×2.
    public static func freeKnowledgePoints(
        attributes: AttributeRatings,
        houseRules: HouseRules
    ) -> Int {
        guard houseRules.isEnabled(.freeKnowledgeSkills) else { return 0 }
        if houseRules.freeKnowledgePoints > 0 {
            return houseRules.freeKnowledgePoints
        }
        return max(0, (attributes.logic + attributes.intuition) * 2)
    }

    /// Contact point budget: CHA×3 core + expanded-contacts extras.
    public static func contactPoints(
        charisma: Int,
        houseRules: HouseRules
    ) -> Int {
        let base = max(0, charisma) * 3
        guard houseRules.isEnabled(.expandedContacts) else { return base }
        return base + max(0, houseRules.extraContactPoints)
    }

    /// Positive quality karma cap (edition default or house override).
    public static func positiveQualityCap(
        editionDefault: Int,
        houseRules: HouseRules
    ) -> Int {
        if houseRules.isEnabled(.qualityBudgetAdjustment),
           let override = houseRules.positiveQualityKarmaCap
        {
            return override
        }
        return houseRules.positiveQualityKarmaCap ?? editionDefault
    }

    /// Natural attribute maximum during chargen (Exceptional Attribute house rule).
    public static func naturalAttributeMaximum(
        metatypeMaximum: Int,
        houseRules: HouseRules
    ) -> Int {
        // Rule allows Exceptional Attribute quality (+1 natural max) at chargen.
        // For wizard steppers we allow +1 when the toggle is on (simplified table rule).
        if houseRules.isEnabled(.exceptionalAttributeAtChargen) {
            return metatypeMaximum + 1
        }
        return metatypeMaximum
    }

    /// Resources nuyen after prime-runner bump (optional 10% when package enabled without custom).
    public static func resourceNuyen(
        base: Int,
        houseRules: HouseRules
    ) -> Int {
        guard houseRules.isEnabled(.primeRunnerPackage) else { return base }
        // Prime package already adds karma via bonusKarma; also nudge resources slightly.
        return base + max(0, base / 10)
    }

    /// Apply mutual exclusions when toggling a rule on.
    public static func enabling(_ rule: HouseRuleID, into rules: inout HouseRules) {
        rules.enable(rule)
        switch rule {
        case .karmaGeneration:
            // Karmagen replaces priority / sum-to-ten columns.
            rules.disable(.sumToTen)
        case .sumToTen:
            rules.disable(.karmaGeneration)
        case .qualityBudgetAdjustment:
            if rules.positiveQualityKarmaCap == nil {
                rules.positiveQualityKarmaCap = 35
            }
        case .bonusStartingKarma:
            if rules.bonusKarma <= 0 { rules.bonusKarma = 25 }
        case .primeRunnerPackage:
            if rules.bonusKarma < 50 { rules.bonusKarma = 50 }
            if rules.extraContactPoints < 6 { rules.extraContactPoints = 6 }
            rules.enable(.expandedContacts)
            if rules.positiveQualityKarmaCap == nil || (rules.positiveQualityKarmaCap ?? 0) < 40 {
                rules.positiveQualityKarmaCap = 40
            }
            rules.enable(.qualityBudgetAdjustment)
        case .expandedContacts:
            if rules.extraContactPoints <= 0 { rules.extraContactPoints = 3 }
        case .freeKnowledgeSkills:
            // 0 means auto (LOG+INT)×2
            break
        case .essenceCostRounding, .exceptionalAttributeAtChargen, .alternateAttributeCosts:
            break
        }
    }

    public static func disabling(_ rule: HouseRuleID, into rules: inout HouseRules) {
        rules.disable(rule)
    }

    /// Human-readable list of active mechanical effects.
    public static func effectSummary(for houseRules: HouseRules, editionBaselineKarma: Int) -> [String] {
        var lines: [String] = []
        if houseRules.enabled.isEmpty {
            return ["Core book only — no house rules."]
        }
        for id in HouseRuleID.allCases where houseRules.isEnabled(id) {
            lines.append("• \(id.displayName): \(id.mechanicalEffect(houseRules))")
        }
        let karma = startingKarma(editionBaseline: editionBaselineKarma, houseRules: houseRules)
        if karma != editionBaselineKarma {
            lines.append("• Starting karma total: \(karma) (baseline \(editionBaselineKarma))")
        }
        return lines
    }
}

public extension HouseRuleID {
    /// Longer copy for the house-rules catalog browser.
    var detailDescription: String {
        switch self {
        case .sumToTen:
            return """
            Instead of assigning each priority letter (A–E) once, you assign values so A=4, B=3, C=2, D=1, E=0 and the five columns sum to exactly 10. Duplicate letters are allowed (e.g. two B’s). Common “street-level flexibility” rule from Runner’s Companion-era tables.
            """
        case .karmaGeneration:
            return """
            Build the entire character with a karma budget (default 750, or your campaign number) instead of priority columns or build points. Mutually exclusive with Sum-to-Ten / classic priority letter assignment in ShadowDeck.
            """
        case .bonusStartingKarma:
            return """
            After generation, grant extra unspent karma (default +25) for post-gen touches—qualities, skill bumps, or gear. Stacks with edition leftover karma (e.g. SR5’s 25).
            """
        case .freeKnowledgeSkills:
            return """
            Grant free Knowledge and Language ranks at chargen that do not spend active skill points. When the point field is 0, ShadowDeck uses (Logic + Intuition) × 2 — the SR5 free-knowledge formula—as the free pool.
            """
        case .expandedContacts:
            return """
            Core contact points are typically Charisma × 3. This rule adds extra contact points (default +3) so faces and connected runners can start with a deeper network without starving other builds.
            """
        case .exceptionalAttributeAtChargen:
            return """
            Allows Exceptional Attribute / Lucky-style maximum bumps during creation. In ShadowDeck this raises the chargen natural max by +1 and the play-sheet augmented ceiling by +1 so permanent augs + exceptional still validate.
            """
        case .essenceCostRounding:
            return """
            Round each augmentation’s essence cost down to the configured step (default 0.1) before summing, slightly favoring chrome-heavy builds. Applied by the essence calculator and reflected on Summary Essence.
            """
        case .qualityBudgetAdjustment:
            return """
            Raise or lower the positive quality karma cap above the edition default (SR5 core is 25). ShadowDeck default when enabled is 35 unless you set another value. Negative quality caps stay edition-default unless you extend later.
            """
        case .primeRunnerPackage:
            return """
            Higher-powered “prime runner” table: extra starting karma (default 50), expanded contacts, higher quality budget, and a modest resources bump (+10% nuyen). Enables related convenience rules so the package stays coherent.
            """
        case .alternateAttributeCosts:
            return """
            Use simplified (often linear) karma costs when raising attributes after chargen, instead of progressive new-rating × N tables. Chargen point pools are unchanged; post-gen advancement is cheaper/clearer for long campaigns.
            """
        }
    }

    var categoryLabel: String {
        switch self {
        case .sumToTen, .karmaGeneration:
            return "Generation system"
        case .bonusStartingKarma, .primeRunnerPackage, .qualityBudgetAdjustment:
            return "Budgets & power level"
        case .freeKnowledgeSkills, .expandedContacts:
            return "Skills & contacts"
        case .exceptionalAttributeAtChargen, .alternateAttributeCosts:
            return "Attributes"
        case .essenceCostRounding:
            return "Augmentations"
        }
    }

    func mechanicalEffect(_ rules: HouseRules) -> String {
        switch self {
        case .sumToTen:
            return "Priority letters sum to 10; duplicates allowed"
        case .karmaGeneration:
            return "Karma budget \(rules.karmaGenBudget) instead of priority"
        case .bonusStartingKarma:
            return "+\(rules.bonusKarma) starting karma"
        case .freeKnowledgeSkills:
            if rules.freeKnowledgePoints > 0 {
                return "\(rules.freeKnowledgePoints) free knowledge ranks"
            }
            return "Free knowledge = (LOG+INT)×2"
        case .expandedContacts:
            return "CHA×3 contacts +\(rules.extraContactPoints) points"
        case .exceptionalAttributeAtChargen:
            return "Natural max +1; augmented ceiling +1"
        case .essenceCostRounding:
            return "Essence costs round down to \(rules.essenceRoundingStep)"
        case .qualityBudgetAdjustment:
            return "Positive quality cap \(rules.positiveQualityKarmaCap.map(String.init) ?? "edition default")"
        case .primeRunnerPackage:
            return "+\(rules.bonusKarma) karma, contacts, quality cap, +10% nuyen"
        case .alternateAttributeCosts:
            return "Linear-style post-gen attribute karma costs"
        }
    }
}
