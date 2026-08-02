//
//  RunDraftHeuristic.swift
//  ShadowDeck
//
//  Offline (non-AI) mission PDF → RunDraft parsing.
//  Tuned against Shadowrun Missions living-campaign layout
//  (SRM 5A-xx two-column books with MISSION SYNOPSIS, Scan This,
//  Tell It to Them Straight, Behind the Scenes, PICKING UP THE PIECES).
//

import Foundation

enum RunDraftHeuristic {
    // MARK: - Public entry

    static func draft(
        from text: String,
        fallbackTitle: String
    ) -> RunDraft {
        var warnings: [String] = []
        let cleaned = clean(text)
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("No usable text after cleaning.")
            return RunDraft(
                title: fallbackTitle,
                warnings: warnings,
                usedOnDeviceAI: false
            )
        }

        let sections = splitSections(cleaned)
        let missionCode = extractMissionCode(from: cleaned)
        let title = extractTitle(cleaned: cleaned, code: missionCode, fallback: fallbackTitle)

        let synopsis = firstSection(
            in: sections,
            keys: [
                "mission synopsis",
                "mission background & synopsis",
                "mission background and synopsis",
                "mission background"
            ]
        )
        let scanBlocks = sections
            .filter { $0.key.hasPrefix("scan this") }
            .sorted { $0.key < $1.key }
            .map(\.value)
        let tellBlocks = sections
            .filter { $0.key.hasPrefix("tell it to them straight") }
            .sorted { $0.key < $1.key }
            .map(\.value)
        let behindBlocks = sections
            .filter { $0.key.hasPrefix("behind the scenes") }
            .sorted { $0.key < $1.key }
            .map(\.value)
        let pickingUp = firstSection(
            in: sections,
            keys: ["picking up the pieces", "money", "karma"]
        )

        // Player-facing: Scan This (plot beat) + Tell It (what they hear) — not the full GM synopsis.
        var playerFacingParts: [String] = []
        if let first = scanBlocks.first, first.count > 20 {
            playerFacingParts.append(prose(first))
        }
        if let first = tellBlocks.first, first.count > 40 {
            playerFacingParts.append(prose(first))
        }
        if playerFacingParts.isEmpty, let synopsis, !synopsis.isEmpty {
            // Fall back to first few synopsis paragraphs (often the hire setup).
            playerFacingParts.append(firstParagraphs(prose(synopsis), maxChars: 2_400))
            warnings.append("No Scene “Tell It to Them Straight” found — used Mission Synopsis for player-facing text.")
        }
        let playerFacing = playerFacingParts.joined(separator: "\n\n")

        var objectives = extractObjectives(
            scanBlocks: scanBlocks,
            synopsis: synopsis ?? "",
            cleaned: cleaned
        ).map { prose($0) }.filter { !$0.isEmpty }
        if objectives.isEmpty {
            warnings.append("No clear objectives found — add them manually from Scan This / synopsis.")
        }

        let client = prose(extractClient(from: cleaned, tell: tellBlocks.first ?? "", behind: behindBlocks.first ?? ""))
        let location = prose(extractLocation(from: cleaned))
        let knownRisks = prose(extractRisks(
            scanBlocks: scanBlocks,
            synopsis: synopsis ?? "",
            behind: behindBlocks.prefix(2).joined(separator: "\n")
        ))
        let opposition = prose(extractOpposition(
            behind: behindBlocks.prefix(3).joined(separator: "\n\n"),
            synopsis: synopsis ?? "",
            cleaned: cleaned
        ))
        let (nuyen, karma) = extractPayout(from: cleaned, pickingUp: pickingUp ?? "")
        let reputation = extractReputation(from: cleaned, pickingUp: pickingUp ?? "")

        // GM notes: mission background only — no markdown headers, no full PDF dump,
        // no NPC stat blocks (those look like "B A R S W …" noise in the review sheet).
        var gmParts: [String] = []
        if let synopsis, !synopsis.isEmpty {
            gmParts.append(firstParagraphs(prose(stripStatBlocks(synopsis)), maxChars: 3_500))
        }
        if let first = behindBlocks.first, !first.isEmpty {
            let behind = firstParagraphs(prose(stripStatBlocks(first)), maxChars: 2_000)
            if !behind.isEmpty, behind != gmParts.last {
                gmParts.append(behind)
            }
        }
        var gmNotes = gmParts.joined(separator: "\n\n")
        if gmNotes.isEmpty {
            gmNotes = firstParagraphs(prose(stripStatBlocks(cleaned)), maxChars: 2_500)
            warnings.append("Could not isolate Mission Synopsis — GM notes are a trimmed extract.")
        }

