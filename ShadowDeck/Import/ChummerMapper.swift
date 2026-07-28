//
//  ChummerMapper.swift
//  ShadowDeck
//
//  Maps normalized Chummer data into ShadowDeck domain Character.
//

import Foundation

public enum ChummerMapper {
    public static func mapToCharacter(
        _ source: ChummerNormalizedCharacter,
        diagnostics: inout ImportDiagnostics
    ) -> Character {
        let edition = mapEdition(source.gameEdition, diagnostics: &diagnostics)
        let metatype = mapMetatype(source.metatype, diagnostics: &diagnostics)
        let awakened = mapAwakened(source, diagnostics: &diagnostics)
        let attributes = mapAttributes(source.attributes, essence: source.essenceTotal, diagnostics: &diagnostics)
        let generation = mapGeneration(source, edition: edition, diagnostics: &diagnostics)

        let skills = source.skills.map { skill in
            let category: SkillCategory
            if skill.isLanguage {
                category = .language
            } else if skill.isKnowledge {
                category = .knowledge
            } else {
                category = .active
            }
            return SkillRating(
                catalogKey: ChummerParsingHelpers.catalogKey(from: skill.name),
                displayName: skill.name,
                category: category,
                rating: skill.rating,
                specialized: skill.specialized,
                group: mapSkillGroup(skill.skillGroup),
                knowledgeType: skill.category
            )
        }

        if skills.isEmpty {
            diagnostics.warn("skills.empty", "No trained skills were found in the Chummer file.")
        }

        let skillGroups: [SkillGroupRating] = source.skillGroups.compactMap { g in
            guard let id = mapSkillGroup(g.name) else { return nil }
            return SkillGroupRating(group: id, rating: g.rating)
        }

        let qualities = source.qualities.map { q in
            QualityInstance(
                catalogKey: ChummerParsingHelpers.catalogKey(from: q.name),
                name: q.name,
                kind: q.isPositive ? .positive : .negative,
                karmaValue: q.karma,
                notes: q.source.map { "Source: \($0)" } ?? "",
                modifiers: CatalogLookup.modifiers(named: q.name)
            )
        }

        let augmentations: [Augmentation] =
            source.cyberware.map { mapAug($0) } + source.bioware.map { mapAug($0) }

        var gear: [GearItem] = []
        gear += source.gear.map { mapGearItem($0, defaultCategory: .other) }
        gear += source.weapons.map { mapGearItem($0, defaultCategory: .weapon) }
        gear += source.armors.map { mapGearItem($0, defaultCategory: .armor) }

        let powers = source.powers.map {
            AdeptPowerInstance(
                catalogKey: ChummerParsingHelpers.catalogKey(from: $0.name),
                name: $0.name,
                level: $0.rating,
                powerPointCost: $0.pointCost,
                modifiers: CatalogLookup.modifiers(named: $0.name)
            )
        }

        let spells = source.spells.map {
            SpellInstance(
                catalogKey: ChummerParsingHelpers.catalogKey(from: $0.name),
                name: $0.name,
                category: $0.category
            )
        }

        let complexForms = source.complexForms.map {
            ComplexFormInstance(
                catalogKey: ChummerParsingHelpers.catalogKey(from: $0.name),
                name: $0.name
            )
        }

        let contacts = source.contacts.map {
            Contact(
                name: $0.name,
                role: $0.role,
                loyalty: $0.loyalty,
                connection: $0.connection,
                notes: $0.notes,
                contactType: Self.optionalText($0.contactType),
                metatype: Self.optionalText($0.metatype),
                gender: Self.optionalText($0.gender),
                age: Self.optionalText($0.age),
                location: Self.optionalText($0.location),
                preferredPayment: Self.optionalText($0.preferredPayment),
                hobbiesVice: Self.optionalText($0.hobbiesVice),
                personalLife: Self.optionalText($0.personalLife)
            )
        }

        let lifestyles = source.lifestyles.map {
            Lifestyle(
                name: $0.name,
                level: mapLifestyleLevel($0.level),
                monthlyCost: $0.monthlyCost,
                monthsPrepaid: $0.monthsPrepaid
            )
        }

        // Story vs session notes:
        // - background → Character.background (story-mode blurb)
        // - description (if not already in background) may fold into story
        // - notes / gamenotes → Character.notes (mission logs, table notes)
        var storyParts: [String] = []
        if !source.background.isEmpty { storyParts.append(source.background) }
        if !source.description.isEmpty,
           !storyParts.contains(where: { $0.caseInsensitiveCompare(source.description) == .orderedSame })
        {
            // Chummer “description” is often a short GM note; append if distinct.
            storyParts.append(source.description)
        }
        let storyBackground = storyParts.joined(separator: "\n\n")

        var notesParts: [String] = []
        if !source.notes.isEmpty { notesParts.append(source.notes) }
        if !source.gender.isEmpty || !source.age.isEmpty {
            notesParts.append([source.gender, source.age].filter { !$0.isEmpty }.joined(separator: ", "))
        }
        if !source.playerName.isEmpty {
            notesParts.append("Player: \(source.playerName)")
        }
        notesParts.append(
            "Imported from Chummer (\(source.gameEdition.isEmpty ? "SR?" : source.gameEdition), \(source.buildMethod.isEmpty ? "unknown build" : source.buildMethod))."
        )

        let nuyenInt = NSDecimalNumber(decimal: source.nuyen).intValue

        var character = Character(
            name: source.name.isEmpty ? (source.alias.isEmpty ? "Imported Runner" : source.alias) : source.name,
            streetName: source.alias,
            concept: source.concept,
            background: storyBackground.isEmpty ? nil : storyBackground,
            notes: notesParts.joined(separator: "\n\n"),
            edition: edition,
            metatype: metatype,
            awakened: awakened,
            generation: generation,
            houseRules: .coreBook,
            attributes: attributes,
            skills: skills,
            skillGroups: skillGroups,
            qualities: qualities,
            gear: gear,
            augmentations: augmentations,
            spells: spells,
            adeptPowers: powers,
            complexForms: complexForms,
            lifestyles: lifestyles,
            contacts: contacts,
            karmaTotal: source.karmaTotal,
            karmaAvailable: source.karmaAvailable,
            nuyen: nuyenInt,
            conditionTrack: ConditionTrack(
                physicalDamage: source.physicalDamage,
                stunDamage: source.stunDamage
            )
        )

        // Prefer Chummer-reported essence when present.
        if let essence = source.essenceTotal, essence > 0 {
            character.attributes.essence = essence
        } else if !augmentations.isEmpty {
            let rules = RulesRegistry.rules(for: edition)
            character.attributes.essence = rules.computeEssence(for: character)
            diagnostics.info("essence.recomputed", "Essence recomputed from augmentations.")
        }

        // Soft-validate after map. Campaign imports are play sheets, not pure chargen drafts:
        // chargen-budget style codes become informational only.
        let validation = RulesRegistry.rules(for: edition).validate(character)
        for issue in validation.issues {
            let code = "validation.\(issue.code)"
            if Self.chargenOnlyValidationCodes.contains(issue.code) {
                diagnostics.info(code, "Chargen note (not enforced on import): \(issue.message)")
            } else if issue.severity == .error {
                diagnostics.warn(code, "Post-import check: \(issue.message)")
            } else {
                diagnostics.info(code, issue.message)
            }
        }

        return character
    }

