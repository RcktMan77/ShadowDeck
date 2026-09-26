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

        let objectives = extractObjectives(
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
            + #"Hooks|"#
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


}
