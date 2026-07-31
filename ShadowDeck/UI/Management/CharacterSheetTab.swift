//
//  CharacterSheetTab.swift
//  ShadowDeck
//
//  Phase 6 — sections of the detailed character workspace.
//

import Foundation

enum CharacterSheetTab: String, CaseIterable, Identifiable, Hashable {
    case summary
    case skills
    case gear
    case augmentations
    case qualities
    case contacts
    case lifestyle
    case advance
    case magic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Summary"
        case .skills: "Skills"
        case .gear: "Gear"
        case .augmentations: "Augs"
        case .qualities: "Qualities"
        case .contacts: "Contacts"
        case .lifestyle: "Lifestyle"
        case .advance: "Advance"
        case .magic: "Magic"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "person.text.rectangle"
        case .skills: "list.bullet.rectangle"
        case .gear: "bag"
        case .augmentations: "cpu"
        case .qualities: "star.circle"
        case .contacts: "person.2"
        case .lifestyle: "house"
        case .advance: "arrow.up.heart"
        case .magic: "sparkles"
        }
    }

    /// Tabs shown for a given awakened path (Magic is always available for notes/spells import).
    static func tabs(for path: AwakenedPath) -> [CharacterSheetTab] {
        // Keep Magic tab for all so imported spells/powers remain reachable after path edits.
        allCases
    }
}