    /// Codes that matter at generation time but should not block or alarm campaign imports.
    private static let chargenOnlyValidationCodes: Set<String> = [
        "qualities.positive_cap",
        "priority.incomplete",
        "priority.unique",
        "priority.sum_to_ten",
        "bp.budget",
        "bp.overspent",
        "karma.overspent",
    ]

    // MARK: - Field mappers

    private static func mapEdition(_ raw: String, diagnostics: inout ImportDiagnostics) -> Edition {
        let t = raw.uppercased().replacingOccurrences(of: " ", with: "")
        switch t {
        case "SR4", "SR4A", "4", "4A", "FOURTH":
            return .sr4
        case "SR5", "5", "FIFTH":
            return .sr5
        case "SR6", "6", "SIXTH", "6E", "SIXTHWORLD":
            return .sr6
        default:
            diagnostics.warn("edition.unknown", "Unknown game edition “\(raw)”; defaulting to SR5.")
            return .sr5
        }
    }

    private static func mapMetatype(_ raw: String, diagnostics: inout ImportDiagnostics) -> MetatypeID {
        let t = raw.lowercased()
        if t.contains("elf") { return .elf }
        if t.contains("dwarf") { return .dwarf }
        if t.contains("ork") || t.contains("orc") { return .ork }
        if t.contains("troll") { return .troll }
        if t.contains("human") { return .human }
        diagnostics.warn("metatype.unknown", "Unknown metatype “\(raw)”; defaulting to Human.")
        return .human
    }

