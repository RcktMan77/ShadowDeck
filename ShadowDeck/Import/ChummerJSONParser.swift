//
//  ChummerJSONParser.swift
//  ShadowDeck
//
//  Parses Chummer5a JSON export (XML-shaped JSON with characters.character).
//

import Foundation

public enum ChummerJSONParser {
    public static func parse(data: Data) throws -> ChummerNormalizedCharacter {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ImportError.parseFailed(error.localizedDescription)
        }
        return try parse(object: object)
    }

    public static func parse(object: Any) throws -> ChummerNormalizedCharacter {
        let root = try characterDictionary(from: object)
        return mapDictionary(root)
    }

    // MARK: - Locate character node

    private static func characterDictionary(from object: Any) throws -> [String: Any] {
        if let dict = object as? [String: Any] {
            if let characters = dict["characters"] as? [String: Any] {
                if let character = characters["character"] as? [String: Any] {
                    return character
                }
                if let list = characters["character"] as? [Any],
                   let first = list.first as? [String: Any]
                {
                    return first
                }
            }
            // Bare character object (some exports / test fixtures).
            if dict["name"] != nil || dict["alias"] != nil || dict["metatype"] != nil {
                return dict
            }
        }
        if let arr = object as? [Any], let first = arr.first as? [String: Any] {
            return try characterDictionary(from: first)
        }
        throw ImportError.missingCharacterData
    }

    // MARK: - Map

    private static func mapDictionary(_ c: [String: Any]) -> ChummerNormalizedCharacter {
        let H = ChummerParsingHelpers.self

        var skills = mapSkills(c["skills"])
        let skillGroups = mapSkillGroups(c["skills"])

        // Some exports put knowledge skills separately.
        if let knowledge = c["knowledgeskills"] {
            skills.append(contentsOf: mapSkillList(knowledge, forceKnowledge: true))
        }

        let qualities = mapQualities(c["qualities"])
        let cyber = mapAugmentations(c["cyberwares"] ?? c["cyberware"], bioware: false)
        let bio = mapAugmentations(c["biowares"] ?? c["bioware"], bioware: true)

        var character = ChummerNormalizedCharacter(
            name: H.stringValue(c["name"]) ?? "",
            alias: H.stringValue(c["alias"]) ?? "",
            metatype: H.stringValue(c["metatype"]) ?? "Human",
            gameEdition: H.stringValue(c["gameedition"]) ?? "SR5",
            buildMethod: H.stringValue(c["buildmethod"]) ?? "",
            playerName: H.stringValue(c["playername"]) ?? "",
            concept: H.stripHTML(H.stringValue(c["concept"])),
            description: H.stripHTML(H.stringValue(c["description"])),
            background: H.stripHTML(H.stringValue(c["background"])),
            notes: mergeNotes(
                H.stripHTML(H.stringValue(c["notes"])),
                H.stripHTML(H.stringValue(c["gamenotes"]))
            ),
            gender: H.stringValue(c["gender"]) ?? "",
            age: H.stringValue(c["age"]) ?? "",
            nuyen: H.decimalValue(c["nuyen"]),
            karmaAvailable: H.intValue(c["karma"]),
            karmaTotal: H.intValue(c["totalkarma"], default: H.intValue(c["karma"])),
            priorityMetatype: H.stringValue(c["prioritymetatype"]),
            priorityAttributes: H.stringValue(c["priorityattributes"]),
            prioritySpecial: H.stringValue(c["priorityspecial"]),
            prioritySkills: firstPriorityLetter(c["priorityskills"]),
            priorityResources: H.stringValue(c["priorityresources"]),
            isAdept: H.boolValue(c["adept"]),
            isMagician: H.boolValue(c["magician"]),
            isTechnomancer: H.boolValue(c["technomancer"]),
            isMysticAdept: H.boolValue(c["mysticadept"]),
            attributes: mapAttributes(c["attributes"]),
            essenceTotal: essence(from: c),
            skills: skills,
            skillGroups: skillGroups,
            qualities: qualities,
            cyberware: cyber,
            bioware: bio,
            gear: mapGear(c["gears"] ?? c["gear"], category: "other"),
            weapons: mapGear(c["weapons"] ?? c["weapon"], category: "weapon"),
            armors: mapArmor(c["armors"] ?? c["armor"]),
            powers: mapPowers(c["powers"] ?? c["power"]),
            spells: mapNamed(c["spells"] ?? c["spell"], nameKeys: ["name", "name_english"]),
            complexForms: mapNamed(c["complexforms"] ?? c["complexform"], nameKeys: ["name", "name_english"]),
            contacts: mapContacts(c["contacts"] ?? c["contact"]),
            lifestyles: mapLifestyles(c["lifestyles"] ?? c["lifestyle"]),
            physicalDamage: H.intValue(c["physicalcmfilled"]),
            stunDamage: H.intValue(c["stuncmfilled"])
        )

        // Infer adept from qualities if flags missing.
        if !character.isAdept && qualities.contains(where: { $0.name.caseInsensitiveCompare("Adept") == .orderedSame }) {
            character.isAdept = true
        }
        if !character.isMagician && qualities.contains(where: {
            $0.name.localizedCaseInsensitiveContains("Magician") && !$0.name.localizedCaseInsensitiveContains("Aspected")
        }) {
            character.isMagician = true
        }

        return character
    }

    private static func essence(from c: [String: Any]) -> Decimal? {
        let H = ChummerParsingHelpers.self
        for key in ["totaless", "essence", "ess"] {
            if c[key] != nil {
                let value = H.decimalValue(c[key])
                if value > 0 { return value }
            }
        }
        return nil
    }

    private static func firstPriorityLetter(_ any: Any?) -> String? {
        if let s = ChummerParsingHelpers.stringValue(any), s.count == 1 {
            return s.uppercased()
        }
        if let arr = any as? [Any] {
            for item in arr {
                if let s = ChummerParsingHelpers.stringValue(item), s.count == 1 {
                    return s.uppercased()
                }
            }
        }
        return nil
    }

    private static func mapAttributes(_ node: Any?) -> [ChummerNormalizedAttribute] {
        let H = ChummerParsingHelpers.self
        return H.attributeDictionaries(from: node).compactMap { dict in
            guard let name = H.stringValue(dict["name"]) ?? H.stringValue(dict["name_english"]) else {
                return nil
            }
            let total = H.intValue(dict["total"] ?? dict["totalvalue"], default: H.intValue(dict["base"]))
            let base = H.intValue(dict["base"], default: total)
            return ChummerNormalizedAttribute(
                name: name,
                base: base,
                total: total,
                metatypeMin: dict["min"] != nil ? H.intValue(dict["min"]) : (dict["metatypemin"] != nil ? H.intValue(dict["metatypemin"]) : nil),
                metatypeMax: dict["max"] != nil ? H.intValue(dict["max"]) : (dict["metatypemax"] != nil ? H.intValue(dict["metatypemax"]) : nil)
            )
        }
    }

    private static func mapSkills(_ node: Any?) -> [ChummerNormalizedSkill] {
        guard let node else { return [] }
        if let dict = node as? [String: Any] {
            return mapSkillList(dict["skill"] ?? dict)
        }
        return mapSkillList(node)
    }

    private static func mapSkillGroups(_ node: Any?) -> [ChummerNormalizedSkillGroup] {
        let H = ChummerParsingHelpers.self
        guard let dict = node as? [String: Any] else { return [] }
        return H.arrayOfDictionaries(dict["skillgroup"]).compactMap { g in
            guard let name = H.stringValue(g["name"]) ?? H.stringValue(g["name_english"]) else { return nil }
            let rating = H.intValue(g["rating"] ?? g["base"] ?? g["total"])
            guard rating > 0 else { return nil }
            return ChummerNormalizedSkillGroup(name: name, rating: rating)
        }
    }

    private static func mapSkillList(_ node: Any?, forceKnowledge: Bool = false) -> [ChummerNormalizedSkill] {
        let H = ChummerParsingHelpers.self
        return H.arrayOfDictionaries(node).compactMap { s in
            guard let name = H.stringValue(s["name"]) ?? H.stringValue(s["name_english"]) else { return nil }
            let isKnowledge = forceKnowledge || H.boolValue(s["knowledge"])
            let category = H.stringValue(s["skillcategory"]) ?? H.stringValue(s["skillcategory_english"]) ?? ""
            let isLanguage = category.localizedCaseInsensitiveContains("language")
                || name.localizedCaseInsensitiveContains("language")

            // Skill rank is `rating` (or base+karma), NOT `total` (dice pool).
            let rating = H.intValue(s["rating"], default: H.intValue(s["base"]) + H.intValue(s["karma"]))
            // Skip untrained / native-language infinite placeholders with 0 rating.
            if rating <= 0 { return nil }
            // Guard against Chummer's Int32.Max native language total leaking into rating.
            if rating > 13 { return nil }

            let spec = H.stringValue(s["spec"]) ?? H.stringValue(s["specialty"])
            return ChummerNormalizedSkill(
                name: name,
                rating: rating,
                specialized: spec,
                isKnowledge: isKnowledge,
                isLanguage: isLanguage,
                skillGroup: H.stringValue(s["skillgroup"]) ?? H.stringValue(s["skillgroup_english"]),
                category: category,
                attribute: H.stringValue(s["attribute"]) ?? H.stringValue(s["displayattribute"])
            )
        }
    }

    private static func mapQualities(_ node: Any?) -> [ChummerNormalizedQuality] {
        let H = ChummerParsingHelpers.self
        let items = H.arrayOfDictionaries(node, childKey: "quality")
        return items.compactMap { q in
            guard let name = H.stringValue(q["name"]) ?? H.stringValue(q["name_english"]) else { return nil }
            let type = (H.stringValue(q["qualitytype"]) ?? H.stringValue(q["type"]) ?? "Positive")
            let isPositive = type.lowercased().contains("positive")
            var karma = H.intValue(q["karma"] ?? q["bp"] ?? q["cost"])
            // Some exports omit karma on built-in qualities.
            if karma == 0, let contrib = H.stringValue(q["contribution"]) {
                karma = H.intValue(contrib)
            }
            return ChummerNormalizedQuality(
                name: name,
                karma: abs(karma),
                isPositive: isPositive,
                source: H.stringValue(q["source"])
            )
        }
    }

    private static func mapAugmentations(_ node: Any?, bioware: Bool) -> [ChummerNormalizedAugmentation] {
        let H = ChummerParsingHelpers.self
        let key = bioware ? "bioware" : "cyberware"
        let items = H.arrayOfDictionaries(node, childKey: key)
        return items.compactMap { a in
            guard let name = H.stringValue(a["name"]) ?? H.stringValue(a["name_english"]) else { return nil }
            let ess = H.decimalValue(a["ess"] ?? a["essence"] ?? a["calculatedess"])
            let rating = H.intValue(a["rating"])
            return ChummerNormalizedAugmentation(
                name: name,
                essence: ess,
                grade: H.stringValue(a["grade"]) ?? "Standard",
                rating: rating > 0 ? rating : nil,
                isBioware: bioware,
                notes: H.stripHTML(H.stringValue(a["notes"]))
            )
        }
    }

    private static func mapGear(_ node: Any?, category: String) -> [ChummerNormalizedGear] {
        let H = ChummerParsingHelpers.self
        let child = category == "weapon" ? "weapon" : "gear"
        let items = H.arrayOfDictionaries(node, childKey: child)
        return items.compactMap { g in
            guard let name = H.stringValue(g["name"]) ?? H.stringValue(g["name_english"]) else { return nil }
            // Skip abstract unarmed attack rows.
            if name.localizedCaseInsensitiveContains("Unarmed Attack") { return nil }
            let qty = max(1, H.intValue(g["qty"] ?? g["quantity"] ?? g["count"], default: 1))
            let cost = H.intValue(g["cost"] ?? g["totalcost"] ?? g["stcost"])
            let damage = H.stringValue(g["damage"])
            return ChummerNormalizedGear(
                name: name,
                quantity: qty,
                cost: cost,
                category: category,
                armorRating: nil,
                damageCode: damage,
                equipped: H.boolValue(g["equipped"]) || category == "weapon",
                notes: H.stripHTML(H.stringValue(g["notes"]))
            )
        }
    }

    private static func mapArmor(_ node: Any?) -> [ChummerNormalizedGear] {
        let H = ChummerParsingHelpers.self
        return H.arrayOfDictionaries(node, childKey: "armor").compactMap { a in
            guard let name = H.stringValue(a["name"]) ?? H.stringValue(a["name_english"]) else { return nil }
            let armor = H.intValue(a["armor"] ?? a["totalarmor"] ?? a["armorvalue"])
            return ChummerNormalizedGear(
                name: name,
                quantity: 1,
                cost: H.intValue(a["cost"] ?? a["totalcost"]),
                category: "armor",
                armorRating: armor > 0 ? armor : nil,
                equipped: H.boolValue(a["equipped"]) || true,
                notes: H.stripHTML(H.stringValue(a["notes"]))
            )
        }
    }

    private static func mergeNotes(_ notes: String, _ gameNotes: String) -> String {
        if !notes.isEmpty, !gameNotes.isEmpty { return notes + "\n\n" + gameNotes }
        return notes.isEmpty ? gameNotes : notes
    }

    private static func mapPowers(_ node: Any?) -> [ChummerNormalizedPower] {
        let H = ChummerParsingHelpers.self
        return H.arrayOfDictionaries(node, childKey: "power").compactMap { p in
            guard let name = H.stringValue(p["name"]) ?? H.stringValue(p["name_english"]) else { return nil }
            let rating = max(1, H.intValue(p["rating"] ?? p["total"], default: 1))
            let points = H.decimalValue(p["totalpoints"] ?? p["extrapointcost"] ?? p["pointsperlevel"])
            return ChummerNormalizedPower(name: name, rating: rating, pointCost: points)
        }
    }

    private static func mapNamed(_ node: Any?, nameKeys: [String]) -> [ChummerNormalizedNamedItem] {
        let H = ChummerParsingHelpers.self
        // Try common wrappers.
        let items = H.arrayOfDictionaries(node)
            + H.arrayOfDictionaries(node, childKey: "spell")
            + H.arrayOfDictionaries(node, childKey: "complexform")
        var seen = Set<String>()
        var result: [ChummerNormalizedNamedItem] = []
        for item in items {
            let name = nameKeys.compactMap { H.stringValue(item[$0]) }.first
            guard let name, seen.insert(name).inserted else { continue }
            let category = H.stringValue(item["category"]) ?? H.stringValue(item["category_english"]) ?? ""
            result.append(ChummerNormalizedNamedItem(name: name, category: category))
        }
        return result
    }

    private static func mapContacts(_ node: Any?) -> [ChummerNormalizedContact] {
        let H = ChummerParsingHelpers.self
        return H.arrayOfDictionaries(node, childKey: "contact").compactMap { c in
            guard let name = H.stringValue(c["name"]) else { return nil }
            return ChummerNormalizedContact(
                name: name,
                role: H.stringValue(c["role"]) ?? H.stringValue(c["job"]) ?? "",
                loyalty: H.intValue(c["loyalty"], default: 1),
                connection: H.intValue(c["connection"], default: 1),
                notes: H.stripHTML(H.stringValue(c["notes"])),
                contactType: H.stringValue(c["type"]) ?? H.stringValue(c["contacttype"]) ?? "",
                metatype: H.stringValue(c["metatype"]) ?? "",
                gender: H.stringValue(c["gender"]) ?? "",
                age: H.stringValue(c["age"]) ?? "",
                location: H.stringValue(c["location"]) ?? "",
                preferredPayment: H.stringValue(c["preferredpayment"]) ?? "",
                hobbiesVice: H.stringValue(c["hobbiesvice"]) ?? "",
                personalLife: H.stringValue(c["personallife"]) ?? ""
            )
        }
    }

    private static func mapLifestyles(_ node: Any?) -> [ChummerNormalizedLifestyle] {
        let H = ChummerParsingHelpers.self
        return H.arrayOfDictionaries(node, childKey: "lifestyle").compactMap { l in
            let name = H.stringValue(l["name"]) ?? "Lifestyle"
            let level = H.stringValue(l["baselifestyle"])
                ?? H.stringValue(l["lifestyle"])
                ?? H.stringValue(l["lifestylename"])
                ?? "Low"
            let cost = H.intValue(l["totalmonthlycost"] ?? l["cost"] ?? l["totalcost"])
            let months = max(1, H.intValue(l["months"] ?? l["purchasedmonths"] ?? l["increment"], default: 1))
            return ChummerNormalizedLifestyle(name: name, level: level, monthlyCost: cost, monthsPrepaid: months)
        }
    }
}