        if playerFacing.isEmpty {
            warnings.append("Could not isolate a briefing — check GM notes.")
        }

        return RunDraft(
            title: prose(title),
            missionCode: missionCode,
            client: client,
            location: location,
            objectives: objectives,
            oppositionSummary: opposition,
            expectedPayoutNuyen: nuyen,
            expectedKarma: karma,
            expectedStreetCred: reputation.streetCred,
            expectedNotoriety: reputation.notoriety,
            expectedPublicAwareness: reputation.publicAwareness,
            reputationNotes: reputation.notes,
            playerFacingSummary: playerFacing,
            knownRisks: knownRisks,
            gmNotes: gmNotes,
            warnings: warnings,
            usedOnDeviceAI: false
        )
    }

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

    private static func looksLikeStatBlockLine(_ line: String) -> Bool {
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

    private static func looksLikeStatBlockContinuation(_ line: String) -> Bool {
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
    private static func stripSidebarTOC(_ text: String) -> String {
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

    private static func stripBoilerplateBlocks(_ text: String) -> String {
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

    // MARK: - Section split

    /// Map lowercased header → body text.
    static func splitSections(_ text: String) -> [String: String] {
        // Built in pieces so SwiftLint line_length stays under the hard cap.
        let headerPattern =
            #"(?mi)^(?:"#
            + #"MISSION\s+SYNOPSIS|"#
            + #"MISSION\s+BACKGROUND(?:\s*&\s*SYNOPSIS)?|"#
            + #"MISSION\s+BACKGROUND\s+AND\s+SYNOPSIS|"#
            + #"PICKING\s+UP\s+THE\s+PIECES|"#
            + #"CAST\s+OF\s+SHADOWS|"#
            + #"PLAYER\s+HANDOUTS|"#
            + #"LEGWORK|"#
            + #"Scan\s+This|"#
            + #"Tell\s+It\s+to\s+Them\s+Straight|"#
            + #"Behind\s+the\s+Scenes|"#
            + #"Pushing\s+the\s+Envelope|"#
            + #"Debugging|"#
            + #"SCENE\s+\d+[A-Z]?(?:\s*:\s*.+)?"#
            + #")\s*$"#

        guard let regex = try? NSRegularExpression(pattern: headerPattern) else {
            return ["body": text]
        }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, range: full)
        guard !matches.isEmpty else {
            return ["body": text]
        }

        var result: [String: String] = [:]
        var scanIndex = 0
        var tellIndex = 0
        var behindIndex = 0

        for (i, match) in matches.enumerated() {
            let header = ns.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyStart = match.range.upperBound
            let bodyEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            guard bodyEnd > bodyStart else { continue }
            let body = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }

            let keyBase = header.lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

            let key: String
            if keyBase.hasPrefix("scan this") {
                scanIndex += 1
                key = "scan this \(scanIndex)"
            } else if keyBase.hasPrefix("tell it to them straight") {
                tellIndex += 1
                key = "tell it to them straight \(tellIndex)"
            } else if keyBase.hasPrefix("behind the scenes") {
                behindIndex += 1
                key = "behind the scenes \(behindIndex)"
            } else if keyBase.hasPrefix("scene") {
                key = keyBase
            } else {
                // Normalize mission background variants.
                if keyBase.contains("mission background") && keyBase.contains("synopsis") {
                    key = "mission background & synopsis"
                } else if keyBase.hasPrefix("mission background") {
                    key = "mission background"
                } else if keyBase.hasPrefix("mission synopsis") {
                    key = "mission synopsis"
                } else if keyBase.hasPrefix("picking up") {
                    key = "picking up the pieces"
                } else {
                    key = keyBase
                }
            }

            if let existing = result[key], !existing.isEmpty {
                result[key] = existing + "\n\n" + body
            } else {
                result[key] = body
            }
        }
        return result
    }

    private static func firstSection(in sections: [String: String], keys: [String]) -> String? {
        for k in keys {
            if let v = sections[k], !v.isEmpty { return v }
        }
        return nil
    }

    // MARK: - Field extractors

    static func extractMissionCode(from text: String) -> String? {
        // SRM 5A-01, SRM 05-05, SRM 5A–01 (en dash)
        let patterns = [
            #"SRM\s*\d+[A-Za-z]?\s*[-–—]?\s*\d+[A-Za-z]?"#,
            #"SRM\s+\d+[A-Za-z]?-\d+"#
        ]
        for p in patterns {
            if let r = text.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                var code = String(text[r])
                code = code
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "–", with: "-")
                    .replacingOccurrences(of: "—", with: "-")
                    .trimmingCharacters(in: .whitespaces)
                // Normalize "SRM 5A-01"
                if let m = code.range(
                    of: #"SRM\s*(\d+[A-Za-z]?)\s*-?\s*(\d+)"#,
                    options: [.regularExpression, .caseInsensitive]
                ) {
                    let raw = String(code[m])
                    let parts = raw
                        .uppercased()
                        .replacingOccurrences(of: "SRM", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .split { !$0.isLetter && !$0.isNumber }
                        .map(String.init)
                    if parts.count >= 2 {
                        return "SRM \(parts[0])-\(parts[1])"
                    }
                }
                return code
            }
        }
        return nil
    }

    private static func extractTitle(cleaned: String, code: String?, fallback: String) -> String {
        // Prefer "SRM 5A-01: Chasin' the Wind"
        if let r = cleaned.range(
            of: #"SRM\s*\d+[A-Za-z]?[-–—]?\d+\s*:\s*[^\n]{3,80}"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            var line = String(cleaned[r])
            line = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            // Often continues with "is a Shadowrun Missions" — cut at that.
            if let cut = line.range(of: #"\s+is\s+a\s+Shadowrun"#, options: [.regularExpression, .caseInsensitive]) {
                line = String(line[..<cut.lowerBound])
            }
            if let cut = line.range(of: #"\s+is\s+intended"#, options: [.regularExpression, .caseInsensitive]) {
                line = String(line[..<cut.lowerBound])
            }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Scene 1 titles sometimes carry the adventure name in the header area.
        if let code {
            // "SRM 5A-01" alone → use fallback with code
            let base = fallback
                .replacingOccurrences(of: #"\.pdf$"#, with: "", options: .regularExpression)
            if base.localizedCaseInsensitiveContains(code.replacingOccurrences(of: "SRM ", with: ""))
                || base.count > 8 {
                return base
            }
            return "\(code): \(base)"
        }
        return fallback
    }

    private static func extractClient(from cleaned: String, tell: String, behind: String) -> String {
        let pool = [tell, behind, cleaned].joined(separator: "\n")
        // "know me as Quantum Princess" / "Mr. Johnson" named
        if let r = pool.range(
            of: #"know me as\s+([A-Z][A-Za-z0-9'’\-]+(?:\s+[A-Z][A-Za-z0-9'’\-]+)?)"#,
            options: .regularExpression
        ) {
            let s = String(pool[r])
            if let asRange = s.range(of: "as ", options: .caseInsensitive) {
                return String(s[asRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        // "hired by X" / "job from X"
        let hirePatterns = [
            #"hired by\s+([A-Z][A-Za-z0-9'’\-]+(?:\s+[A-Z][A-Za-z0-9'’\-]+)?)"#,
            #"job from\s+([A-Z][A-Za-z0-9'’\-]+(?:\s+[A-Z][A-Za-z0-9'’\-]+)?)"#,
            #"contacted by\s+(?:a\s+frantic\s+)?([A-Z][A-Za-z0-9'’\-]+)"#,
            #"Ms\.\s*Johnson"#,
            #"Mr\.\s*Johnson"#,
            #"meet with\s+([A-Z][A-Za-z0-9'’\-]+)"#
        ]
        for p in hirePatterns {
            if let r = pool.range(of: p, options: .regularExpression) {
                var s = String(pool[r])
                if s.localizedCaseInsensitiveContains("johnson") {
                    // Prefer a proper name nearby if "Ms. Johnson is already there. She is ..."
                    return s.trimmingCharacters(in: .whitespaces)
                }
                if let last = s.split(separator: " ").last.map(String.init) {
                    // Avoid generic verbs
                    if !["the", "a", "an"].contains(last.lowercased()) {
                        // Extract capture more carefully
                        if s.lowercased().hasPrefix("hired by") {
                            return String(s.dropFirst("hired by".count)).trimmingCharacters(in: .whitespaces)
                        }
                        if s.lowercased().hasPrefix("job from") {
                            return String(s.dropFirst("job from".count)).trimmingCharacters(in: .whitespaces)
                        }
                        if s.lowercased().contains("contacted by") {
                            return last
                        }
                        if s.lowercased().hasPrefix("meet with") {
                            return String(s.dropFirst("meet with".count)).trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
                return s
            }
        }
        // Sid as Johnson pattern
        if pool.localizedCaseInsensitiveContains("sid is looking to make a name")
            || pool.range(of: #"\bSid\b.*\bJohnson\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "Sid"
        }
        return ""
    }

    private static func extractLocation(from text: String) -> String {
        let lower = text.lowercased()
        var parts: [String] = []
        if lower.contains("containment zone") || lower.contains(" the cz") || lower.contains("in the cz") {
            parts.append("Chicago Containment Zone")
        } else if lower.contains("chicago") {
            parts.append("Chicago")
        }
        if lower.contains("seattle") { parts.append("Seattle") }
        if lower.contains("denver") { parts.append("Denver") }
        if lower.contains("neo-tokyo") || lower.contains("neo tokyo") { parts.append("Neo-Tokyo") }

        // Named meet site from Scene 1.
        if let r = text.range(
            of: #"(?:reserved at|meet(?:ing)? at|table reserved at)\s+([A-Z][^.\n]{3,60})"#,
            options: .regularExpression
        ) {
            var site = String(text[r])
            if let at = site.range(of: " at ", options: .caseInsensitive) {
                site = String(site[at.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Cut trailing clause
                if let comma = site.firstIndex(of: ".") {
                    site = String(site[..<comma])
                }
                if site.count > 3, site.count < 80 {
                    parts.append(site)
                }
            }
        }

        // De-dupe preserving order.
        var seen = Set<String>()
        let unique = parts.filter {
            let k = $0.lowercased()
            if seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
        return unique.joined(separator: " · ")
    }

    private static func extractObjectives(
        scanBlocks: [String],
        synopsis: String,
        cleaned: String
    ) -> [String] {
        var objectives: [String] = []

        // Scan This blocks are short GM summaries of scene goals — best objective source.
        for block in scanBlocks.prefix(8) {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 24 else { continue }
            // First 1–2 sentences.
            let sentence = firstSentences(trimmed, max: 2, maxChars: 320)
            if sentence.count >= 20 {
                objectives.append(sentence)
            }
        }

        // "hire the runners to X" / "wants the runners to X"
        if let regex = try? NSRegularExpression(
            pattern: #"(?:hire[sd]?|wants?|need(?:s)?|ask(?:s|ing)?)\s+(?:the\s+)?runners\s+to\s+([^.]{10,180})"#,
            options: .caseInsensitive
        ) {
            let ns = cleaned as NSString
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
            for m in matches.prefix(6) {
                guard m.numberOfRanges >= 2 else { continue }
                var goal = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard goal.count >= 10 else { continue }
                if !goal.hasPrefix("To ") && !goal.hasPrefix("to ") {
                    goal = "To " + goal
                } else if goal.hasPrefix("to ") {
                    goal = "To " + goal.dropFirst(3)
                }
                objectives.append(String(goal.prefix(280)))
            }
        }

        // Bullet / numbered lists.
        for line in cleaned.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.range(of: #"^[•\-\*]\s+\S.{8,}"#, options: .regularExpression) != nil
                || t.range(of: #"^\d+[\.\)]\s+\S.{8,}"#, options: .regularExpression) != nil {
                var cleanedLine = t.replacingOccurrences(
                    of: #"^[•\-\*\d\.\)\s]+"#,
                    with: "",
                    options: .regularExpression
                )
                cleanedLine = cleanedLine.trimmingCharacters(in: .whitespaces)
                // Skip reward bullets
                let lower = cleanedLine.lowercased()
                if lower.contains("nuyen") && lower.contains("net hit") { continue }
                if lower.hasPrefix("karma") || lower.contains("street cred") { continue }
                if cleanedLine.count >= 12, cleanedLine.count <= 280 {
                    objectives.append(cleanedLine)
                }
            }
            if objectives.count >= 16 { break }
        }

        return dedupe(objectives).prefix(12).map { String($0) }
    }

    private static func extractRisks(scanBlocks: [String], synopsis: String, behind: String) -> String {
        let pool = (scanBlocks + [synopsis, behind]).joined(separator: "\n\n")
        let keywords = [
            "danger", "risk", "threat", "gang", "go-gang", "security", "patrol",
            "bug", "spirit", "noise", "background count", "containment zone",
            "lone star", "knight errant", "ambush", "hostile", "combat",
            "blackmail", "deadline", "short time", "frantic"
        ]
        var hits: [String] = []
        for para in paragraphs(pool) {
            let lower = para.lowercased()
            guard para.count >= 40, para.count <= 600 else { continue }
            if keywords.contains(where: { lower.contains($0) }) {
                hits.append(para)
            }
            if hits.count >= 8 { break }
        }
        // Prefer scan-this sentences about encounters.
        return dedupe(hits).prefix(6).joined(separator: "\n\n")
    }

    private static func extractOpposition(behind: String, synopsis: String, cleaned: String) -> String {
        let pool = [behind, synopsis].joined(separator: "\n\n")
        if pool.count > 80 {
            // Pull sentences with force/security/gang nouns.
            let keywords = [
                "guard", "security", "ganger", "gang", "go-gang", "fleshmonger",
                "spirit", "mage", "samurai", "drone", "knight errant", "lone star",
                "corpsec", "soldier", "thug", "boyz", "horde", "angel"
            ]
            var hits: [String] = []
            for sentence in sentences(pool) {
                let lower = sentence.lowercased()
                if sentence.count < 30 || sentence.count > 400 { continue }
                if keywords.contains(where: { lower.contains($0) }) {
                    hits.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if hits.count >= 8 { break }
            }
            if !hits.isEmpty {
                return dedupe(hits).joined(separator: " ")
            }
            return firstParagraphs(behind.isEmpty ? synopsis : behind, maxChars: 1_200)
        }
        return ""
    }

    private struct ReputationExtract {
        var streetCred: Int?
        var notoriety: Int?
        var publicAwareness: Int?
        var notes: String
    }

    /// From Picking Up the Pieces: “+1 Street Cred if…”, etc.
    private static func extractReputation(from cleaned: String, pickingUp: String) -> ReputationExtract {
        let pool = pickingUp.isEmpty ? cleaned : pickingUp + "\n" + cleaned
        var notes: [String] = []
        var streetCred: Int?
        var notoriety: Int?
        var publicAwareness: Int?

        // Collect bullet-style reputation lines.
        for line in pool.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            let lower = t.lowercased()
            guard lower.contains("street cred")
                || lower.contains("notoriety")
                || lower.contains("public awareness") else { continue }
            // Skip generic rules blurb.
            if lower.contains("p. 372") || lower.contains("gamemasters should consider") {
                continue
            }
            guard t.range(of: #"[\+\-]?\s*\d+"#, options: .regularExpression) != nil else { continue }

            var cleanedLine = t.replacingOccurrences(
                of: #"^[•\-\*\s]+"#,
                with: "",
                options: .regularExpression
            )
            cleanedLine = prose(cleanedLine)
            if cleanedLine.count < 8 || cleanedLine.count > 280 { continue }
            notes.append(cleanedLine)

            if let n = firstSignedInt(in: cleanedLine) {
                if lower.contains("street cred") {
                    streetCred = max(streetCred ?? n, n)
                } else if lower.contains("notoriety") {
                    notoriety = max(notoriety ?? n, n)
                } else if lower.contains("public awareness") {
                    publicAwareness = max(publicAwareness ?? n, n)
                }
            }
        }

        return ReputationExtract(
            streetCred: streetCred,
            notoriety: notoriety,
            publicAwareness: publicAwareness,
            notes: dedupe(notes).prefix(8).joined(separator: "\n")
        )
    }

    private static func firstSignedInt(in text: String) -> Int? {
        guard let r = text.range(of: #"[\+\-]?\d+"#, options: .regularExpression) else { return nil }
        return Int(String(text[r]).replacingOccurrences(of: "+", with: ""))
    }

    private static func extractPayout(from cleaned: String, pickingUp: String) -> (Int?, Int?) {
        var nuyen: Int?
        var karma: Int?

        // Prefer explicit adventure totals.
        if let r = cleaned.range(
            of: #"Nuyen Earned:\s*([\d,]+)\s*¥?"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let digits = String(cleaned[r]).filter(\.isNumber)
            if let v = Int(digits), v > 0 { nuyen = v }
        }
        if let r = cleaned.range(
            of: #"Karma Earned:\s*(\d+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let digits = String(cleaned[r]).filter(\.isNumber)
            if let v = Int(digits), v > 0, v < 40 { karma = v }
        }

        // Primary job offer: "4,000 nuyen each" / "offering 4,000 nuyen" / "¥12,000"
        if nuyen == nil {
            let offerPatterns = [
                #"offer(?:s|ing)?\s+(?:the\s+runners\s+)?([\d,]+)\s*nuyen\s+each"#,
                #"([\d,]+)\s*nuyen\s+each"#,
                #"offer(?:s|ing)?\s+([\d,]+)\s*nuyen"#,
                #"pay(?:s|ing)?\s+(?:you\s+)?(?:each\s+)?([\d,]+)\s*nuyen"#,
                #"¥\s*([\d,]+)"#,
                #"([\d,]+)\s*¥"#,
                #"([\d,]+)\s*nuyen"#
            ]
            for p in offerPatterns {
                if let r = cleaned.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                    let digits = String(cleaned[r]).filter(\.isNumber)
                    if let v = Int(digits), v >= 500, v <= 500_000 {
                        nuyen = v
                        break
                    }
                }
            }
        }

        // "maximum adventure award ... is 6" / "4 karma"
        if karma == nil {
            if let r = cleaned.range(
                of: #"maximum adventure award[^\d]{0,40}(\d+)"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let digits = String(cleaned[r]).filter(\.isNumber)
                if let v = Int(digits), v > 0, v < 40 { karma = v }
            }
        }
        if karma == nil {
            if let r = cleaned.range(
                of: #"\b(\d+)\s*karma\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let digits = String(cleaned[r]).filter(\.isNumber)
                if let v = Int(digits), v > 0, v < 40 { karma = v }
            }
        }

        // Scan picking-up block for first money bullet if still empty.
        if nuyen == nil, !pickingUp.isEmpty {
            if let r = pickingUp.range(
                of: #"([\d,]+)\s*nuyen\s+each"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let digits = String(pickingUp[r]).filter(\.isNumber)
                if let v = Int(digits), v >= 500 { nuyen = v }
            }
        }

        return (nuyen, karma)
    }

    // MARK: - Text helpers

    private static func paragraphs(_ text: String) -> [String] {
        text
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func sentences(_ text: String) -> [String] {
        // Simple split; good enough for heuristic.
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
        var result: [String] = []
        var current = ""
        for ch in normalized {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count > 15 { result.append(t) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count > 15 { result.append(tail) }
        return result
    }

    private static func firstSentences(_ text: String, max: Int, maxChars: Int) -> String {
        let parts = sentences(text).prefix(max)
        var out = ""
        for s in parts {
            if out.isEmpty {
                out = s
            } else if out.count + s.count + 1 <= maxChars {
                out += " " + s
            } else {
                break
            }
        }
        if out.isEmpty {
            return String(text.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    private static func firstParagraphs(_ text: String, maxChars: Int) -> String {
        var out = ""
        for p in paragraphs(text) {
            if out.isEmpty {
                out = p
            } else if out.count + p.count + 2 <= maxChars {
                out += "\n\n" + p
            } else {
                break
            }
        }
        if out.count > maxChars {
            return String(out.prefix(maxChars))
        }
        return out
    }

    private static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter {
            let key = $0.lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if seen.contains(key) { return false }
            // Near-duplicate: prefix match
            if seen.contains(where: { key.hasPrefix($0.prefix(40)) || $0.hasPrefix(key.prefix(40)) }) {
                return false
            }
            seen.insert(key)
            return true
        }
    }
}