    private static func mapAwakened(
        _ source: ChummerNormalizedCharacter,
        diagnostics: inout ImportDiagnostics
    ) -> AwakenedPath {
        if source.isMysticAdept { return .mysticAdept }
        if source.isTechnomancer { return .technomancer }
        if source.isAdept && source.isMagician {
            diagnostics.info("awakened.mystic_inferred", "Both adept and magician flags set; treating as Mystic Adept.")
            return .mysticAdept
        }
        if source.isAdept { return .adept }
        if source.isMagician {
            if source.qualities.contains(where: { $0.name.localizedCaseInsensitiveContains("Aspected") }) {
                return .aspectedMagician
            }
            return .fullMagician
        }
        // Resonance/Magic attributes as fallback.
        if source.attributes.contains(where: { $0.name.uppercased().hasPrefix("RES") && $0.total > 0 }) {
            return .technomancer
        }
        if source.attributes.contains(where: { $0.name.uppercased().hasPrefix("MAG") && $0.total > 0 }) {
            return source.powers.isEmpty ? .fullMagician : .adept
        }
        return .mundane
    }

    private static func mapAttributes(
        _ list: [ChummerNormalizedAttribute],
        essence: Decimal?,
        diagnostics: inout ImportDiagnostics
    ) -> AttributeRatings {
        var ratings = AttributeRatings()
        if list.isEmpty {
            diagnostics.warn("attributes.empty", "No attributes found; using metatype defaults (all 1s / essence 6).")
            return ratings
        }

        func value(for names: [String]) -> Int? {
            for attr in list {
                let n = attr.name.uppercased()
                if names.contains(n) {
                    // Prefer base so CharacterEffectsEngine can re-apply aug/quality/gear
                    // modifiers without double-counting Chummer totals.
                    if attr.base > 0 { return attr.base }
                    if attr.total > 0 { return attr.total }
                    return nil
                }
            }
            return nil
        }

        if let v = value(for: ["BOD", "BODY"]) { ratings.body = v }
        if let v = value(for: ["AGI", "AGILITY"]) { ratings.agility = v }
        if let v = value(for: ["REA", "REACTION"]) { ratings.reaction = v }
        if let v = value(for: ["STR", "STRENGTH"]) { ratings.strength = v }
        if let v = value(for: ["WIL", "WILLPOWER"]) { ratings.willpower = v }
        if let v = value(for: ["LOG", "LOGIC"]) { ratings.logic = v }
        if let v = value(for: ["INT", "INTUITION"]) { ratings.intuition = v }
        if let v = value(for: ["CHA", "CHARISMA"]) { ratings.charisma = v }
        if let v = value(for: ["EDG", "EDGE"]) { ratings.edge = v }
        if let v = value(for: ["MAG", "MAGIC"]) { ratings.magic = v }
        if let v = value(for: ["RES", "RESONANCE"]) { ratings.resonance = v }

        if let essence, essence > 0 {
            ratings.essence = essence
        } else if let ess = value(for: ["ESS", "ESSENCE"]), ess > 0, ess <= 6 {
            // Chummer sometimes stores remaining essence oddly; only trust sane values.
            ratings.essence = Decimal(ess)
        }

        return ratings
    }

