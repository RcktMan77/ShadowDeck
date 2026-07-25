//
//  ChummerXMLParser.swift
//  ShadowDeck
//
//  Parses native Chummer `.chum5` XML character files.
//

import Foundation

public enum ChummerXMLParser {
    public static func parse(data: Data) throws -> ChummerNormalizedCharacter {
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let utf16 = String(data: data, encoding: .utf16) {
            text = utf16
        } else {
            throw ImportError.unreadableFile("Unable to decode XML text.")
        }
        // Strip BOM if present.
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let xmlData = Data(cleaned.utf8)

        let root: XMLElement
        do {
            let document = try XMLDocument(data: xmlData, options: [.documentTidyXML, .nodePreserveAll])
            guard let element = document.rootElement() else {
                throw ImportError.missingCharacterData
            }
            root = element
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.parseFailed(error.localizedDescription)
        }

        // Accept <character> or <characters><character>
        let characterElement: XMLElement
        if root.name == "character" {
            characterElement = root
        } else if root.name == "characters",
                  let first = root.elements(forName: "character").first
        {
            characterElement = first
        } else if let nested = root.elements(forName: "character").first {
            characterElement = nested
        } else {
            throw ImportError.missingCharacterData
        }

        return mapElement(characterElement)
    }

    private static func mapElement(_ c: XMLElement) -> ChummerNormalizedCharacter {
        let text = { (name: String) -> String in
            c.elements(forName: name).first?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let H = ChummerParsingHelpers.self

        let qualities = mapQualities(c)
        var isAdept = boolText(text("adept"))
        var isMagician = boolText(text("magician"))
        let isTechnomancer = boolText(text("technomancer"))
        let isMysticAdept = boolText(text("mysticadept"))
        if !isAdept && qualities.contains(where: { $0.name.caseInsensitiveCompare("Adept") == .orderedSame }) {
            isAdept = true
        }
        if !isMagician && qualities.contains(where: { $0.name.localizedCaseInsensitiveContains("Magician") }) {
            isMagician = true
        }

        let essenceText = text("totaless").isEmpty ? text("essence") : text("totaless")
        let essence = essenceText.isEmpty ? nil : H.decimalValue(essenceText)

        return ChummerNormalizedCharacter(
            name: text("name"),
            alias: text("alias"),
            metatype: text("metatype").isEmpty ? "Human" : text("metatype"),
            gameEdition: text("gameedition").isEmpty ? "SR5" : text("gameedition"),
            buildMethod: text("buildmethod"),
            playerName: text("playername"),
            concept: H.stripHTML(text("concept")),
            description: H.stripHTML(text("description")),
            background: H.stripHTML(text("background")),
            notes: H.stripHTML(text("notes").isEmpty ? text("gamenotes") : text("notes")),
            gender: text("gender"),
            age: text("age"),
            nuyen: H.decimalValue(text("nuyen")),
            karmaAvailable: H.intValue(text("karma")),
            karmaTotal: H.intValue(text("totalkarma"), default: H.intValue(text("karma"))),
            priorityMetatype: optionalLetter(text("prioritymetatype")),
            priorityAttributes: optionalLetter(text("priorityattributes")),
            prioritySpecial: optionalLetter(text("priorityspecial")),
            prioritySkills: firstPrioritySkillsLetter(c),
            priorityResources: optionalLetter(text("priorityresources")),
            isAdept: isAdept,
            isMagician: isMagician,
            isTechnomancer: isTechnomancer,
            isMysticAdept: isMysticAdept,
            attributes: mapAttributes(c),
            essenceTotal: essence,
            skills: mapSkills(c),
            skillGroups: mapSkillGroups(c),
            qualities: qualities,
            cyberware: mapAugmentations(c, parent: "cyberwares", child: "cyberware", bioware: false),
            bioware: mapAugmentations(c, parent: "biowares", child: "bioware", bioware: true),
            gear: mapGear(c, parent: "gears", child: "gear", category: "other"),
            weapons: mapGear(c, parent: "weapons", child: "weapon", category: "weapon"),
            armors: mapArmor(c),
            powers: mapPowers(c),
            spells: mapNamedItems(c, parent: "spells", child: "spell"),
            complexForms: mapNamedItems(c, parent: "complexforms", child: "complexform"),
            contacts: mapContacts(c),
            lifestyles: mapLifestyles(c)
        )
    }

    private static func optionalLetter(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard t.count == 1, ("A"..."E").contains(t) else { return t.isEmpty ? nil : t }
        return t
    }

    private static func firstPrioritySkillsLetter(_ c: XMLElement) -> String? {
        for el in c.elements(forName: "priorityskills") {
            if let v = optionalLetter(el.stringValue ?? "") { return v }
        }
        return nil
    }

    private static func boolText(_ s: String) -> Bool {
        ChummerParsingHelpers.boolValue(s)
    }

    private static func childText(_ element: XMLElement, _ name: String) -> String {
        element.elements(forName: name).first?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func mapAttributes(_ c: XMLElement) -> [ChummerNormalizedAttribute] {
        let H = ChummerParsingHelpers.self
        guard let container = c.elements(forName: "attributes").first else { return [] }
        return container.elements(forName: "attribute").compactMap { a in
            let name = childText(a, "name")
            guard !name.isEmpty else { return nil }
            let total = H.intValue(childText(a, "totalvalue").isEmpty ? childText(a, "total") : childText(a, "totalvalue"))
            let base = H.intValue(childText(a, "base"), default: total)
            let min = childText(a, "metatypemin")
            let max = childText(a, "metatypemax")
            return ChummerNormalizedAttribute(
                name: name,
                base: base,
                total: total == 0 ? base : total,
                metatypeMin: min.isEmpty ? nil : H.intValue(min),
                metatypeMax: max.isEmpty ? nil : H.intValue(max)
            )
        }
    }

    private static func mapSkills(_ c: XMLElement) -> [ChummerNormalizedSkill] {
        // Legacy: <skills><skill/>…</skills>
        // Chummer 5.2xx: <newskills><skills>…</skills><knoskills>…</knoskills></newskills>
        var collected: [(element: XMLElement, forceKnowledge: Bool)] = []

        if let legacy = c.elements(forName: "skills").first {
            for s in legacy.elements(forName: "skill") {
                collected.append((s, false))
            }
        }
        if let modern = c.elements(forName: "newskills").first {
            if let active = modern.elements(forName: "skills").first {
                for s in active.elements(forName: "skill") {
                    collected.append((s, false))
                }
            }
            if let knowledge = modern.elements(forName: "knoskills").first {
                for s in knowledge.elements(forName: "skill") {
                    collected.append((s, true))
                }
            }
            if let jack = modern.elements(forName: "skilljackknowledgeskills").first {
                for s in jack.elements(forName: "skill") {
                    collected.append((s, true))
                }
            }
        }

        let H = ChummerParsingHelpers.self
        var seen = Set<String>()
        return collected.compactMap { item -> ChummerNormalizedSkill? in
            let s = item.element
            let name = childText(s, "name")
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            let isKnowledge = item.forceKnowledge || boolText(childText(s, "knowledge"))
            let category = childText(s, "skillcategory")
            let isLanguage = category.localizedCaseInsensitiveContains("language")
            let rating = H.intValue(
                childText(s, "rating"),
                default: H.intValue(childText(s, "base")) + H.intValue(childText(s, "karma"))
            )
            if rating <= 0 || rating > 13 { return nil }
            let spec = childText(s, "spec")
            return ChummerNormalizedSkill(
                name: name,
                rating: rating,
                specialized: spec.isEmpty ? nil : spec,
                isKnowledge: isKnowledge,
                isLanguage: isLanguage,
                skillGroup: childText(s, "skillgroup").nilIfEmpty,
                category: category.nilIfEmpty,
                attribute: childText(s, "attribute").nilIfEmpty
            )
        }
    }

    private static func mapSkillGroups(_ c: XMLElement) -> [ChummerNormalizedSkillGroup] {
        let H = ChummerParsingHelpers.self
        var groups: [XMLElement] = []
        if let legacy = c.elements(forName: "skills").first {
            groups.append(contentsOf: legacy.elements(forName: "skillgroup"))
        }
        if let modern = c.elements(forName: "newskills").first {
            if let container = modern.elements(forName: "groups").first {
                groups.append(contentsOf: container.elements(forName: "skillgroup"))
                groups.append(contentsOf: container.elements(forName: "group"))
            }
            groups.append(contentsOf: modern.elements(forName: "skillgroup"))
        }
        return groups.compactMap { g in
            let name = childText(g, "name")
            let rating = H.intValue(childText(g, "rating").isEmpty ? childText(g, "base") : childText(g, "rating"))
            guard !name.isEmpty, rating > 0 else { return nil }
            return ChummerNormalizedSkillGroup(name: name, rating: rating)
        }
    }

    private static func mapQualities(_ c: XMLElement) -> [ChummerNormalizedQuality] {
        let H = ChummerParsingHelpers.self
        guard let container = c.elements(forName: "qualities").first else { return [] }
        return container.elements(forName: "quality").compactMap { q in
            let name = childText(q, "name")
            guard !name.isEmpty else { return nil }
            let type = childText(q, "qualitytype").isEmpty ? childText(q, "type") : childText(q, "qualitytype")
            let isPositive = type.lowercased().contains("positive") || type.isEmpty
            let karma = abs(H.intValue(childText(q, "karma").isEmpty ? childText(q, "bp") : childText(q, "karma")))
            return ChummerNormalizedQuality(
                name: name,
                karma: karma,
                isPositive: type.lowercased().contains("negative") ? false : isPositive,
                source: childText(q, "source").nilIfEmpty
            )
        }
    }

    private static func mapAugmentations(
        _ c: XMLElement,
        parent: String,
        child: String,
        bioware: Bool
    ) -> [ChummerNormalizedAugmentation] {
        let H = ChummerParsingHelpers.self
        guard let container = c.elements(forName: parent).first else { return [] }
        return container.elements(forName: child).compactMap { a in
            let name = childText(a, "name")
            guard !name.isEmpty else { return nil }
            let ess = H.decimalValue(childText(a, "ess").isEmpty ? childText(a, "essence") : childText(a, "ess"))
            let rating = H.intValue(childText(a, "rating"))
            return ChummerNormalizedAugmentation(
                name: name,
                essence: ess,
                grade: childText(a, "grade").isEmpty ? "Standard" : childText(a, "grade"),
                rating: rating > 0 ? rating : nil,
                isBioware: bioware,
                notes: H.stripHTML(childText(a, "notes"))
            )
        }
    }

    private static func mapGear(
        _ c: XMLElement,
        parent: String,
        child: String,
        category: String
    ) -> [ChummerNormalizedGear] {
        let H = ChummerParsingHelpers.self
        guard let container = c.elements(forName: parent).first else { return [] }
        return container.elements(forName: child).compactMap { g in
            let name = childText(g, "name")
            guard !name.isEmpty else { return nil }
            if name.localizedCaseInsensitiveContains("Unarmed Attack") { return nil }
            let qty = max(1, H.intValue(childText(g, "qty").isEmpty ? childText(g, "quantity") : childText(g, "qty"), default: 1))
            let cost = H.intValue(childText(g, "cost").isEmpty ? childText(g, "totalcost") : childText(g, "cost"))
            let damage = childText(g, "damage")
            return ChummerNormalizedGear(
                name: name,
                quantity: qty,
                cost: cost,
                category: category,
                damageCode: damage.isEmpty ? nil : damage,
                equipped: boolText(childText(g, "equipped")) || category == "weapon",
                notes: H.stripHTML(childText(g, "notes"))
            )
        }
    }

    private static func mapArmor(_ c: XMLElement) -> [ChummerNormalizedGear] {
        let H = ChummerParsingHelpers.self
        guard let container = c.elements(forName: "armors").first else { return [] }
        return container.elements(forName: "armor").compactMap { a in
            let name = childText(a, "name")
            guard !name.isEmpty else { return nil }
            let armorText = childText(a, "armor").isEmpty ? childText(a, "totalarmor") : childText(a, "armor")
            let armor = H.intValue(armorText)
            return ChummerNormalizedGear(
                name: name,
                quantity: 1,
                cost: H.intValue(childText(a, "cost")),
                category: "armor",
                armorRating: armor > 0 ? armor : nil,
                equipped: true,
                notes: H.stripHTML(childText(a, "notes"))
            )
        }
    }

    private static func mapPowers(_ c: XMLElement) -> [ChummerNormalizedPower] {
        let H = ChummerParsingHelpers.self
        guard let container = c.elements(forName: "powers").first else { return [] }
        return container.elements(forName: "power").compactMap { p in
            let name = childText(p, "name")
            guard !name.isEmpty else { return nil }
            let rating = max(1, H.intValue(childText(p, "rating").isEmpty ? childText(p, "total") : childText(p, "rating"), default: 1))
            let costText = childText(p, "totalpoints").isEmpty ? childText(p, "pointsperlevel") : childText(p, "totalpoints")
            return ChummerNormalizedPower(name: name, rating: rating, pointCost: H.decimalValue(costText))
        }
    }

    private static func mapNamedItems(_ c: XMLElement, parent: String, child: String) -> [ChummerNormalizedNamedItem] {
        guard let container = c.elements(forName: parent).first else { return [] }
        return container.elements(forName: child).compactMap { el in
            let name = childText(el, "name")
            guard !name.isEmpty else { return nil }
            return ChummerNormalizedNamedItem(name: name, category: childText(el, "category"))
        }
    }

    private static func mapContacts(_ c: XMLElement) -> [ChummerNormalizedContact] {
        let H = ChummerParsingHelpers.self
        guard let container = c.elements(forName: "contacts").first else { return [] }
        return container.elements(forName: "contact").compactMap { el in
            let name = childText(el, "name")
            guard !name.isEmpty else { return nil }
            return ChummerNormalizedContact(
                name: name,
                role: childText(el, "role"),
                loyalty: H.intValue(childText(el, "loyalty"), default: 1),
                connection: H.intValue(childText(el, "connection"), default: 1)
            )
        }
    }

    private static func mapLifestyles(_ c: XMLElement) -> [ChummerNormalizedLifestyle] {
        let H = ChummerParsingHelpers.self
        guard let container = c.elements(forName: "lifestyles").first else { return [] }
        return container.elements(forName: "lifestyle").compactMap { el in
            let name = childText(el, "name").isEmpty ? "Lifestyle" : childText(el, "name")
            let level = childText(el, "baselifestyle").isEmpty ? childText(el, "lifestyle") : childText(el, "baselifestyle")
            let costText = childText(el, "totalmonthlycost").isEmpty ? childText(el, "cost") : childText(el, "totalmonthlycost")
            return ChummerNormalizedLifestyle(
                name: name,
                level: level.isEmpty ? "Low" : level,
                monthlyCost: H.intValue(costText),
                monthsPrepaid: max(1, H.intValue(childText(el, "months"), default: 1))
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
