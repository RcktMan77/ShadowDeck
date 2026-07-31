//
//  ConceptTagline.swift
//  ShadowDeck
//
//  Short library / list labels from free-text concept + background.
//  Prefers Shadowrun role keywords; never requires an LLM.
//

import Foundation

public enum ConceptTagline {
    /// Soft max length for a library subtitle (caption under the name).
    public static let maxLength = 42

    /// Length at or below which a concept string is used as-is (after trim).
    public static let shortConceptLimit = 48

    /// Build a short label for Character Library rows.
    /// - Short explicit concepts win.
    /// - Longer text is scanned for role / archetype keywords.
    /// - Optional background is scanned when concept is empty or very long.
    public static func libraryLabel(
        concept: String,
        background: String? = nil,
        awakened: AwakenedPath = .mundane
    ) -> String {
        let conceptTrim = concept.trimmingCharacters(in: .whitespacesAndNewlines)
        let backgroundTrim = (background ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Short concept field — keep author intent.
        if !conceptTrim.isEmpty, conceptTrim.count <= shortConceptLimit, !looksLikeProse(conceptTrim) {
            return truncate(conceptTrim, max: maxLength)
        }

        let haystack = [conceptTrim, backgroundTrim]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()

        guard !haystack.isEmpty else { return "" }

        // 2) Keyword roles from concept + background.
        var roles = matchRoles(in: haystack)

        // 3) Light awakened bias when text never named a magic path.
        if roles.isEmpty {
            roles.append(contentsOf: awakenedFallback(awakened))
        } else if awakened.usesMagic,
                  !roles.contains(where: { magicRoleLabels.contains($0) })
        {
            // e.g. “coder” + awakened adept prose → keep coder, add Adept if present in text
            if haystack.contains("adept") { roles.insert("Adept", at: 0) }
            else if haystack.contains("mystic") { roles.insert("Mystic Adept", at: 0) }
            else if haystack.contains("mage") || haystack.contains("magician") || haystack.contains("spell") {
                roles.insert("Mage", at: 0)
            }
        }

        // 4) Optional corp / city flavor (one chip max).
        if let flavor = matchFlavor(in: haystack) {
            // Prefer “Ex-Renraku Adept” style when we have a role.
            if let first = roles.first {
                let combined = "\(flavor) \(first)"
                if combined.count <= maxLength {
                    return combined
                }
            } else {
                return truncate(flavor, max: maxLength)
            }
        }

        if !roles.isEmpty {
            // Join up to two roles: “Adept Decker”
            let label = roles.prefix(2).joined(separator: " ")
            return truncate(label, max: maxLength)
        }

        // 5) Fallback: first sentence / clause of concept, else background.
        let source = conceptTrim.isEmpty ? backgroundTrim : conceptTrim
        return truncate(firstClause(source), max: maxLength)
    }

    // MARK: - Matching

    private static let magicRoleLabels: Set<String> = [
        "Mage", "Magician", "Adept", "Mystic Adept", "Aspected Mage", "Technomancer",
    ]

    /// Ordered rules: first match wins a slot; later unique labels may append.
    private static let roleRules: [(tokens: [String], label: String)] = [
        (["street sam", "street samurai", "samurai", "chrome warrior"], "Street Samurai"),
        (["mystic adept"], "Mystic Adept"),
        (["physical adept", "adept powers", "adept"], "Adept"),
        (["technomancer", "techno ", "resonance", "sprite"], "Technomancer"),
        (["full magician", "magician", "spellcaster", "spellcasting", " mage", "mage ", "mage,", "mage."], "Mage"),
        (["aspected"], "Aspected Mage"),
        (["decker", "hacker", "cyberdeck", "matrix", "coder", "programmer", "otaku"], "Decker"),
        (["rigger", "drone", "vehicle"], "Rigger"),
        (["face", "negotiator", "negotiat", "social engineer", "con artist"], "Face"),
        (["infiltrator", "covert", "sneak", "ghostwire", " ghost ", "shadow infil"], "Infiltrator"),
        (["gunslinger", "shootist", "sniper", "sharpshooter"], "Gunslinger"),
        (["street doc", "medic", "combat medic", "doctor"], "Street Doc"),
        (["fixer"], "Fixer"),
        (["shaman", "hermetic", "occultist"], "Awakened"),
        (["bounty hunter", "hunter"], "Bounty Hunter"),
        (["smuggler"], "Smuggler"),
        (["bodyguard"], "Bodyguard"),
        (["investigator", "detective", "PI "], "Investigator"),
        (["ex-corp", "ex corp", "former corp", "corpsec", "corp shadow"], "Ex-Corp"),
    ]

    private static let flavorRules: [(tokens: [String], label: String)] = [
        (["renraku"], "Ex-Renraku"),
        (["saeder"], "Ex-SK"),
        (["aztechnology", "aztlan"], "Ex-Aztlan"),
        (["ares "], "Ex-Ares"),
        (["horizon"], "Ex-Horizon"),
        (["neoNET", "neonet", "evo "], "Ex-Corp"),
        (["chicago"], "Chicago"),
        (["seattle"], "Seattle"),
        (["denver"], "Denver"),
        (["neo-tokyo", "neotokyo", "tokyo"], "Neo-Tokyo"),
    ]

    private static func matchRoles(in haystack: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        for rule in roleRules {
            guard rule.tokens.contains(where: { haystack.contains($0) }) else { continue }
            guard seen.insert(rule.label).inserted else { continue }
            found.append(rule.label)
            if found.count >= 3 { break }
        }
        return found
    }

    private static func matchFlavor(in haystack: String) -> String? {
        for rule in flavorRules {
            if rule.tokens.contains(where: { haystack.contains($0) }) {
                return rule.label
            }
        }
        return nil
    }

    private static func awakenedFallback(_ path: AwakenedPath) -> [String] {
        switch path {
        case .mundane: []
        case .fullMagician: ["Mage"]
        case .aspectedMagician: ["Aspected Mage"]
        case .mysticAdept: ["Mystic Adept"]
        case .adept: ["Adept"]
        case .technomancer: ["Technomancer"]
        }
    }

    /// Multi-sentence / paragraph-style free text rather than a short tagline.
    private static func looksLikeProse(_ text: String) -> Bool {
        if text.count > shortConceptLimit { return true }
        if text.contains(". ") || text.contains(".\n") { return true }
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.count >= 10
    }

    private static func firstClause(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Prefer first sentence.
        let stoppers: Set<Unicode.Scalar> = [".", "!", "?", "\n"]
        if let idx = trimmed.unicodeScalars.firstIndex(where: { stoppers.contains($0) }) {
            let clause = String(trimmed.unicodeScalars[..<idx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if clause.count >= 8 { return clause }
        }
        return trimmed
    }

    private static func truncate(_ text: String, max: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        let end = t.index(t.startIndex, offsetBy: max - 1)
        var slice = String(t[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastSpace = slice.lastIndex(of: " "), lastSpace > slice.startIndex {
            slice = String(slice[..<lastSpace])
        }
        return slice + "…"
    }
}
