//
//  AdvancementGuidance.swift
//  ShadowDeck
//
//  Player-facing “what this raise changes” summaries for the Advancement Planner.
//  Uses live character derived stats so guidance reflects current state.
//

import Foundation

public struct AdvancementImpact: Sendable, Hashable {
    /// One-line hint under a raise row.
    public var headline: String
    /// Longer text for tooltips / accessibility.
    public var detail: String

    public init(headline: String, detail: String) {
        self.headline = headline
        self.detail = detail
    }
}

public enum AdvancementGuidance {
    // MARK: - Public API

    public static func impact(
        for preview: AdvancementRaisePreview,
        character: Character,
        rules: any EditionRules
    ) -> AdvancementImpact? {
        switch preview.kind {
        case .attributeRaise:
            guard let attr = AttributeID(rawValue: preview.targetKey) else { return nil }
            return attributeImpact(character: character, attribute: attr, rules: rules)
        case .skillRaise:
            guard let skill = character.skills.first(where: { $0.catalogKey == preview.targetKey }) else {
                return nil
            }
            return skillImpact(character: character, skill: skill, rules: rules)
        case .newSkill:
            return newSkillImpact(preview: preview, character: character, rules: rules)
        case .other, .runAward:
            return nil
        }
    }

    public static func attributeImpact(
        character: Character,
        attribute: AttributeID,
        rules: any EditionRules
    ) -> AdvancementImpact {
        let before = playStats(character: character, rules: rules)
        var raised = character
        raised.attributes[attribute] = character.attributes[attribute] + 1
        let after = playStats(character: raised, rules: rules)

        var deltas: [String] = []

        // Condition monitors
        if before.condition.physicalBoxes != after.condition.physicalBoxes {
            deltas.append(
                "Physical boxes \(before.condition.physicalBoxes) → \(after.condition.physicalBoxes)"
            )
        }
        if before.condition.stunBoxes != after.condition.stunBoxes {
            deltas.append(
                "Stun boxes \(before.condition.stunBoxes) → \(after.condition.stunBoxes)"
            )
        }

        // Initiative
        if before.initiativeBase != after.initiativeBase {
            deltas.append("Initiative \(before.initiativeBase) → \(after.initiativeBase)")
        }

        // Limits (edition-dependent)
        if let bp = before.physicalLimit, let ap = after.physicalLimit, bp != ap {
            deltas.append("Physical limit \(bp) → \(ap)")
        }
        if let bm = before.mentalLimit, let am = after.mentalLimit, bm != am {
            deltas.append("Mental limit \(bm) → \(am)")
        }
        if let bs = before.socialLimit, let as_ = after.socialLimit, bs != as_ {
            deltas.append("Social limit \(bs) → \(as_)")
        }

        // Social / mental secondaries
        if before.composure != after.composure {
            deltas.append("Composure \(before.composure) → \(after.composure)")
        }
        if before.judgeIntentions != after.judgeIntentions {
            deltas.append("Judge Intentions \(before.judgeIntentions) → \(after.judgeIntentions)")
        }
        if before.memory != after.memory {
            deltas.append("Memory \(before.memory) → \(after.memory)")
        }
        if before.liftCarry != after.liftCarry {
            deltas.append("Lift/Carry \(before.liftCarry) → \(after.liftCarry) kg")
        }
        if before.movementWalk != after.movementWalk || before.movementRun != after.movementRun {
            deltas.append(
                "Walk/Run \(before.movementWalk)/\(before.movementRun) → \(after.movementWalk)/\(after.movementRun)"
            )
        }
        if before.magicOrResonanceEffective != after.magicOrResonanceEffective {
            let label = character.awakened.usesResonance ? "Resonance" : "Magic"
            deltas.append(
                "\(label) effective \(before.magicOrResonanceEffective) → \(after.magicOrResonanceEffective)"
            )
        }

        // Skill pools that increase because of this attribute
        let poolBoosts = skillPoolBoosts(before: before, after: after, character: character)
        if !poolBoosts.isEmpty {
            let names = poolBoosts.prefix(4).map(\.name)
            let more = poolBoosts.count > 4 ? " +\(poolBoosts.count - 4) more" : ""
            deltas.append(
                "\(poolBoosts.count) skill pool\(poolBoosts.count == 1 ? "" : "s") +1 (\(names.joined(separator: ", "))\(more))"
            )
        }

        let influences = ChargenHelpCatalog.attributeInfluences(attribute)
        let description = ChargenHelpCatalog.attributeDescription(attribute)

        let headline: String
        if deltas.isEmpty {
            headline = influences
        } else if deltas.count <= 2 {
            headline = deltas.joined(separator: " · ")
        } else {
            headline = deltas.prefix(2).joined(separator: " · ") + " · +\(deltas.count - 2) more"
        }

        var detailParts = [description, "Affects: \(influences)"]
        if !deltas.isEmpty {
            detailParts.append("If raised to \(character.attributes[attribute] + 1):\n• " + deltas.joined(separator: "\n• "))
        }
        if !poolBoosts.isEmpty {
            let lines = poolBoosts.prefix(8).map { "\($0.name) pool \($0.from) → \($0.to)" }
            detailParts.append("Skill pools:\n• " + lines.joined(separator: "\n• "))
        }

        return AdvancementImpact(headline: headline, detail: detailParts.joined(separator: "\n\n"))
    }

