//
//  RulesReference.swift
//  ShadowDeck
//
//  Structured mechanical reference entries (seed JSON) and page-reference keys.
//  Summaries are original concise paraphrases — not rulebook prose.
//

import Foundation

// MARK: - Categories & calculators

public enum RuleCategory: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case dice
    case advancement
    case lifestyle
    case combat
    case magic
    case matrix
    case social
    case chargen
    case catalog
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dice: "Tests & Dice"
        case .advancement: "Karma & Advancement"
        case .lifestyle: "Lifestyle"
        case .combat: "Combat & Derived"
        case .magic: "Magic"
        case .matrix: "Matrix"
        case .social: "Social"
        case .chargen: "Chargen"
        case .catalog: "Catalog"
        case .other: "Other"
        }
    }
}

public enum CalculatorID: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case drain
    case karmaRaise
    case glitchThreshold
    case lifestyleBurn
    case overwatch
    case conditionMonitors
    case limitsSR5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .drain: "Drain"
        case .karmaRaise: "Karma raise"
        case .glitchThreshold: "Glitch threshold"
        case .lifestyleBurn: "Lifestyle burn"
        case .overwatch: "Overwatch"
        case .conditionMonitors: "Condition monitors"
        case .limitsSR5: "SR5 limits"
        }
    }
}

// MARK: - Page reference

/// Stable key into the user’s PDF library role binding (e.g. `sr5-crb`).
public struct PageRef: Codable, Sendable, Hashable, Identifiable {
    public var bookKey: String
    public var page: Int
    public var label: String

    public var id: String { "\(bookKey):\(page):\(label)" }

    public init(bookKey: String, page: Int, label: String) {
        self.bookKey = bookKey
        self.page = max(1, page)
        self.label = label
    }

    /// Well-known book keys for curated chips (user binds their own files).
    public enum BookKey {
        public static let sr4a = "sr4a"
        public static let sr5CRB = "sr5-crb"
        public static let sr6Core = "sr6-core"
    }

    /// Core-book order index: SR4=0, SR5=1, SR6=2, other=50.
    public var editionSortIndex: Int {
        let key = bookKey.lowercased()
        switch key {
        case BookKey.sr4a, "sr4", "sr4-core", "sr4a-core":
            return 0
        case BookKey.sr5CRB, "sr5", "sr5-core", "sr5crb":
            return 1
        case BookKey.sr6Core, "sr6", "sr6-crb", "sr6-core-rulebook":
            return 2
        default:
            return 50
        }
    }

    /// Which core edition this book key represents, if any.
    public var coreEdition: Edition? {
        switch editionSortIndex {
        case 0: return .sr4
        case 1: return .sr5
        case 2: return .sr6
        default: return nil
        }
    }

    /// Display order for page chips.
    /// - Parameter preferEdition: when set (e.g. open character), that edition’s core
    ///   book is listed first; remaining cores stay SR4 → SR5 → SR6; then other keys.
    public static func sortedForDisplay(_ refs: [Self], preferEdition: Edition? = nil) -> [Self] {
        func rank(_ ref: Self) -> (Int, Int, String, Int, String) {
            let base = ref.editionSortIndex
            let preferred: Int
            if let preferEdition, ref.coreEdition == preferEdition {
                preferred = -1
            } else {
                preferred = base
            }
            return (preferred, base, ref.bookKey.lowercased(), ref.page, ref.label.lowercased())
        }
        return refs.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra.0 != rb.0 { return ra.0 < rb.0 }
            if ra.1 != rb.1 { return ra.1 < rb.1 }
            if ra.2 != rb.2 { return ra.2 < rb.2 }
            if ra.3 != rb.3 { return ra.3 < rb.3 }
            return ra.4 < rb.4
        }
    }
}

// MARK: - Rule entry

public struct RuleEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var category: RuleCategory
    public var tags: [String]
    /// Original concise paraphrase only — never copyrighted book prose.
    public var summary: String
    public var formula: String?
    /// Empty = applies to all editions.
    public var editions: [Edition]
    public var pageRefs: [PageRef]
    public var calculator: CalculatorID?
    public var relatedIDs: [String]

    public init(
        id: String,
        title: String,
        category: RuleCategory,
        tags: [String] = [],
        summary: String,
        formula: String? = nil,
        editions: [Edition] = [],
        pageRefs: [PageRef] = [],
        calculator: CalculatorID? = nil,
        relatedIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.tags = tags
        self.summary = summary
        self.formula = formula
        self.editions = editions
        self.pageRefs = PageRef.sortedForDisplay(pageRefs)
        self.calculator = calculator
        self.relatedIDs = relatedIDs
    }

    /// Page chips: optional character edition first, then SR4 → SR5 → SR6 → other.
    public func pageRefsForDisplay(preferEdition: Edition? = nil) -> [PageRef] {
        PageRef.sortedForDisplay(pageRefs, preferEdition: preferEdition)
    }

    /// Default display order without character context.
    public var pageRefsForDisplay: [PageRef] {
        pageRefsForDisplay(preferEdition: nil)
    }

    public var appliesToAllEditions: Bool { editions.isEmpty }

    public func applies(to edition: Edition?) -> Bool {
        guard let edition else { return true }
        if editions.isEmpty { return true }
        return editions.contains(edition)
    }
}

// MARK: - Seed file envelope

public struct RulesSeedFile: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var entries: [RuleEntry]

    public init(schemaVersion: Int = 1, entries: [RuleEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}
