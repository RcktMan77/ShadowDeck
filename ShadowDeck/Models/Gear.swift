//
//  Gear.swift
//  ShadowDeck
//

import Foundation

public enum GearCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case weapon
    case armor
    case clothing
    case electronics
    case cyberdeck
    case software
    case vehicle
    case drone
    case ammo
    case chemical
    case biotech
    case magic
    case security
    case survival
    case tool
    case identity
    case entertainment
    case other

    public var displayName: String {
        switch self {
        case .cyberdeck: "Cyberdeck"
        case .biotech: "Biotech"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Map free-text (Chummer category / user label) into a ShadowDeck bucket.
    public static func infer(from raw: String) -> GearCategory {
        let t = raw.lowercased()
        if t.contains("weapon") || t.contains("firearm") || t.contains("blade")
            || t.contains("club") || t.contains("cannon") || t.contains("rifle")
            || t.contains("pistol") || t.contains("shotgun") || t.contains("launcher")
            || t.contains("melee") || t.contains("throwing")
        {
            return .weapon
        }
        if t.contains("armor") || t.contains("shield") { return .armor }
        if t.contains("cloth") || t.contains("disguise") || t.contains("cloak") { return .clothing }
        if t.contains("ammo") || t.contains("ammunition") || t.contains("grenade") { return .ammo }
        if t.contains("cyberdeck") || t.contains("rigger command") { return .cyberdeck }
        if t.contains("program") || t.contains("autosoft") || t.contains("soft")
            || t.contains("app") || t.contains("agent")
        {
            return .software
        }
        if t.contains("drone") { return .drone }
        if t.contains("vehicle") || t.contains("bike") || t.contains("car")
            || t.contains("aircraft") || t.contains("watercraft")
        {
            return .vehicle
        }
        if t.contains("drug") || t.contains("chemical") || t.contains("toxin")
            || t.contains("btl") || t.contains("compound")
        {
            return .chemical
        }
        if t.contains("biotech") || t.contains("medkit") || t.contains("docwagon") { return .biotech }
        if t.contains("magic") || t.contains("focus") || t.contains("reagent")
            || t.contains("alchemical") || t.contains("spell formula") || t.contains("fetish")
        {
            return .magic
        }
        if t.contains("security") || t.contains("breaking and entering")
            || t.contains("lock") || t.contains("restraint")
        {
            return .security
        }
        if t.contains("survival") || t.contains("camping") || t.contains("climbing") { return .survival }
        if t.contains("tool") || t.contains("kit") { return .tool }
        if t.contains("sin") || t.contains("license") || t.contains("identity")
            || t.contains("credstick") || t.contains("fake")
        {
            return .identity
        }
        if t.contains("entertainment") || t.contains("music") { return .entertainment }
        if t.contains("electronic") || t.contains("commlink") || t.contains("sensor")
            || t.contains("audio") || t.contains("visual") || t.contains("rfid")
            || t.contains("communication")
        {
            return .electronics
        }
        return .other
    }
}

public struct GearItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var catalogKey: String
    public var name: String
    public var category: GearCategory
    public var quantity: Int
    /// Cost in nuyen for the stack as acquired (not unit price × qty when bargained).
    public var nuyenCost: Int
    public var availability: String
    public var equipped: Bool
    public var notes: String
    public var armorRating: Int?
    public var damageCode: String?
    /// Free-text subcategory from catalog (e.g. Chummer “Commlinks”).
    public var subcategory: String?
    public var source: String?
    /// Rating for rating-scaled bonuses (smartlink, etc.).
    public var rating: Int
    /// Stat modifiers while equipped (or always for passive gear).
    public var modifiers: [StatModifier]
    /// When true, item was purchased through ShadowDeck (nuyen already charged).
    public var purchasedInApp: Bool

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        category: GearCategory,
        quantity: Int = 1,
        nuyenCost: Int = 0,
        availability: String = "",
        equipped: Bool = false,
        notes: String = "",
        armorRating: Int? = nil,
        damageCode: String? = nil,
        subcategory: String? = nil,
        source: String? = nil,
        rating: Int = 1,
        modifiers: [StatModifier] = [],
        purchasedInApp: Bool = false
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.category = category
        self.quantity = quantity
        self.nuyenCost = nuyenCost
        self.availability = availability
        self.equipped = equipped
        self.notes = notes
        self.armorRating = armorRating
        self.damageCode = damageCode
        self.subcategory = subcategory
        self.source = source
        self.rating = max(1, rating)
        self.modifiers = modifiers
        self.purchasedInApp = purchasedInApp
    }
}

// Backward-compatible decode for pre–Phase 7 library payloads.
extension GearItem {
    private enum CodingKeys: String, CodingKey {
        case id, catalogKey, name, category, quantity, nuyenCost, availability
        case equipped, notes, armorRating, damageCode, subcategory, source
        case rating, modifiers, purchasedInApp
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        catalogKey = try c.decode(String.self, forKey: .catalogKey)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(GearCategory.self, forKey: .category)
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        nuyenCost = try c.decodeIfPresent(Int.self, forKey: .nuyenCost) ?? 0
        availability = try c.decodeIfPresent(String.self, forKey: .availability) ?? ""
        equipped = try c.decodeIfPresent(Bool.self, forKey: .equipped) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        armorRating = try c.decodeIfPresent(Int.self, forKey: .armorRating)
        damageCode = try c.decodeIfPresent(String.self, forKey: .damageCode)
        subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        rating = max(1, try c.decodeIfPresent(Int.self, forKey: .rating) ?? 1)
        modifiers = try c.decodeIfPresent([StatModifier].self, forKey: .modifiers) ?? []
        purchasedInApp = try c.decodeIfPresent(Bool.self, forKey: .purchasedInApp) ?? false
    }
}

extension GearItem: ModifierSource {
    public var modifierSourceName: String { name }
    public var modifierRating: Int { rating }
    public var contributesModifiers: Bool { equipped }
}
