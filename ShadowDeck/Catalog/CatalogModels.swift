//
//  CatalogModels.swift
//  ShadowDeck
//
//  Searchable reference entries (typically loaded from Chummer data XML).
//

import Foundation

public enum CatalogKind: String, Codable, Sendable, CaseIterable, Hashable {
    case gear
    case weapon
    case armor
    case cyberware
    case bioware
    case quality
    case contactRole
    case skill
    case adeptPower

    public var displayName: String {
        switch self {
        case .gear: "Gear"
        case .weapon: "Weapons"
        case .armor: "Armor"
        case .cyberware: "Cyberware"
        case .bioware: "Bioware"
        case .quality: "Qualities"
        case .contactRole: "Contact roles"
        case .skill: "Skills"
        case .adeptPower: "Adept powers"
        }
    }
}

public struct CatalogEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: CatalogKind
    public var name: String
    public var category: String
    public var costText: String
    public var costNuyen: Int?
    public var availability: String
    public var source: String
    public var page: String
    public var essenceText: String?
    public var karma: Int?
    public var damage: String?
    public var armorRating: Int?
    public var notes: String
    /// Play-sheet modifiers extracted from Chummer `<bonus>` nodes (or custom entries).
    public var modifiers: [StatModifier]

    public init(
        id: String,
        kind: CatalogKind,
        name: String,
        category: String = "",
        costText: String = "",
        costNuyen: Int? = nil,
        availability: String = "",
        source: String = "",
        page: String = "",
        essenceText: String? = nil,
        karma: Int? = nil,
        damage: String? = nil,
        armorRating: Int? = nil,
        notes: String = "",
        modifiers: [StatModifier] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.category = category
        self.costText = costText
        self.costNuyen = costNuyen
        self.availability = availability
        self.source = source
        self.page = page
        self.essenceText = essenceText
        self.karma = karma
        self.damage = damage
        self.armorRating = armorRating
        self.notes = notes
        self.modifiers = modifiers
    }

    public var subtitle: String {
        var parts: [String] = []
        if !category.isEmpty { parts.append(category) }
        if let cost = costNuyen {
            parts.append("¥\(cost)")
        } else if !costText.isEmpty {
            parts.append(costText.hasPrefix("¥") ? costText : "¥\(costText)")
        }
        if let karma {
            parts.append("\(karma) Karma")
        }
        if let essenceText, !essenceText.isEmpty {
            parts.append("ESS \(essenceText)")
        }
        if !modifiers.isEmpty {
            let brief = modifiers.prefix(3).map(\.summary).joined(separator: ", ")
            parts.append(modifiers.count > 3 ? "\(brief)…" : brief)
        }
        if !source.isEmpty {
            parts.append(page.isEmpty ? source : "\(source) p.\(page)")
        }
        return parts.joined(separator: " · ")
    }

    /// Fields used for ranking (name is primary).
    public var searchBlob: String {
        [name, category, source, notes, damage ?? ""]
            .joined(separator: " ")
            .lowercased()
    }
}

// MARK: - Search

public enum CatalogSearch {
    /// Ranked filter: prefers name matches; requires every query token to match
    /// as a whole word (or name prefix), so "ares" does not hit "House**wares**".
    public static func filter(_ entries: [CatalogEntry], query: String) -> [CatalogEntry] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return entries }

        let tokens = raw.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return entries }

        var scored: [(CatalogEntry, Int)] = []
        for entry in entries {
            guard let score = score(entry: entry, tokens: tokens) else { continue }
            scored.append((entry, score))
        }
        scored.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
        }
        return scored.map(\.0)
    }

    /// Higher is better. nil = no match.
    private static func score(entry: CatalogEntry, tokens: [String]) -> Int? {
        let name = entry.name.lowercased()
        let category = entry.category.lowercased()
        let source = entry.source.lowercased()
        let nameWords = words(in: name)
        let categoryWords = words(in: category)

        var total = 0
        for token in tokens {
            var best = 0
            // Exact name
            if name == token { best = max(best, 100) }
            // Name starts with token
            if name.hasPrefix(token) { best = max(best, 80) }
            // Whole word in name
            if nameWords.contains(where: { $0 == token || $0.hasPrefix(token) }) {
                best = max(best, 70)
            }
            // Substring in name only if token is reasonably long (avoid "ar" noise)
            if token.count >= 3, name.contains(token) {
                best = max(best, 50)
            }
            // Category whole-word only (prevents "ares" ∈ "housewares")
            if categoryWords.contains(where: { $0 == token || $0.hasPrefix(token) }) {
                best = max(best, 25)
            }
            // Source book code exact / prefix (e.g. SR5, RF)
            if source == token || (token.count >= 2 && source.hasPrefix(token)) {
                best = max(best, 15)
            }
            if best == 0 { return nil } // every token must match something
            total += best
        }
        return total
    }

    private static func words(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

public struct CatalogLoadResult: Sendable {
    public var entries: [CatalogEntry]
    public var sourceDirectory: URL?
    public var loadedFiles: [String]
    public var errors: [String]

    public var isEmpty: Bool { entries.isEmpty }
}
