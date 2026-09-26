//
//  GenerationDraft+Recommendations.swift
//  ShadowDeck
//
//  User-triggered recommendations and skill-group / spell / contact helpers.
//  GenerationDraft remains the only draft type.
//

import Foundation

extension GenerationDraft {
    // MARK: - Recommendations (user-triggered)

    public func applyRecommendedPriorities() {
        let rec = ChargenRecommendations.priorities(archetype: archetype, metatype: metatype)
        priority = rec.assignment
        if houseRules.isEnabled(.sumToTen) {
            generationSystem = .sumToTen
        }
        recomputeBudgetsFromPriorities()
        lastRecommendationNote = rec.rationale
    }

    /// Attribute-point budget for recommendations (stable if reapplied).
    /// In BP mode, counts free BP as if physical/mental attributes were back at metatype minima
    /// so a second click does not shrink the budget by the spend of the first apply.
    /// **Pure** — must not mutate budget (called from SwiftUI view bodies for button subtitles).
    public var recommendedAttributePointBudget: Int {
        if generationSystem == .buildPoints {
            let ledger = buildPointLedger
            let total = budget.buildPointsTotal > 0
                ? budget.buildPointsTotal
                : SR4BuildPointEngine.defaultBudget
            let remaining = total - ledger.total
            let bpIfAttrsCleared = max(0, remaining) + ledger.attributes
            let freePoints = bpIfAttrsCleared / SR4BuildPointEngine.attributePointCost
            return min(20, freePoints)
        }
        return budget.attributePointsTotal
    }

    /// Active-skill rank budget for recommendations (stable if reapplied).
    /// **Pure** — must not mutate budget (called from SwiftUI view bodies).
    public var recommendedSkillPointBudget: Int {
        if generationSystem == .buildPoints {
            let ledger = buildPointLedger
            let total = budget.buildPointsTotal > 0
                ? budget.buildPointsTotal
                : SR4BuildPointEngine.defaultBudget
            let remaining = total - ledger.total
            let bpIfSkillsCleared = max(0, remaining) + ledger.skills
            let freeRanks = bpIfSkillsCleared / SR4BuildPointEngine.activeSkillRankCost
            return min(36, freeRanks)
        }
        return budget.skillPointsTotal
    }

