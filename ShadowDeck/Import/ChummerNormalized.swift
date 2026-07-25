//
//  ChummerNormalized.swift
//  ShadowDeck
//
//  Intermediate representation shared by JSON and .chum5 parsers.
//

import Foundation

public struct ChummerNormalizedCharacter: Sendable {
    public var name: String
    public var alias: String
    public var metatype: String
    public var gameEdition: String
    public var buildMethod: String
    public var playerName: String
    public var concept: String
    public var description: String
    public var background: String
    public var notes: String
    public var gender: String
    public var age: String

    public var nuyen: Decimal
    public var karmaAvailable: Int
    public var karmaTotal: Int

    public var priorityMetatype: String?
    public var priorityAttributes: String?
    public var prioritySpecial: String?
    public var prioritySkills: String?
    public var priorityResources: String?

    public var isAdept: Bool
    public var isMagician: Bool
    public var isTechnomancer: Bool
    public var isMysticAdept: Bool

    public var attributes: [ChummerNormalizedAttribute]
    public var essenceTotal: Decimal?
    public var skills: [ChummerNormalizedSkill]
    public var skillGroups: [ChummerNormalizedSkillGroup]
    public var qualities: [ChummerNormalizedQuality]
    public var cyberware: [ChummerNormalizedAugmentation]
    public var bioware: [ChummerNormalizedAugmentation]
    public var gear: [ChummerNormalizedGear]
    public var weapons: [ChummerNormalizedGear]
    public var armors: [ChummerNormalizedGear]
    public var powers: [ChummerNormalizedPower]
    public var spells: [ChummerNormalizedNamedItem]
    public var complexForms: [ChummerNormalizedNamedItem]
    public var contacts: [ChummerNormalizedContact]
    public var lifestyles: [ChummerNormalizedLifestyle]

    public init(
        name: String = "",
        alias: String = "",
        metatype: String = "Human",
        gameEdition: String = "SR5",
        buildMethod: String = "",
        playerName: String = "",
        concept: String = "",
        description: String = "",
        background: String = "",
        notes: String = "",
        gender: String = "",
        age: String = "",
        nuyen: Decimal = 0,
        karmaAvailable: Int = 0,
        karmaTotal: Int = 0,
        priorityMetatype: String? = nil,
        priorityAttributes: String? = nil,
        prioritySpecial: String? = nil,
        prioritySkills: String? = nil,
        priorityResources: String? = nil,
        isAdept: Bool = false,
        isMagician: Bool = false,
        isTechnomancer: Bool = false,
        isMysticAdept: Bool = false,
        attributes: [ChummerNormalizedAttribute] = [],
        essenceTotal: Decimal? = nil,
        skills: [ChummerNormalizedSkill] = [],
        skillGroups: [ChummerNormalizedSkillGroup] = [],
        qualities: [ChummerNormalizedQuality] = [],
        cyberware: [ChummerNormalizedAugmentation] = [],
        bioware: [ChummerNormalizedAugmentation] = [],
        gear: [ChummerNormalizedGear] = [],
        weapons: [ChummerNormalizedGear] = [],
        armors: [ChummerNormalizedGear] = [],
        powers: [ChummerNormalizedPower] = [],
        spells: [ChummerNormalizedNamedItem] = [],
        complexForms: [ChummerNormalizedNamedItem] = [],
        contacts: [ChummerNormalizedContact] = [],
        lifestyles: [ChummerNormalizedLifestyle] = []
    ) {
        self.name = name
        self.alias = alias
        self.metatype = metatype
        self.gameEdition = gameEdition
        self.buildMethod = buildMethod
        self.playerName = playerName
        self.concept = concept
        self.description = description
        self.background = background
        self.notes = notes
        self.gender = gender
        self.age = age
        self.nuyen = nuyen
        self.karmaAvailable = karmaAvailable
        self.karmaTotal = karmaTotal
        self.priorityMetatype = priorityMetatype
        self.priorityAttributes = priorityAttributes
        self.prioritySpecial = prioritySpecial
        self.prioritySkills = prioritySkills
        self.priorityResources = priorityResources
        self.isAdept = isAdept
        self.isMagician = isMagician
        self.isTechnomancer = isTechnomancer
        self.isMysticAdept = isMysticAdept
        self.attributes = attributes
        self.essenceTotal = essenceTotal
        self.skills = skills
        self.skillGroups = skillGroups
        self.qualities = qualities
        self.cyberware = cyberware
        self.bioware = bioware
        self.gear = gear
        self.weapons = weapons
        self.armors = armors
        self.powers = powers
        self.spells = spells
        self.complexForms = complexForms
        self.contacts = contacts
        self.lifestyles = lifestyles
    }
}