    private static func mapGeneration(
        _ source: ChummerNormalizedCharacter,
        edition: Edition,
        diagnostics: inout ImportDiagnostics
    ) -> GenerationProfile {
        let method = source.buildMethod.lowercased()
        let system: GenerationSystem
        if method.contains("sum") && method.contains("ten") {
            system = .sumToTen
        } else if method.contains("karma") {
            system = .karmaGen
        } else if method.contains("priority") {
            system = .priority
        } else if method.contains("bp") || method.contains("build point") {
            system = .buildPoints
        } else {
            system = edition.usesPriorityGenerationByDefault ? .priority : .buildPoints
            if !source.buildMethod.isEmpty {
                diagnostics.info(
                    "generation.defaulted",
                    "Build method “\(source.buildMethod)” mapped to \(system.displayName)."
                )
            }
        }

        var assignment = PriorityAssignment()
        func apply(_ raw: String?, column: PriorityColumn) {
            guard let raw, let letter = PriorityLetter(rawValue: raw.uppercased()) else { return }
            assignment[column] = letter
        }
        apply(source.priorityMetatype, column: .metatype)
        apply(source.priorityAttributes, column: .attributes)
        apply(source.prioritySpecial, column: .magicOrResonance)
        apply(source.prioritySkills, column: .skills)
        apply(source.priorityResources, column: .resources)

        let rules = RulesRegistry.rules(for: edition)
        return GenerationProfile(
            system: system,
            priority: assignment,
            buildPointBudget: system == .buildPoints ? rules.standardBuildPointBudget : 0,
            karmaBudget: source.karmaTotal,
            karmaSpent: max(0, source.karmaTotal - source.karmaAvailable),
            nuyenBudget: NSDecimalNumber(decimal: source.nuyen).intValue,
            nuyenSpent: 0,
            isFinished: true
        )
    }

    private static func mapSkillGroup(_ name: String?) -> SkillGroupID? {
        guard let name else { return nil }
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        switch key {
        case "athletics": return .athletics
        case "biotech": return .biotech
        case "closecombat": return .closeCombat
        case "conjuring": return .conjuring
        case "cracking": return .cracking
        case "electronics": return .electronics
        case "enchanting": return .enchanting
        case "firearms": return .fireArarms
        case "influence": return .influence
        case "engineering": return .engineering
        case "outdoors": return .outdoors
        case "perception": return .perception
        case "piloting", "pilot": return .piloting
        case "sorcery": return .sorcery
        case "stealth": return .stealth
        case "tasking": return .tasking
        default: return nil
        }
    }

    private static func mapAug(_ a: ChummerNormalizedAugmentation) -> Augmentation {
        Augmentation(
            catalogKey: ChummerParsingHelpers.catalogKey(from: a.name),
            name: a.name,
            kind: a.isBioware ? .bioware : .cyberware,
            grade: mapGrade(a.grade),
            rating: a.rating,
            essenceCost: a.essence,
            notes: a.notes,
            modifiers: CatalogLookup.modifiers(named: a.name)
        )
    }

    private static func mapGrade(_ raw: String) -> AugmentationGrade {
        switch raw.lowercased() {
        case "alphaware", "alpha": return .alphaware
        case "betaware", "beta": return .betaware
        case "deltaware", "delta": return .deltaware
        case "used": return .used
        default: return .standard
        }
    }

    private static func optionalText(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func mapGearItem(_ g: ChummerNormalizedGear, defaultCategory: GearCategory) -> GearItem {
        let category: GearCategory
        if !g.category.isEmpty {
            let inferred = GearCategory.infer(from: g.category)
            category = (inferred == .other && defaultCategory != .other) ? defaultCategory : inferred
        } else {
            category = defaultCategory
        }
        return GearItem(
            catalogKey: ChummerParsingHelpers.catalogKey(from: g.name),
            name: g.name,
            category: category,
            quantity: g.quantity,
            nuyenCost: g.cost,
            equipped: g.equipped,
            notes: g.notes,
            armorRating: g.armorRating,
            damageCode: g.damageCode,
            subcategory: optionalText(g.category),
            modifiers: CatalogLookup.modifiers(named: g.name)
        )
    }

    private static func mapLifestyleLevel(_ raw: String) -> LifestyleLevel {
        switch raw.lowercased() {
        case "street": return .street
        case "squatter": return .squatter
        case "low": return .low
        case "middle", "medium": return .middle
        case "high": return .high
        case "luxury": return .luxury
        default: return .low
        }
    }
}
