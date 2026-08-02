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
    /// Street Cred / Notoriety / Public Awareness (Phase 2D). Nil in legacy payloads = all zero.
    public var reputation: CharacterReputation?
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
        schemaVersion: Int = Self.currentSchemaVersion,
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
        reputation: CharacterReputation? = nil,
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
        self.reputation = reputation
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

    /// Street Cred (legacy-safe; missing reputation decodes as 0).
    public var streetCred: Int {
        get { reputation?.streetCred ?? 0 }
        set {
            var scores = reputation ?? .zero
            scores.streetCred = newValue
            reputation = scores
        }
    }

    /// Notoriety (legacy-safe; missing reputation decodes as 0).
    public var notoriety: Int {
        get { reputation?.notoriety ?? 0 }
        set {
            var scores = reputation ?? .zero
            scores.notoriety = newValue
            reputation = scores
        }
    }

    /// Public Awareness (legacy-safe; missing reputation decodes as 0).
    public var publicAwareness: Int {
        get { reputation?.publicAwareness ?? 0 }
        set {
            var scores = reputation ?? .zero
            scores.publicAwareness = newValue
            reputation = scores
        }
    }

    /// Apply reputation deltas (any may be negative). Leaves scores as-is when all deltas are 0.
    public mutating func applyReputationDeltas(
        streetCred deltaSC: Int = 0,
        notoriety deltaNot: Int = 0,
        publicAwareness deltaPA: Int = 0
    ) {
        guard deltaSC != 0 || deltaNot != 0 || deltaPA != 0 else { return }
        streetCred += deltaSC
        notoriety += deltaNot
        publicAwareness += deltaPA
    }

    public mutating func touch() {
        modifiedAt = Date()
    }
}

// MARK: - Reputation (Phase 2D)

/// Minimal SR reputation scores tracked on a character.
public struct CharacterReputation: Codable, Sendable, Hashable {
    public var streetCred: Int
    public var notoriety: Int
    public var publicAwareness: Int

    public static let zero = CharacterReputation(streetCred: 0, notoriety: 0, publicAwareness: 0)

    public init(streetCred: Int = 0, notoriety: Int = 0, publicAwareness: Int = 0) {
        self.streetCred = streetCred
        self.notoriety = notoriety
        self.publicAwareness = publicAwareness
    }

    private enum CodingKeys: String, CodingKey {
        case streetCred, notoriety, publicAwareness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streetCred = try c.decodeIfPresent(Int.self, forKey: .streetCred) ?? 0
        notoriety = try c.decodeIfPresent(Int.self, forKey: .notoriety) ?? 0
        publicAwareness = try c.decodeIfPresent(Int.self, forKey: .publicAwareness) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(streetCred, forKey: .streetCred)
        try c.encode(notoriety, forKey: .notoriety)
        try c.encode(publicAwareness, forKey: .publicAwareness)
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