    public static func skillImpact(
        character: Character,
        skill: SkillRating,
        rules: any EditionRules
    ) -> AdvancementImpact {
        let linkedID = linkedAttributeID(for: skill)
        let linkedValue = character.attributes[linkedID]
        let before = playStats(character: character, rules: rules)
        var raised = character
        if let idx = raised.skills.firstIndex(where: { $0.catalogKey == skill.catalogKey }) {
            raised.skills[idx].rating = skill.rating + 1
        }
        let after = playStats(character: raised, rules: rules)

        let poolBefore = before.dicePools[skill.catalogKey]
            ?? (linkedValue + max(0, skill.rating))
        let poolAfter = after.dicePools[skill.catalogKey]
            ?? (linkedValue + skill.rating + 1)

        let description = ChargenHelpCatalog.skillDescription(catalogKey: skill.catalogKey)
        let categoryNote: String
        switch skill.category {
        case .active:
            categoryNote = "Active skill"
        case .knowledge:
            categoryNote = "Knowledge skill"
        case .language:
            categoryNote = "Language skill"
        }

        let headline = "Pool \(poolBefore) → \(poolAfter) (\(linkedID.displayName) \(linkedValue) + rank)"
        let detail = """
        \(description)

        \(categoryNote). Dice pool uses \(linkedID.displayName) (\(linkedValue)) + skill rank.
        Raising \(skill.displayName) \(skill.rating) → \(skill.rating + 1) changes the pool \(poolBefore) → \(poolAfter).
        """
        return AdvancementImpact(headline: headline, detail: detail)
    }

    public static func newSkillImpact(
        preview: AdvancementRaisePreview,
        character: Character,
        rules: any EditionRules
    ) -> AdvancementImpact {
        let category = preview.skillCategory ?? .active
        let linkedID: AttributeID
        switch category {
        case .active: linkedID = .reaction // default; real link depends on skill name
        case .knowledge: linkedID = .intuition
        case .language: linkedID = .intuition
        }
        // Prefer catalog-based description when we can.
        let description = ChargenHelpCatalog.skillDescription(catalogKey: preview.targetKey)
        let linkedValue = character.attributes[linkedID]
        let pool = linkedValue + 1
        let headline = "New rank 1 · ~pool \(pool)+ (linked attr varies by skill)"
        let detail = """
        \(description)

        Buying \(preview.displayName) at rank 1 adds a trained skill. Dice pools use a linked attribute + rank (typically \(linkedID.displayName) for this category; exact link depends on the skill).
        """
        return AdvancementImpact(headline: headline, detail: detail)
    }

    // MARK: - Helpers

