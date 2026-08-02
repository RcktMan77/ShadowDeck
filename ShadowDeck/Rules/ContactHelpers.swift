//
//  ContactHelpers.swift
//  ShadowDeck
//
//  Pure helpers for enriched contacts: relationship status, filters, suggested tags.
//

import Foundation

// MARK: - Relationship status (locked thresholds)

public enum ContactRelationshipStatus: String, Sendable, Hashable, CaseIterable, Identifiable {
    case strong
    case warm
    case cold
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strong: "Strong"
        case .warm: "Warm"
        case .cold: "Cold"
        case .unknown: "Unknown"
        }
    }
}

public enum ContactHelpers {
    /// Recency windows used by `relationshipStatus` (calendar days).
    public static let strongRecencyDays = 30
    public static let warmRecencyDays = 90

    /// Suggested tags (chips only; free-form still allowed).
    public static let suggestedTags: [String] = [
        "Fixer",
        "Street Doc",
        "Corp",
        "Gang",
        "Fence",
        "Johnson",
        "Informant",
        "Smuggler",
        "Talismonger",
        "Rigger Shop"
    ]

    /// Locked rules (v1):
    /// - Unknown — no `lastContactAt`
    /// - Strong — Loyalty ≥ 4 **and** last contact within 30 days
    /// - Warm — Loyalty ≥ 3 **or** last contact within 90 days
    /// - Cold — Loyalty ≤ 2 **or** last contact older than 90 days
    ///
    /// Evaluation order: Unknown → Strong → Warm → Cold (else Warm as soft fallback).
    public static func relationshipStatus(
        for contact: Contact,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ContactRelationshipStatus {
        guard let last = contact.lastContactAt else {
            return .unknown
        }

        let days = calendar.dateComponents([.day], from: last, to: now).day ?? Int.max
        let loyalty = contact.loyalty

        if loyalty >= 4, days <= strongRecencyDays {
            return .strong
        }
        if loyalty >= 3 || days <= warmRecencyDays {
            return .warm
        }
        // loyalty ≤ 2 or last contact older than 90 days
        if loyalty <= 2 || days > warmRecencyDays {
            return .cold
        }
        return .warm
    }

    public static func hasPendingFavor(_ contact: Contact) -> Bool {
        contact.favorState.hasPendingFavor
    }

    /// Name, role, and tags only (notes excluded from v1 search).
    public static func matchesSearch(_ contact: Contact, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if contact.name.lowercased().contains(q) { return true }
        if contact.role.lowercased().contains(q) { return true }
        if contact.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
        return false
    }

    public static func matchesFavorFilter(_ contact: Contact, pendingOnly: Bool) -> Bool {
        guard pendingOnly else { return true }
        return hasPendingFavor(contact)
    }

    public static func matchesTagFilter(_ contact: Contact, tag: String?) -> Bool {
        guard let tag, !tag.isEmpty else { return true }
        return contact.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    public static func filter(
        _ contacts: [Contact],
        query: String = "",
        pendingFavorOnly: Bool = false,
        tag: String? = nil
    ) -> [Contact] {
        contacts.filter { c in
            matchesSearch(c, query: query)
                && matchesFavorFilter(c, pendingOnly: pendingFavorOnly)
                && matchesTagFilter(c, tag: tag)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Normalize a tag for storage (trim; drop empties).
    public static func normalizeTag(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
