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
    /// Short tagline / role concept (sheet “concept” field).
    public var concept: String
    /// Longer fiction / backstory for story-mode display. Optional for legacy payloads.
    public var background: String?
    /// Mission logs, table notes, freeform (may be plain text or RTF).
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
    /// Buffer spent first when processing monthly lifestyle costs.
    public var lifestyleNuyenReserve: Int
    /// Last successful “Process Month” (any number of months).
    public var lifestyleLastProcessedAt: Date?
    /// Append-only lifestyle payment history (optional in payloads for legacy decode).
    public var lifestyleLedger: [LifestyleLedgerEntry]?
    /// Append-only karma advancement history (optional for legacy decode).
    public var advancementLedger: [AdvancementLedgerEntry]?
    /// Draft advancement plan (cart). Persists so users can save goals across sessions/tabs.
    public var advancementPlan: [AdvancementPlanItem]?

    /// Play-state condition damage. Optional so legacy library payloads still decode.
    public var conditionTrack: ConditionTrack?

    // Avatar (Phase 2 stores binary; Phase 1 keeps metadata + optional inline data)
    public var avatar: AvatarRef

    /// Optional original import payload (Chummer) for faithful re-export.
    public var importProvenance: ImportProvenance?

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
        background: String? = nil,
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
        lifestyleLastProcessedAt: Date? = nil,
        lifestyleLedger: [LifestyleLedgerEntry]? = nil,
        advancementLedger: [AdvancementLedgerEntry]? = nil,
        advancementPlan: [AdvancementPlanItem]? = nil,
        conditionTrack: ConditionTrack? = nil,
        avatar: AvatarRef = AvatarRef(),
        importProvenance: ImportProvenance? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.streetName = streetName
        self.concept = concept
        self.background = background
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
        self.lifestyleLastProcessedAt = lifestyleLastProcessedAt
        self.lifestyleLedger = lifestyleLedger
        self.advancementLedger = advancementLedger
        self.advancementPlan = advancementPlan
        self.conditionTrack = conditionTrack
        self.avatar = avatar
        self.importProvenance = importProvenance
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Ledger entries (empty if never set).
    public var lifestyleLedgerEntries: [LifestyleLedgerEntry] {
        get { lifestyleLedger ?? [] }
        set { lifestyleLedger = newValue.isEmpty ? [] : newValue }
    }

    public mutating func appendLifestyleLedger(_ entry: LifestyleLedgerEntry, keepLast limit: Int = 40) {
        var entries = lifestyleLedgerEntries
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        lifestyleLedger = entries
    }

    /// Advancement ledger entries (empty if never set).
    public var advancementLedgerEntries: [AdvancementLedgerEntry] {
        get { advancementLedger ?? [] }
        set { advancementLedger = newValue.isEmpty ? [] : newValue }
    }

    public mutating func appendAdvancementLedger(_ entry: AdvancementLedgerEntry, keepLast limit: Int = 40) {
        var entries = advancementLedgerEntries
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        advancementLedger = entries
    }

    /// Draft plan items (empty if never set). Survives tab switches and library saves.
    public var advancementPlanItems: [AdvancementPlanItem] {
        get { advancementPlan ?? [] }
        set { advancementPlan = newValue.isEmpty ? nil : newValue }
    }

    public var physicalDamage: Int {
        get { conditionTrack?.physicalDamage ?? 0 }
        set {
            var track = conditionTrack ?? ConditionTrack()
            track.physicalDamage = max(0, newValue)
            conditionTrack = track
        }
    }

    public var stunDamage: Int {
        get { conditionTrack?.stunDamage ?? 0 }
        set {
            var track = conditionTrack ?? ConditionTrack()
            track.stunDamage = max(0, newValue)
            conditionTrack = track
        }
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
