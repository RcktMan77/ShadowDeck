//
//  AdvancementSkillPreviewCache.swift
//  ShadowDeck
//
//  Skill-raise rows for the Advance tab. Rebuilt only from `invalidate`.
//

import Foundation

enum AdvancementSkillListFilter: String, CaseIterable, Identifiable {
    case all, active, knowledge, language
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .knowledge: "Knowledge"
        case .language: "Language"
        }
    }
}

enum AdvancementSkillListSort: String, CaseIterable, Identifiable {
    case name, cheapest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .cheapest: "Cheapest"
        }
    }
}

struct AdvancementSkillPreviewCache {
    private(set) var previews: [AdvancementRaisePreview] = []
    private(set) var rebuildCount = 0

    mutating func invalidate(
        character: Character,
        rules: any EditionRules,
        filter: AdvancementSkillListFilter,
        sort: AdvancementSkillListSort
    ) {
        rebuildCount += 1
        previews = Self.build(character: character, rules: rules, filter: filter, sort: sort)
    }

    static func build(
        character: Character,
        rules: any EditionRules,
        filter: AdvancementSkillListFilter,
        sort: AdvancementSkillListSort
    ) -> [AdvancementRaisePreview] {
        var list = character.skills.map {
            AdvancementEngine.skillRaisePreview(character: character, skill: $0, rules: rules)
        }
        switch filter {
        case .all: break
        case .active: list = list.filter { $0.skillCategory == .active }
        case .knowledge: list = list.filter { $0.skillCategory == .knowledge }
        case .language: list = list.filter { $0.skillCategory == .language }
        }
        switch sort {
        case .name:
            list.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .cheapest:
            list.sort {
                if $0.canRaise != $1.canRaise { return $0.canRaise && !$1.canRaise }
                if $0.karmaCost != $1.karmaCost { return $0.karmaCost < $1.karmaCost }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        return list
    }
}
