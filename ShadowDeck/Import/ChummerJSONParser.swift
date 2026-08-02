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
                   let first = list.first as? [String: Any] {
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
        let helpers = ChummerParsingHelpers.self

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
            name: helpers.stringValue(c["name"]) ?? "",
            alias: helpers.stringValue(c["alias"]) ?? "",
            metatype: helpers.stringValue(c["metatype"]) ?? "Human",
            gameEdition: helpers.stringValue(c["gameedition"]) ?? "SR5",
            buildMethod: helpers.stringValue(c["buildmethod"]) ?? "",
            playerName: helpers.stringValue(c["playername"]) ?? "",
            concept: helpers.stripHTML(helpers.stringValue(c["concept"])),
            description: helpers.stripHTML(helpers.stringValue(c["description"])),
            background: helpers.stripHTML(helpers.stringValue(c["background"])),
            notes: mergeNotes(
                helpers.stripHTML(helpers.stringValue(c["notes"])),
                helpers.stripHTML(helpers.stringValue(c["gamenotes"]))
            ),
            gender: helpers.stringValue(c["gender"]) ?? "",
            age: helpers.stringValue(c["age"]) ?? "",
            nuyen: helpers.decimalValue(c["nuyen"]),
            karmaAvailable: helpers.intValue(c["karma"]),
            karmaTotal: helpers.intValue(c["totalkarma"], default: helpers.intValue(c["karma"])),
            priorityMetatype: helpers.stringValue(c["prioritymetatype"]),
            priorityAttributes: helpers.stringValue(c["priorityattributes"]),
            prioritySpecial: helpers.stringValue(c["priorityspecial"]),
            prioritySkills: firstPriorityLetter(c["priorityskills"]),
            priorityResources: helpers.stringValue(c["priorityresources"]),
            isAdept: helpers.boolValue(c["adept"]),
            isMagician: helpers.boolValue(c["magician"]),
            isTechnomancer: helpers.boolValue(c["technomancer"]),
            isMysticAdept: helpers.boolValue(c["mysticadept"]),
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
            physicalDamage: helpers.intValue(c["physicalcmfilled"]),
            stunDamage: helpers.intValue(c["stuncmfilled"])
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
        let helpers = ChummerParsingHelpers.self
        for key in ["totaless", "essence", "ess"] where c[key] != nil {
            let value = helpers.decimalValue(c[key])
            if value > 0 { return value }
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
        let helpers = ChummerParsingHelpers.self
        return helpers.attributeDictionaries(from: node).compactMap { dict in
            guard let name = helpers.stringValue(dict["name"]) ?? helpers.stringValue(dict["name_english"]) else {
                return nil
            }
            let total = helpers.intValue(dict["total"] ?? dict["totalvalue"], default: helpers.intValue(dict["base"]))
            let base = helpers.intValue(dict["base"], default: total)
            return ChummerNormalizedAttribute(
                name: name,
                base: base,
                total: total,
                metatypeMin: dict["min"] != nil ? helpers.intValue(dict["min"]) : (dict["metatypemin"] != nil ? helpers.intValue(dict["metatypemin"]) : nil),
                metatypeMax: dict["max"] != nil ? helpers.intValue(dict["max"]) : (dict["metatypemax"] != nil ? helpers.intValue(dict["metatypemax"]) : nil)
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
        let helpers = ChummerParsingHelpers.self
        guard let dict = node as? [String: Any] else { return [] }
        return helpers.arrayOfDictionaries(dict["skillgroup"]).compactMap { g in
            guard let name = helpers.stringValue(g["name"]) ?? helpers.stringValue(g["name_english"]) else { return nil }
            let rating = helpers.intValue(g["rating"] ?? g["base"] ?? g["total"])
            guard rating > 0 else { return nil }
            return ChummerNormalizedSkillGroup(name: name, rating: rating)
        }
    }

    private static func mapSkillList(_ node: Any?, forceKnowledge: Bool = false) -> [ChummerNormalizedSkill] {
        let helpers = ChummerParsingHelpers.self
        return helpers.arrayOfDictionaries(node).compactMap { s in
            guard let name = helpers.stringValue(s["name"]) ?? helpers.stringValue(s["name_english"]) else { return nil }
            let isKnowledge = forceKnowledge || helpers.boolValue(s["knowledge"])
            let category = helpers.stringValue(s["skillcategory"]) ?? helpers.stringValue(s["skillcategory_english"]) ?? ""
            let isLanguage = category.localizedCaseInsensitiveContains("language")
                || name.localizedCaseInsensitiveContains("language")

            // Skill rank is `rating` (or base+karma), NOT `total` (dice pool).
            let rating = helpers.intValue(s["rating"], default: helpers.intValue(s["base"]) + helpers.intValue(s["karma"]))
            // Skip untrained / native-language infinite placeholders with 0 rating.
            if rating <= 0 { return nil }
            // Guard against Chummer's Int32.Max native language total leaking into rating.
            if rating > 13 { return nil }

            let spec = helpers.stringValue(s["spec"]) ?? helpers.stringValue(s["specialty"])
            return ChummerNormalizedSkill(
                name: name,
                rating: rating,
                specialized: spec,
                isKnowledge: isKnowledge,
                isLanguage: isLanguage,
                skillGroup: helpers.stringValue(s["skillgroup"]) ?? helpers.stringValue(s["skillgroup_english"]),
                category: category,
                attribute: helpers.stringValue(s["attribute"]) ?? helpers.stringValue(s["displayattribute"])
            )
        }
    }

    private static func mapQualities(_ node: Any?) -> [ChummerNormalizedQuality] {
        let helpers = ChummerParsingHelpers.self
        let items = helpers.arrayOfDictionaries(node, childKey: "quality")
        return items.compactMap { q in
            guard let name = helpers.stringValue(q["name"]) ?? helpers.stringValue(q["name_english"]) else { return nil }
            let type = (helpers.stringValue(q["qualitytype"]) ?? helpers.stringValue(q["type"]) ?? "Positive")
            let isPositive = type.lowercased().contains("positive")
            var karma = helpers.intValue(q["karma"] ?? q["bp"] ?? q["cost"])
            // Some exports omit karma on built-in qualities.
            if karma == 0, let contrib = helpers.stringValue(q["contribution"]) {
                karma = helpers.intValue(contrib)
            }
            return ChummerNormalizedQuality(
                name: name,
                karma: abs(karma),
                isPositive: isPositive,
                source: helpers.stringValue(q["source"])
            )
        }
    }

    private static func mapAugmentations(_ node: Any?, bioware: Bool) -> [ChummerNormalizedAugmentation] {
        let helpers = ChummerParsingHelpers.self
        let key = bioware ? "bioware" : "cyberware"
        let items = helpers.arrayOfDictionaries(node, childKey: key)
        return items.compactMap { a in
            guard let name = helpers.stringValue(a["name"]) ?? helpers.stringValue(a["name_english"]) else { return nil }
            let ess = helpers.decimalValue(a["ess"] ?? a["essence"] ?? a["calculatedess"])
            let rating = helpers.intValue(a["rating"])
            return ChummerNormalizedAugmentation(
                name: name,
                essence: ess,
                grade: helpers.stringValue(a["grade"]) ?? "Standard",
                rating: rating > 0 ? rating : nil,
                isBioware: bioware,
                notes: helpers.stripHTML(helpers.stringValue(a["notes"]))
            )
        }
    }

    private static func mapGear(_ node: Any?, category: String) -> [ChummerNormalizedGear] {
        let helpers = ChummerParsingHelpers.self
        let child = category == "weapon" ? "weapon" : "gear"
        let items = helpers.arrayOfDictionaries(node, childKey: child)
        return items.compactMap { g in
            guard let name = helpers.stringValue(g["name"]) ?? helpers.stringValue(g["name_english"]) else { return nil }
            // Skip abstract unarmed attack rows.
            if name.localizedCaseInsensitiveContains("Unarmed Attack") { return nil }
            let qty = max(1, helpers.intValue(g["qty"] ?? g["quantity"] ?? g["count"], default: 1))
            let cost = helpers.intValue(g["cost"] ?? g["totalcost"] ?? g["stcost"])
            let damage = helpers.stringValue(g["damage"])
            return ChummerNormalizedGear(
                name: name,
                quantity: qty,
                cost: cost,
                category: category,
                armorRating: nil,
                damageCode: damage,
                equipped: helpers.boolValue(g["equipped"]) || category == "weapon",
                notes: helpers.stripHTML(helpers.stringValue(g["notes"]))
            )
        }
    }

    private static func mapArmor(_ node: Any?) -> [ChummerNormalizedGear] {
        let helpers = ChummerParsingHelpers.self
        return helpers.arrayOfDictionaries(node, childKey: "armor").compactMap { a in
            guard let name = helpers.stringValue(a["name"]) ?? helpers.stringValue(a["name_english"]) else { return nil }
            let armor = helpers.intValue(a["armor"] ?? a["totalarmor"] ?? a["armorvalue"])
            return ChummerNormalizedGear(
                name: name,
                quantity: 1,
                cost: helpers.intValue(a["cost"] ?? a["totalcost"]),
                category: "armor",
                armorRating: armor > 0 ? armor : nil,
                equipped: helpers.boolValue(a["equipped"]) || true,
                notes: helpers.stripHTML(helpers.stringValue(a["notes"]))
            )
        }
    }

    private static func mergeNotes(_ notes: String, _ gameNotes: String) -> String {
        if !notes.isEmpty, !gameNotes.isEmpty { return notes + "\n\n" + gameNotes }
        return notes.isEmpty ? gameNotes : notes
    }

    private static func mapPowers(_ node: Any?) -> [ChummerNormalizedPower] {
        let helpers = ChummerParsingHelpers.self
        return helpers.arrayOfDictionaries(node, childKey: "power").compactMap { p in
            guard let name = helpers.stringValue(p["name"]) ?? helpers.stringValue(p["name_english"]) else { return nil }
            let rating = max(1, helpers.intValue(p["rating"] ?? p["total"], default: 1))
            let points = helpers.decimalValue(p["totalpoints"] ?? p["extrapointcost"] ?? p["pointsperlevel"])
            return ChummerNormalizedPower(name: name, rating: rating, pointCost: points)
        }
    }

    private static func mapNamed(_ node: Any?, nameKeys: [String]) -> [ChummerNormalizedNamedItem] {
        let helpers = ChummerParsingHelpers.self
        // Try common wrappers.
        let items = helpers.arrayOfDictionaries(node)
            + helpers.arrayOfDictionaries(node, childKey: "spell")
            + helpers.arrayOfDictionaries(node, childKey: "complexform")
        var seen = Set<String>()
        var result: [ChummerNormalizedNamedItem] = []
        for item in items {
            let name = nameKeys.compactMap { helpers.stringValue(item[$0]) }.first
            guard let name, seen.insert(name).inserted else { continue }
            let category = helpers.stringValue(item["category"]) ?? helpers.stringValue(item["category_english"]) ?? ""
            result.append(ChummerNormalizedNamedItem(name: name, category: category))
        }
        return result
    }

    private static func mapContacts(_ node: Any?) -> [ChummerNormalizedContact] {
        let helpers = ChummerParsingHelpers.self
        return helpers.arrayOfDictionaries(node, childKey: "contact").compactMap { c in
            guard let name = helpers.stringValue(c["name"]) else { return nil }
            return ChummerNormalizedContact(
                name: name,
                role: helpers.stringValue(c["role"]) ?? helpers.stringValue(c["job"]) ?? "",
                loyalty: helpers.intValue(c["loyalty"], default: 1),
                connection: helpers.intValue(c["connection"], default: 1),
                notes: helpers.stripHTML(helpers.stringValue(c["notes"])),
                contactType: helpers.stringValue(c["type"]) ?? helpers.stringValue(c["contacttype"]) ?? "",
                metatype: helpers.stringValue(c["metatype"]) ?? "",
                gender: helpers.stringValue(c["gender"]) ?? "",
                age: helpers.stringValue(c["age"]) ?? "",
                location: helpers.stringValue(c["location"]) ?? "",
                preferredPayment: helpers.stringValue(c["preferredpayment"]) ?? "",
                hobbiesVice: helpers.stringValue(c["hobbiesvice"]) ?? "",
                personalLife: helpers.stringValue(c["personallife"]) ?? ""
            )
        }
    }

    private static func mapLifestyles(_ node: Any?) -> [ChummerNormalizedLifestyle] {
        let helpers = ChummerParsingHelpers.self
        return helpers.arrayOfDictionaries(node, childKey: "lifestyle").compactMap { lifestyle in
            let name = helpers.stringValue(lifestyle["name"]) ?? "Lifestyle"
            let level = helpers.stringValue(lifestyle["baselifestyle"])
                ?? helpers.stringValue(lifestyle["lifestyle"])
                ?? helpers.stringValue(lifestyle["lifestylename"])
                ?? "Low"
            let cost = helpers.intValue(
                lifestyle["totalmonthlycost"] ?? lifestyle["cost"] ?? lifestyle["totalcost"]
            )
            let months = max(
                1,
                helpers.intValue(
                    lifestyle["months"] ?? lifestyle["purchasedmonths"] ?? lifestyle["increment"],
                    default: 1
                )
            )
            return ChummerNormalizedLifestyle(name: name, level: level, monthlyCost: cost, monthsPrepaid: months)
        }
    }
}