public struct ChummerNormalizedAttribute: Sendable {
    public var name: String
    public var base: Int
    public var total: Int
    public var metatypeMin: Int?
    public var metatypeMax: Int?

    public init(name: String, base: Int, total: Int, metatypeMin: Int? = nil, metatypeMax: Int? = nil) {
        self.name = name
        self.base = base
        self.total = total
        self.metatypeMin = metatypeMin
        self.metatypeMax = metatypeMax
    }
}

public struct ChummerNormalizedSkill: Sendable {
    public var name: String
    public var rating: Int
    public var specialized: String?
    public var isKnowledge: Bool
    public var isLanguage: Bool
    public var skillGroup: String?
    public var category: String?
    public var attribute: String?

    public init(
        name: String,
        rating: Int,
        specialized: String? = nil,
        isKnowledge: Bool = false,
        isLanguage: Bool = false,
        skillGroup: String? = nil,
        category: String? = nil,
        attribute: String? = nil
    ) {
        self.name = name
        self.rating = rating
        self.specialized = specialized
        self.isKnowledge = isKnowledge
        self.isLanguage = isLanguage
        self.skillGroup = skillGroup
        self.category = category
        self.attribute = attribute
    }
}

public struct ChummerNormalizedSkillGroup: Sendable {
    public var name: String
    public var rating: Int

    public init(name: String, rating: Int) {
        self.name = name
        self.rating = rating
    }
}

public struct ChummerNormalizedQuality: Sendable {
    public var name: String
    public var karma: Int
    public var isPositive: Bool
    public var source: String?

    public init(name: String, karma: Int, isPositive: Bool, source: String? = nil) {
        self.name = name
        self.karma = karma
        self.isPositive = isPositive
        self.source = source
    }
}

public struct ChummerNormalizedAugmentation: Sendable {
    public var name: String
    public var essence: Decimal
    public var grade: String
    public var rating: Int?
    public var isBioware: Bool
    public var notes: String

    public init(
        name: String,
        essence: Decimal,
        grade: String = "Standard",
        rating: Int? = nil,
        isBioware: Bool = false,
        notes: String = ""
    ) {
        self.name = name
        self.essence = essence
        self.grade = grade
        self.rating = rating
        self.isBioware = isBioware
        self.notes = notes
    }
}

public struct ChummerNormalizedGear: Sendable {
    public var name: String
    public var quantity: Int
    public var cost: Int
    public var category: String
    public var armorRating: Int?
    public var damageCode: String?
    public var equipped: Bool
    public var notes: String

    public init(
        name: String,
        quantity: Int = 1,
        cost: Int = 0,
        category: String = "other",
        armorRating: Int? = nil,
        damageCode: String? = nil,
        equipped: Bool = false,
        notes: String = ""
    ) {
        self.name = name
        self.quantity = quantity
        self.cost = cost
        self.category = category
        self.armorRating = armorRating
        self.damageCode = damageCode
        self.equipped = equipped
        self.notes = notes
    }
}

public struct ChummerNormalizedPower: Sendable {
    public var name: String
    public var rating: Int
    public var pointCost: Decimal

    public init(name: String, rating: Int, pointCost: Decimal) {
        self.name = name
        self.rating = rating
        self.pointCost = pointCost
    }
}

public struct ChummerNormalizedNamedItem: Sendable {
    public var name: String
    public var category: String

    public init(name: String, category: String = "") {
        self.name = name
        self.category = category
    }
}

public struct ChummerNormalizedContact: Sendable {
    public var name: String
    public var role: String
    public var loyalty: Int
    public var connection: Int

    public init(name: String, role: String, loyalty: Int, connection: Int) {
        self.name = name
        self.role = role
        self.loyalty = loyalty
        self.connection = connection
    }
}

public struct ChummerNormalizedLifestyle: Sendable {
    public var name: String
    public var level: String
    public var monthlyCost: Int
    public var monthsPrepaid: Int

    public init(name: String, level: String, monthlyCost: Int, monthsPrepaid: Int = 1) {
        self.name = name
        self.level = level
        self.monthlyCost = monthlyCost
        self.monthsPrepaid = monthsPrepaid
    }
}