    private static func playStats(character: Character, rules: any EditionRules) -> DerivedStats {
        let base = rules.deriveStats(for: character)
        return CharacterEffectsEngine.playStats(for: character, baseDerived: base)
    }

    private struct PoolBoost: Sendable {
        var name: String
        var from: Int
        var to: Int
    }

    private static func skillPoolBoosts(
        before: DerivedStats,
        after: DerivedStats,
        character: Character
    ) -> [PoolBoost] {
        var boosts: [PoolBoost] = []
        let keys = Set(before.dicePools.keys).union(after.dicePools.keys)
        for key in keys.sorted() {
            let b = before.dicePools[key] ?? 0
            let a = after.dicePools[key] ?? 0
            guard a > b else { continue }
            let name = character.skills.first(where: { $0.catalogKey == key })?.displayName ?? key
            boosts.append(PoolBoost(name: name, from: b, to: a))
        }
        // Prefer larger swings first, then name
        return boosts.sorted {
            if ($0.to - $0.from) != ($1.to - $1.from) {
                return ($0.to - $0.from) > ($1.to - $1.from)
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Mirrors CharacterEffectsEngine linked-attribute mapping for display labels.
    public static func linkedAttributeID(for skill: SkillRating) -> AttributeID {
        if skill.category == .knowledge || skill.category == .language {
            return knowledgeLinkedAttributeID(skill: skill)
        }

        let key = skill.catalogKey.lowercased()
        let name = skill.displayName.lowercased()
        let blob = key + " " + name
        if blob.contains("pistol") || blob.contains("automatic") || blob.contains("longarm")
            || blob.contains("heavy_weapon") || blob.contains("sneak") || blob.contains("gym")
            || blob.contains("escape") || blob.contains("lock") || blob.contains("palming")
            || blob.contains("disguise") || blob.contains("imperson")
        {
            return .agility
        }
        if blob.contains("unarmed") || blob.contains("blade") || blob.contains("club")
            || blob.contains("throw") || blob.contains("swim") || blob.contains("run")
            || blob.contains("athlet")
        {
            return .strength
        }
        if blob.contains("hack") || blob.contains("computer") || blob.contains("software")
            || blob.contains("cybercombat") || blob.contains("electronic") || blob.contains("hardware")
            || blob.contains("arcana") || blob.contains("aeronautics") || blob.contains("industrial")
            || blob.contains("mechanic") || blob.contains("armorer") || blob.contains("first_aid")
            || blob.contains("medicine")
        {
            return .logic
        }
        if blob.contains("perception") || blob.contains("assense") || blob.contains("track")
            || blob.contains("navigation") || blob.contains("survival") || blob.contains("artisa")
        {
            return .intuition
        }
        if blob.contains("con") || blob.contains("etiquette") || blob.contains("negotiation")
            || blob.contains("leadership") || blob.contains("instruction") || blob.contains("intimidation")
            || blob.contains("performance")
        {
            return .charisma
        }
        if blob.contains("spellcasting") || blob.contains("counterspelling") || blob.contains("summoning")
            || blob.contains("binding") || blob.contains("banishing") || blob.contains("alchemy")
        {
            return .magic
        }
        if blob.contains("compiling") || blob.contains("registering") || blob.contains("decompiling") {
            return .resonance
        }
        if blob.contains("willpower") {
            return .willpower
        }
        // Piloting, vehicles, defense-ish defaults often Reaction-linked.
        return .reaction
    }

    private static func knowledgeLinkedAttributeID(skill: SkillRating) -> AttributeID {
        let type = (skill.knowledgeType ?? "").lowercased()
        if skill.category == .language
            || type.contains("language")
            || type.contains("street")
            || type.contains("interest")
        {
            return .intuition
        }
        if type.contains("academic") || type.contains("professional") {
            return .logic
        }
        let name = skill.displayName.lowercased() + " " + skill.catalogKey.lowercased()
        if name.contains("corp") || name.contains("science") || name.contains("history")
            || name.contains("matrix") || name.contains("magical") || name.contains("theory")
            || name.contains("academic")
        {
            return .logic
        }
        return .intuition
    }
}
