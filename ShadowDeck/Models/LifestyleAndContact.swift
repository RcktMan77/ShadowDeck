//
//  LifestyleAndContact.swift
//  ShadowDeck
//

import Foundation

public enum LifestyleLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case street
    case squatter
    case low
    case middle
    case high
    case luxury

    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

public struct Lifestyle: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var level: LifestyleLevel
    public var monthlyCost: Int
    public var monthsPrepaid: Int
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String = "Primary",
        level: LifestyleLevel = .low,
        monthlyCost: Int = 0,
        monthsPrepaid: Int = 1,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.level = level
        self.monthlyCost = monthlyCost
        self.monthsPrepaid = monthsPrepaid
        self.notes = notes
    }
}

public struct Contact: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var role: String
    public var loyalty: Int
    public var connection: Int
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        role: String = "",
        loyalty: Int = 1,
        connection: Int = 1,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.loyalty = loyalty
        self.connection = connection
        self.notes = notes
    }
}
