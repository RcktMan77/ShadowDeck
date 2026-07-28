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
    /// Extended identity (from Chummer import / detail sheet).
    public var contactType: String?
    public var metatype: String?
    public var gender: String?
    public var age: String?
    public var location: String?
    public var preferredPayment: String?
    public var hobbiesVice: String?
    public var personalLife: String?

    public init(
        id: UUID = UUID(),
        name: String,
        role: String = "",
        loyalty: Int = 1,
        connection: Int = 1,
        notes: String = "",
        contactType: String? = nil,
        metatype: String? = nil,
        gender: String? = nil,
        age: String? = nil,
        location: String? = nil,
        preferredPayment: String? = nil,
        hobbiesVice: String? = nil,
        personalLife: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.loyalty = loyalty
        self.connection = connection
        self.notes = notes
        self.contactType = contactType
        self.metatype = metatype
        self.gender = gender
        self.age = age
        self.location = location
        self.preferredPayment = preferredPayment
        self.hobbiesVice = hobbiesVice
        self.personalLife = personalLife
    }

    public var hasExtendedProfile: Bool {
        [contactType, metatype, gender, age, location, preferredPayment, hobbiesVice, personalLife]
            .contains { ($0?.isEmpty == false) }
            || !notes.isEmpty
    }
}
