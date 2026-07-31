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

    /// Rough SR5 core-book monthly cost guidance (¥); always user-editable.
    public var suggestedMonthlyCostSR5: Int {
        switch self {
        case .street: return 0
        case .squatter: return 500
        case .low: return 2_000
        case .middle: return 5_000
        case .high: return 10_000
        case .luxury: return 100_000
        }
    }
}

public struct Lifestyle: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var level: LifestyleLevel
    public var monthlyCost: Int
    public var monthsPrepaid: Int
    public var notes: String
    /// When false, excluded from monthly burn / process month.
    public var isActive: Bool
    /// Optional calendar hint for UI; Process Month does not require it.
    public var nextDueDate: Date?

    public init(
        id: UUID = UUID(),
        name: String = "Primary",
        level: LifestyleLevel = .low,
        monthlyCost: Int = 0,
        monthsPrepaid: Int = 1,
        notes: String = "",
        isActive: Bool = true,
        nextDueDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.level = level
        self.monthlyCost = max(0, monthlyCost)
        self.monthsPrepaid = max(0, monthsPrepaid)
        self.notes = notes
        self.isActive = isActive
        self.nextDueDate = nextDueDate
    }

    enum CodingKeys: String, CodingKey {
        case id, name, level, monthlyCost, monthsPrepaid, notes, isActive, nextDueDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Primary"
        level = try c.decodeIfPresent(LifestyleLevel.self, forKey: .level) ?? .low
        monthlyCost = max(0, try c.decodeIfPresent(Int.self, forKey: .monthlyCost) ?? 0)
        monthsPrepaid = max(0, try c.decodeIfPresent(Int.self, forKey: .monthsPrepaid) ?? 1)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        nextDueDate = try c.decodeIfPresent(Date.self, forKey: .nextDueDate)
    }

    public var status: LifestyleCoverageStatus {
        guard isActive else { return .inactive }
        if monthsPrepaid > 0 { return .covered }
        return .due
    }
}

public enum LifestyleCoverageStatus: String, Sendable, Hashable {
    case inactive
    case covered
    case due
    case underfunded

    public var displayName: String {
        switch self {
        case .inactive: "Inactive"
        case .covered: "Covered"
        case .due: "Due"
        case .underfunded: "Underfunded"
        }
    }
}

// MARK: - Ledger

public enum LifestyleLedgerKind: String, Codable, Sendable, CaseIterable, Hashable {
    case processMonth
    case prepay
    case reserveDeposit
    case reserveWithdraw
    case adjustment

    public var displayName: String {
        switch self {
        case .processMonth: "Process Month"
        case .prepay: "Prepay"
        case .reserveDeposit: "Reserve Deposit"
        case .reserveWithdraw: "Reserve Withdraw"
        case .adjustment: "Adjustment"
        }
    }
}

public struct LifestyleLedgerEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: LifestyleLedgerKind
    /// Nuyen delta relative to the character’s liquid funds (negative = spent).
    public var amount: Int
    public var note: String
    public var lifestyleID: UUID?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: LifestyleLedgerKind,
        amount: Int,
        note: String = "",
        lifestyleID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.amount = amount
        self.note = note
        self.lifestyleID = lifestyleID
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