    public func applyRecommendedAttributes() {
        // Keep ledger remaining current before applying (mutation only on user action).
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
        let pointBudget = recommendedAttributePointBudget
        let rec = ChargenRecommendations.attributes(
            archetype: archetype,
            metatype: metatype,
            edition: edition,
            pointBudget: pointBudget
        )
        resetAttributesToMinima()
        let profile = MetatypeCatalog.profile(for: metatype, edition: edition)
        for id in AttributeID.standardGenerationAttributes {
            let bounds = profile.bounds(for: id)
            let maxAllowed = HouseRulesEngine.naturalAttributeMaximum(
                metatypeMaximum: bounds.maximum,
                houseRules: houseRules
            )
            let target = rec.values[id] ?? bounds.minimum
            let clamped = Swift.min(maxAllowed, Swift.max(bounds.minimum, target))
            attributes[id] = clamped
            attributePurchases[id] = Swift.max(0, clamped - bounds.minimum)
        }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        } else {
            recomputeAttributeRemaining()
        }
        refreshHouseRulePools()
        lastRecommendationNote = rec.rationale
    }

    public func applyRecommendedSkills() {
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
        let pointBudget = recommendedSkillPointBudget
        skills.removeAll()
        skillRanks.removeAll()
        if generationSystem != .buildPoints {
            budget.skillPointsRemaining = budget.skillPointsTotal
            // Reset groups so recommend can re-spend the full group pool.
            skillGroupRatings.removeAll()
            budget.skillGroupPointsRemaining = budget.skillGroupPointsTotal
        }
        let rec = ChargenRecommendations.skills(archetype: archetype, pointBudget: pointBudget)
        let names = Dictionary(uniqueKeysWithValues: ChargenSkillCatalog.active.map { ($0.key, $0.name) })
        for (key, rank) in rec.ranks.sorted(by: { $0.key < $1.key }) {
            setSkillRank(catalogKey: key, displayName: names[key] ?? key, rank: rank)
        }
        if generationSystem != .buildPoints, budget.skillGroupPointsTotal > 0 {
            let groupRec = ChargenRecommendations.skillGroups(
                archetype: archetype,
                pointBudget: budget.skillGroupPointsTotal
            )
            for (group, rating) in groupRec.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                setSkillGroupRating(group, rating: rating)
            }
            recomputeSkillGroupRemaining()
        }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
        lastRecommendationNote = rec.rationale
    }

    /// Whether a quality can be toggled on under current caps / BP.
    public func canAddQuality(kind: QualityKind, karmaValue: Int) -> Bool {
        let cost = abs(karmaValue)
        if generationSystem == .buildPoints {
            let pos = qualities.filter { $0.kind == .positive }.reduce(0) { $0 + abs($1.karmaValue) }
            let neg = qualities.filter { $0.kind == .negative }.reduce(0) { $0 + abs($1.karmaValue) }
            let cap = 35
            switch kind {
            case .positive:
                guard pos + cost <= cap else { return false }
                return budget.buildPointsRemaining >= cost
            case .negative:
                return neg + cost <= cap
            }
        }
        switch kind {
        case .positive:
            return budget.positiveQualityKarmaUsed + cost <= budget.positiveQualityKarmaCap
        case .negative:
            return budget.negativeQualityKarmaGained + cost <= budget.negativeQualityKarmaCap
        }
    }

    public func setSkillRank(catalogKey: String, displayName: String, rank: Int, category: SkillCategory = .active) {
        let clamped = max(0, min(rank, 6))
        let previous = skillRanks[catalogKey] ?? 0
        let delta = clamped - previous
        guard delta != 0 else { return }

        if generationSystem == .buildPoints {
            let perRank = category == .active
                ? SR4BuildPointEngine.activeSkillRankCost
                : SR4BuildPointEngine.knowledgeSkillRankCost
            let bpDelta = delta * perRank
            if bpDelta > 0 {
                guard budget.buildPointsRemaining >= bpDelta else { return }
            }
            applySkillRankChange(
                catalogKey: catalogKey,
                displayName: displayName,
                clamped: clamped,
                category: category
            )
            recomputeBuildPoints()
            return
        }

        if delta > 0 {
            guard budget.skillPointsRemaining >= delta else { return }
            budget.skillPointsRemaining -= delta
        } else {
            budget.skillPointsRemaining -= delta // delta negative → add back
        }
        applySkillRankChange(
            catalogKey: catalogKey,
            displayName: displayName,
            clamped: clamped,
            category: category
        )
    }

    public func canIncreaseSkill(catalogKey: String) -> Bool {
        let current = skillRanks[catalogKey] ?? 0
        guard current < 6 else { return false }
        if generationSystem == .buildPoints {
            return budget.buildPointsRemaining >= SR4BuildPointEngine.activeSkillRankCost
        }
        return budget.skillPointsRemaining > 0
    }

    public func canDecreaseSkill(catalogKey: String) -> Bool {
        (skillRanks[catalogKey] ?? 0) > 0
    }

    // MARK: - Skill groups / spells / contacts

    /// Max skill group rating at chargen (SR4A BP: 4; priority SR5-style: 6).
    public var skillGroupMaxAtChargen: Int {
        generationSystem == .buildPoints ? SR4BuildPointEngine.skillGroupMaxAtChargen : 6
    }

    public func skillGroupRating(_ group: SkillGroupID) -> Int {
        skillGroupRatings[group] ?? 0
    }

    public func canIncreaseSkillGroup(_ group: SkillGroupID) -> Bool {
        let current = skillGroupRating(group)
        guard current < skillGroupMaxAtChargen else { return false }
        if generationSystem == .buildPoints {
            return budget.buildPointsRemaining >= SR4BuildPointEngine.skillGroupRankCost
        }
        // Priority (SR5): one skill-group point per rating rank.
        return budget.skillGroupPointsRemaining > 0
    }

    public func canDecreaseSkillGroup(_ group: SkillGroupID) -> Bool {
        skillGroupRating(group) > 0
    }

    public func setSkillGroupRating(_ group: SkillGroupID, rating: Int) {
        let clamped = max(0, min(rating, skillGroupMaxAtChargen))
        let previous = skillGroupRating(group)
        let delta = clamped - previous
        guard delta != 0 else { return }
        if generationSystem == .buildPoints {
            if delta > 0 {
                let need = delta * SR4BuildPointEngine.skillGroupRankCost
                guard budget.buildPointsRemaining >= need else { return }
            }
        } else {
            // Priority: spend/refund skill-group points 1:1 with rating.
            if delta > 0 {
                guard budget.skillGroupPointsRemaining >= delta else { return }
            }
        }
        if clamped == 0 {
            skillGroupRatings.removeValue(forKey: group)
        } else {
            skillGroupRatings[group] = clamped
        }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        } else {
            recomputeSkillGroupRemaining()
        }
    }

    public func canAddSpell() -> Bool {
        guard generationSystem == .buildPoints else { return true }
        guard awakened.usesMagic else { return false }
        guard spells.count < maxSpellsAtChargen else { return false }
        return budget.buildPointsRemaining >= SR4BuildPointEngine.spellCost
    }

    public func addSpell(_ spell: SpellInstance) {
        if generationSystem == .buildPoints {
            guard canAddSpell() else { return }
            guard !spells.contains(where: { $0.catalogKey == spell.catalogKey || $0.name == spell.name }) else {
                return
            }
        }
        spells.append(spell)
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func removeSpell(id: UUID) {
        spells.removeAll { $0.id == id }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func contactBPCost(_ contact: Contact) -> Int {
        SR4BuildPointEngine.contactCost(connection: contact.connection, loyalty: contact.loyalty)
    }

    public func canAddContact(connection: Int, loyalty: Int) -> Bool {
        guard generationSystem == .buildPoints else { return true }
        let cost = SR4BuildPointEngine.contactCost(connection: connection, loyalty: loyalty)
        return budget.buildPointsRemaining >= cost
    }

    public func addContact(_ contact: Contact) {
        if generationSystem == .buildPoints {
            guard canAddContact(connection: contact.connection, loyalty: contact.loyalty) else { return }
        }
        contacts.append(contact)
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func updateContact(_ contact: Contact) {
        guard let idx = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let previous = contacts[idx]
        if generationSystem == .buildPoints {
            let oldCost = contactBPCost(previous)
            let newCost = contactBPCost(contact)
            let free = budget.buildPointsRemaining + oldCost
            guard free >= newCost else { return }
        }
        contacts[idx] = contact
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func removeContact(id: UUID) {
        contacts.removeAll { $0.id == id }
        if generationSystem == .buildPoints {
            recomputeBuildPoints()
        }
    }

    public func buildCharacter() -> Character {
        let groupInstances = skillGroupRatings
            .filter { $0.value > 0 }
            .map { SkillGroupRating(group: $0.key, rating: $0.value) }
            .sorted { $0.group.rawValue < $1.group.rawValue }

        var character = Character(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            streetName: streetName.trimmingCharacters(in: .whitespacesAndNewlines),
            concept: concept.isEmpty ? archetype.displayName : concept,
            notes: notes,
            edition: edition,
            metatype: metatype,
            awakened: awakened,
            generation: GenerationProfile(
                system: generationSystem,
                priority: priority,
                buildPointBudget: budget.buildPointsTotal,
                buildPointsSpent: generationSystem == .buildPoints
                    ? buildPointLedger.total
                    : max(0, budget.buildPointsTotal - budget.buildPointsRemaining),
                karmaBudget: budget.karmaTotal,
                nuyenBudget: generationSystem == .buildPoints ? nuyen : budget.nuyenTotal,
                nuyenSpent: generationSystem == .buildPoints
                    ? nuyen
                    : max(0, budget.nuyenTotal - nuyen),
                attributePoints: budget.attributePointsTotal,
                specialAttributePoints: budget.specialPointsTotal,
                skillPoints: budget.skillPointsTotal,
                skillGroupPoints: generationSystem == .buildPoints
                    ? groupInstances.reduce(0) { $0 + $1.rating }
                    : budget.skillGroupPointsTotal,
                isFinished: true
            ),
            houseRules: houseRules,
            attributes: attributes,
            skills: skills.filter { $0.rating > 0 },
            skillGroups: groupInstances,
            qualities: qualities,
            spells: spells,
            contacts: contacts,
            karmaTotal: budget.karmaTotal,
            karmaAvailable: budget.karmaRemaining,
            nuyen: nuyen
        )
        if let avatarData {
            character.avatar.inlineData = avatarData
            character.avatar.mimeType = "image/png"
        }
        return character
    }

}
