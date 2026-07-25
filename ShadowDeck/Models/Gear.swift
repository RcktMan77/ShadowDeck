//
//  Gear.swift
//  ShadowDeck
//

import Foundation

public enum GearCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case weapon
    case armor
    case electronics
    case cyberdeck
    case vehicle
    case drone
    case ammo
    case chemical
    case tool
    case identity
    case other
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
        damageCode: String? = nil
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
    }
}
