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

// MARK: - Contacts

/// Current standing for favors (manual). Interaction log may snapshot a direction without changing this.
public enum ContactFavorState: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case none
    case owesMe
    case iOweThem

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .owesMe: "Owes me"
        case .iOweThem: "I owe them"
        }
    }

    /// Compact badge text for list rows.
    public var shortLabel: String {
        switch self {
        case .none: ""
        case .owesMe: "Owes me"
        case .iOweThem: "I owe"
        }
    }

    public var hasPendingFavor: Bool { self != .none }
}

/// One dated touchpoint with a contact. `favorDirection` is historical only.
public struct ContactInteraction: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var summary: String
    /// Snapshot of favor direction for this interaction; does not auto-update contact.favorState.
    public var favorDirection: ContactFavorState?
    /// Soft link into `RunLibrary` (tolerate missing runs).
    public var relatedRunID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        summary: String = "",
        favorDirection: ContactFavorState? = nil,
        relatedRunID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.summary = summary
        self.favorDirection = favorDirection
        self.relatedRunID = relatedRunID
        self.createdAt = createdAt
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

    // Enriched contacts (v1) — optional / defaulted for legacy payloads
    public var tags: [String]
    /// Manually maintained current favor standing.
    public var favorState: ContactFavorState
    public var favorOneTime: Bool
    public var lastContactAt: Date?
    public var interactionLog: [ContactInteraction]

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
        personalLife: String? = nil,
        tags: [String] = [],
        favorState: ContactFavorState = .none,
        favorOneTime: Bool = false,
        lastContactAt: Date? = nil,
        interactionLog: [ContactInteraction] = []
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
        self.tags = tags
        self.favorState = favorState
        self.favorOneTime = favorOneTime
        self.lastContactAt = lastContactAt
        self.interactionLog = interactionLog
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, role, loyalty, connection, notes
        case contactType, metatype, gender, age, location, preferredPayment, hobbiesVice, personalLife
        case tags, favorState, favorOneTime, lastContactAt, interactionLog
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        loyalty = try c.decodeIfPresent(Int.self, forKey: .loyalty) ?? 1
        connection = try c.decodeIfPresent(Int.self, forKey: .connection) ?? 1
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        contactType = try c.decodeIfPresent(String.self, forKey: .contactType)
        metatype = try c.decodeIfPresent(String.self, forKey: .metatype)
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        age = try c.decodeIfPresent(String.self, forKey: .age)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        preferredPayment = try c.decodeIfPresent(String.self, forKey: .preferredPayment)
        hobbiesVice = try c.decodeIfPresent(String.self, forKey: .hobbiesVice)
        personalLife = try c.decodeIfPresent(String.self, forKey: .personalLife)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        favorState = try c.decodeIfPresent(ContactFavorState.self, forKey: .favorState) ?? .none
        favorOneTime = try c.decodeIfPresent(Bool.self, forKey: .favorOneTime) ?? false
        lastContactAt = try c.decodeIfPresent(Date.self, forKey: .lastContactAt)
        interactionLog = try c.decodeIfPresent([ContactInteraction].self, forKey: .interactionLog) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(role, forKey: .role)
        try c.encode(loyalty, forKey: .loyalty)
        try c.encode(connection, forKey: .connection)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(contactType, forKey: .contactType)
        try c.encodeIfPresent(metatype, forKey: .metatype)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(age, forKey: .age)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(preferredPayment, forKey: .preferredPayment)
        try c.encodeIfPresent(hobbiesVice, forKey: .hobbiesVice)
        try c.encodeIfPresent(personalLife, forKey: .personalLife)
        try c.encode(tags, forKey: .tags)
        try c.encode(favorState, forKey: .favorState)
        try c.encode(favorOneTime, forKey: .favorOneTime)
        try c.encodeIfPresent(lastContactAt, forKey: .lastContactAt)
        try c.encode(interactionLog, forKey: .interactionLog)
    }

    public var hasExtendedProfile: Bool {
        [contactType, metatype, gender, age, location, preferredPayment, hobbiesVice, personalLife]
            .contains { ($0?.isEmpty == false) }
            || !notes.isEmpty
            || !tags.isEmpty
            || favorState != .none
            || !interactionLog.isEmpty
    }

    /// Newest-first log for UI.
    public var interactionLogNewestFirst: [ContactInteraction] {
        interactionLog.sorted { $0.date > $1.date }
    }

    /// Append an interaction. Always updates `lastContactAt`. Never overwrites `favorState` unless `updateCurrentFavor` is true.
    public mutating func addInteraction(
        _ entry: ContactInteraction,
        updateCurrentFavor: Bool = false
    ) {
        interactionLog.append(entry)
        if let existing = lastContactAt {
            lastContactAt = max(existing, entry.date)
        } else {
            lastContactAt = entry.date
        }
        if updateCurrentFavor, let direction = entry.favorDirection, direction != .none {
            favorState = direction
        }
    }

    public mutating func removeInteraction(id: UUID) {
        interactionLog.removeAll { $0.id == id }
    }
}
