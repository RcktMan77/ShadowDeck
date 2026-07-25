//
//  Character.swift
//  ShadowDeck
//
//  Core domain character — pure value type, Codable, edition-aware.
//  Persistence (SwiftData) will wrap or mirror this in Phase 2.
//

import Foundation

public struct Character: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var schemaVersion: Int

    // Identity
    public var name: String
    public var streetName: String
    public var concept: String
    public var notes: String

    // Edition & build
    public var edition: Edition
    public var metatype: MetatypeID
    public var awakened: AwakenedPath
    public var generation: GenerationProfile
    public var houseRules: HouseRules

    // Core stats
    public var attributes: AttributeRatings
    public var skills: [SkillRating]
    public var skillGroups: [SkillGroupRating]
    public var qualities: [QualityInstance]
    public var gear: [GearItem]
    public var augmentations: [Augmentation]
    public var spells: [SpellInstance]
    public var adeptPowers: [AdeptPowerInstance]
    public var complexForms: [ComplexFormInstance]
    public var lifestyles: [Lifestyle]
    public var contacts: [Contact]

    // Campaign resources
    public var karmaTotal: Int
    public var karmaAvailable: Int
    public var nuyen: Int
    public var lifestyleNuyenReserve: Int

    // Avatar (Phase 2 stores binary; Phase 1 keeps metadata + optional inline data)
    public var avatar: AvatarRef

    // Timestamps
    public var createdAt: Date
    public var modifiedAt: Date

    public static let currentSchemaVersion = 1

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = Character.currentSchemaVersion,
        name: String,
        streetName: String = "",
        concept: String = "",
        notes: String = "",
        edition: Edition,
        metatype: MetatypeID = .human,
        awakened: AwakenedPath = .mundane,
        generation: GenerationProfile,
        houseRules: HouseRules = .coreBook,
        attributes: AttributeRatings = AttributeRatings(),
        skills: [SkillRating] = [],
        skillGroups: [SkillGroupRating] = [],
        qualities: [QualityInstance] = [],
        gear: [GearItem] = [],
        augmentations: [Augmentation] = [],
        spells: [SpellInstance] = [],
        adeptPowers: [AdeptPowerInstance] = [],
        complexForms: [ComplexFormInstance] = [],
        lifestyles: [Lifestyle] = [],
        contacts: [Contact] = [],
        karmaTotal: Int = 0,
        karmaAvailable: Int = 0,
        nuyen: Int = 0,
        lifestyleNuyenReserve: Int = 0,
        avatar: AvatarRef = AvatarRef(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.streetName = streetName
        self.concept = concept
        self.notes = notes
        self.edition = edition
        self.metatype = metatype
        self.awakened = awakened
        self.generation = generation
        self.houseRules = houseRules
        self.attributes = attributes
        self.skills = skills
        self.skillGroups = skillGroups
        self.qualities = qualities
        self.gear = gear
        self.augmentations = augmentations
        self.spells = spells
        self.adeptPowers = adeptPowers
        self.complexForms = complexForms
        self.lifestyles = lifestyles
        self.contacts = contacts
        self.karmaTotal = karmaTotal
        self.karmaAvailable = karmaAvailable
        self.nuyen = nuyen
        self.lifestyleNuyenReserve = lifestyleNuyenReserve
        self.avatar = avatar
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public var displayTitle: String {
        if streetName.isEmpty { return name }
        if name.isEmpty { return streetName }
        return "\(name) “\(streetName)”"
    }

    public mutating func touch() {
        modifiedAt = Date()
    }
}

/// Avatar storage reference. Binary data is optional here for portable documents;
/// the library database may store data separately in Phase 2.
public struct AvatarRef: Codable, Sendable, Hashable {
    public var fileName: String?
    public var mimeType: String?
    public var isAnimated: Bool
    /// Optional inline image bytes for single-file export (kept small when possible).
    public var inlineData: Data?

    public init(
        fileName: String? = nil,
        mimeType: String? = nil,
        isAnimated: Bool = false,
        inlineData: Data? = nil
    ) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.isAnimated = isAnimated
        self.inlineData = inlineData
    }

    public var hasImage: Bool {
        inlineData != nil || fileName != nil
    }
}
