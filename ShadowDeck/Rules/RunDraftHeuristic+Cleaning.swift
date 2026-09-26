//
//  RunDraftHeuristic+Cleaning.swift
//  ShadowDeck
//
//  TOC, stat-block, and boilerplate cleanup. Same type as RunDraftHeuristic.
//
import Foundation

extension RunDraftHeuristic {
    // MARK: - Cleaning (SRM two-column / TOC noise)

    static func clean(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "\u{0c}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Drop our own page labels if present.
        s = s
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--- Page") }
            .joined(separator: "\n")

        // DriveThru / order watermarks.
        s = s.replacingOccurrences(
            of: #"(?m)^.*\(order\s*#\d+\).*$"#,
            with: "",
            options: .regularExpression
        )

        // Rejoin common multi-line section titles split by layout.
        let rejoins: [(String, String)] = [
            (#"MISSION\s*\n\s*SYNOPSIS"#, "MISSION SYNOPSIS"),
            (#"MISSION\s*\n\s*BACKGROUND\s*\n\s*&\s*\n\s*SYNOPSIS"#, "MISSION BACKGROUND & SYNOPSIS"),
            (#"MISSION\s*\n\s*BACKGROUND\s*&\s*\n\s*SYNOPSIS"#, "MISSION BACKGROUND & SYNOPSIS"),
            (#"MISSION\s*\n\s*BACKGROUND"#, "MISSION BACKGROUND"),
            (#"PICKING UP\s*\n\s*THE PIECES"#, "PICKING UP THE PIECES"),
            (#"CAST OF\s*\n\s*SHADOWS"#, "CAST OF SHADOWS"),
            (#"PLAYER\s*\n\s*HANDOUTS"#, "PLAYER HANDOUTS"),
            (#"DEBRIEFING\s*\n\s*LOG"#, "DEBRIEFING LOG"),
            (#"BEHIND THE\s*\n\s*SCENES"#, "Behind the Scenes"),
            (#"TELL IT TO THEM\s*\n\s*STRAIGHT"#, "Tell It to Them Straight"),
            (#"PUSHING THE\s*\n\s*ENVELOPE"#, "Pushing the Envelope"),
            (#"SCAN\s*\n\s*THIS"#, "Scan This")
        ]
        for (pattern, replacement) in rejoins {
            s = s.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        s = stripSidebarTOC(s)
        s = stripBoilerplateBlocks(s)
        s = stripStatBlocks(s)

        // Left-justify: PDF two-column extract often pads lines with leading spaces.
        s = s
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        // Collapse 3+ blank lines.
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drop NPC attribute blocks and similar Cast-of-Shadows noise.
    static func stripStatBlocks(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var kept: [String] = []
        var skippingBlock = false

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                skippingBlock = false
                kept.append("")
                continue
            }
            if looksLikeStatBlockLine(t) {
                skippingBlock = true
                continue
            }
            // Continuation of a stat block (pure numbers / dice pools).
            if skippingBlock, looksLikeStatBlockContinuation(t) {
                continue
            }
            skippingBlock = false
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    static func looksLikeStatBlockLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        let upper = t.uppercased()
        // Classic SR attribute header / row: "B A R S W L I C M EDG ESS"
        if upper.range(
            of: #"\bB\b.*\bA\b.*\bR\b.*\bS\b.*\bW\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if upper.range(of: #"\bEDG\b.*\bESS\b|\bESS\b.*\bEDG\b"#, options: .regularExpression) != nil {
            return true
        }
        // Dense single-letter attribute soup with numbers.
        if t.range(
            of: #"^(?:[BARSWLICM]\s+){4,}(?:EDG|ESS|\d)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        let lower = t.lowercased()
        if lower.hasPrefix("condition monitor")
            || lower.hasPrefix("initiative:")
            || lower.hasPrefix("astral initiative")
            || lower.hasPrefix("matrix initiative")
            || lower.hasPrefix("limits:")
            || lower.hasPrefix("dice pools:")
            || lower.hasPrefix("qualities:")
            || lower.hasPrefix("augmentations:")
            || lower.hasPrefix("gear:")
            || lower.hasPrefix("weapons:")
            || lower.hasPrefix("spells:")
            || lower.hasPrefix("powers:") {
            return true
        }
        return false
    }

    static func looksLikeStatBlockContinuation(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        // Mostly digits / short tokens: "2 7 8 1 4 4 4 4 2 4 4" or "12 + 1D6"
        if t.range(of: #"^[\d\s\+\(\)D6d×x/\-–—\.]+$"#, options: .regularExpression) != nil,
           t.count >= 5 {
            return true
        }
        if t.range(of: #"^\d+(\(\d+\))?(/\d+(\(\d+\))?)?\s*$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Normalize prose for UI: left-aligned, no giant indent, collapsed spaces.
    static func prose(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove pure navigation rails (COVER / SCENE n / LEGWORK stacks).
    /// Do **not** strip real section headers like "MISSION SYNOPSIS" or "Scan This".
    static func stripSidebarTOC(_ text: String) -> String {
        // Only drop short TOC-only tokens, not full section titles used for parsing.
        let navExact: Set<String> = [
            "cover", "intro",
            "legwork", "picking up", "the pieces",
            "cast of", "shadows",
            "player", "handouts",
            "debriefing log", "debriefing"
        ]

        let lines = text.components(separatedBy: .newlines)
        var kept: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            // Bare "SCENE 3" in a sidebar rail — but keep "SCENE 1: TITLE"
            let isBareSceneNav = lower.range(of: #"^scene\s+\d+[a-z]?$"#, options: .regularExpression) != nil
            let isNav = navExact.contains(lower) || isBareSceneNav

            if isNav {
                continue
            }
            // Lone page numbers.
            if trimmed.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    static func stripBoilerplateBlocks(_ text: String) -> String {
        // Drop long GM how-to blocks that appear before the real synopsis.
        let cutHeaders = [
            "PREPARING THE ADVENTURE",
            "RUNNING THE ADVENTURE",
            "GENERAL ADVENTURE RULES",
            "BACKGROUND COUNTS",
            "Paperwork",
            "Step 1: Read The Adventure",
            "Step 2: Take Notes",
            "Step 3: Know The Characters",
            "Step 4: Don’t Panic",
            "Step 4: Don't Panic",
            "Step 5: Challenge the Players",
            "A Note on Loot and Looting",
            "Chicago, The CZ, Noise, and"
        ]
        // Keep everything; only blank out known boilerplate *until* MISSION SYNOPSIS if present.
        guard let synopsisRange = text.range(
            of: #"MISSION SYNOPSIS|MISSION BACKGROUND"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return text
        }

        let prefix = String(text[..<synopsisRange.lowerBound])
        let suffix = String(text[synopsisRange.lowerBound...])

        // If prefix is mostly intro boilerplate, drop it (keep short fiction only if tiny).
        let lowerPrefix = prefix.lowercased()
        let looksLikeIntro =
            lowerPrefix.contains("preparing the")
            || lowerPrefix.contains("running the adventure")
            || lowerPrefix.contains("general adventure rules")
            || lowerPrefix.contains("background counts")
            || lowerPrefix.contains("shadowrun missions living campaign")
            || lowerPrefix.contains("paperwork")

        if looksLikeIntro && prefix.count > 400 {
            // Optionally keep a short cover-fiction teaser? Prefer starting at synopsis.
            _ = cutHeaders
            return suffix
        }
        return text
    }
}
