//
//  RunDraftModelInput.swift
//  ShadowDeck
//
//  Selects mission sections for the on-device model. The heuristic still
//  drafts when the model is unavailable.
//

import Foundation

enum RunDraftModelInput {
    struct Packed: Equatable, Sendable {
        var text: String
        var warnings: [String]
        var includedRewards: Bool
    }

    /// Pack cleaned mission text into a character budget.
    /// Overflow drops Behind the Scenes, then Hooks, then shortens rewards last.
    static func pack(text: String, maxCharacters: Int) -> Packed {
        let budget = max(400, maxCharacters)
        let cleaned = RunDraftHeuristic.clean(text)
        let sections = RunDraftHeuristic.splitSections(cleaned)
        let hasMissionShape = sections.keys.contains { key in
            key.contains("synopsis") || key.contains("scan this") || key.contains("picking up")
        }

        if !hasMissionShape {
            let prefix = String(cleaned.prefix(budget))
            return Packed(
                text: prefix,
                warnings: ["This extract did not look like a mission layout. The model saw a bounded prefix only."],
                includedRewards: false
            )
        }

        let opening = openingSlice(cleaned)
        let synopsis = sectionBody(sections, keys: ["mission synopsis", "mission background & synopsis", "mission background"])
        let scans = numberedBodies(sections, prefix: "scan this")
        let tells = numberedBodies(sections, prefix: "tell it to them straight")
        let pieces = sectionBody(sections, keys: ["picking up the pieces"])
        let behind = numberedBodies(sections, prefix: "behind the scenes")
        let hooks = sectionBody(sections, keys: ["hooks", "pushing the envelope"])

        var warnings: [String] = []
        if pieces == nil {
            warnings.append("No rewards section in range.")
        }

        // Lower dropRank is removed first. Rewards are shortened last, and only down to the
        // payout lines at the start of Picking Up the Pieces.
        var blocks = missionBlocks(
            opening: opening,
            synopsis: synopsis,
            scans: scans,
            tells: tells,
            pieces: pieces,
            behind: behind,
            hooks: hooks
        )

        var droppedBehind = false
        var guardSteps = 0
        while rendered(blocks).count > budget, guardSteps < 12 {
            guardSteps += 1
            guard let index = blocks.indices
                .filter({ blocks[$0].body.count > blocks[$0].minimum })
                .min(by: { blocks[$0].dropRank < blocks[$1].dropRank })
            else { break }

            let block = blocks[index]
            if block.dropRank == 0, !droppedBehind {
                droppedBehind = true
                warnings.append("Behind the Scenes was left out to fit the model window.")
            }
            if block.minimum == 0 {
                blocks[index].body = ""
            } else {
                let overflow = rendered(blocks).count - budget
                let keep = max(block.minimum, block.body.count - overflow)
                blocks[index].body = String(block.body.prefix(keep))
            }
        }

        var textOut = rendered(blocks)
        if textOut.count > budget {
            textOut = fitKeepingRewards(textOut, budget: budget)
        }

        return Packed(text: textOut, warnings: warnings, includedRewards: pieces != nil)
    }

    private struct MissionBlock {
        var heading: String
        var body: String
        var dropRank: Int
        var minimum: Int
    }

    private static func missionBlocks(
        opening: String?,
        synopsis: String?,
        scans: [String],
        tells: [String],
        pieces: String?,
        behind: [String],
        hooks: String?
    ) -> [MissionBlock] {
        var blocks: [MissionBlock] = []
        if let opening, !opening.isEmpty {
            blocks.append(MissionBlock(heading: "OPENING", body: String(opening.prefix(600)), dropRank: 2, minimum: 0))
        }
        if let synopsis, !synopsis.isEmpty {
            blocks.append(MissionBlock(heading: "MISSION SYNOPSIS", body: synopsis, dropRank: 5, minimum: 80))
        }
        if !scans.isEmpty {
            blocks.append(MissionBlock(
                heading: "SCAN THIS",
                body: scans.joined(separator: "\n\n"),
                dropRank: 6,
                minimum: 40
            ))
        }
        if !tells.isEmpty {
            blocks.append(MissionBlock(
                heading: "TELL IT TO THEM STRAIGHT",
                body: tells.joined(separator: "\n\n"),
                dropRank: 3,
                minimum: 0
            ))
        }
        if let pieces, !pieces.isEmpty {
            blocks.append(MissionBlock(
                heading: "PICKING UP THE PIECES",
                body: pieces,
                dropRank: 7,
                minimum: 200
            ))
        }
        let behindBody = String(behind.joined(separator: "\n\n").prefix(500))
        if !behindBody.isEmpty {
            blocks.append(MissionBlock(
                heading: "BEHIND THE SCENES (GM only — do not copy into player-facing fields)",
                body: behindBody,
                dropRank: 0,
                minimum: 0
            ))
        }
        if let hooks, !hooks.isEmpty {
            blocks.append(MissionBlock(heading: "HOOKS", body: String(hooks.prefix(400)), dropRank: 1, minimum: 0))
        }
        return blocks
    }

    private static func rendered(_ blocks: [MissionBlock]) -> String {
        blocks
            .filter { !$0.body.isEmpty }
            .map { "\($0.heading)\n\($0.body)" }
            .joined(separator: "\n\n")
    }

    /// Last resort: keep the rewards block, then the text immediately before it.
    private static func fitKeepingRewards(_ text: String, budget: Int) -> String {
        guard let range = text.range(of: "PICKING UP THE PIECES") else {
            return String(text.prefix(budget))
        }
        let rewards = String(text[range.lowerBound...])
        if rewards.count >= budget {
            return String(rewards.prefix(budget))
        }
        let room = budget - rewards.count
        let prefix = String(text[..<range.lowerBound])
        let keptPrefix = room > 0 ? String(prefix.suffix(room)) : ""
        return (keptPrefix + rewards).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func openingSlice(_ cleaned: String) -> String? {
        let markers = ["mission synopsis", "scan this", "picking up the pieces"]
        let lower = cleaned.lowercased()
        var cut = cleaned.count
        for marker in markers {
            if let range = lower.range(of: marker) {
                cut = min(cut, lower.distance(from: lower.startIndex, to: range.lowerBound))
            }
        }
        let end = cleaned.index(cleaned.startIndex, offsetBy: min(cut, 600), limitedBy: cleaned.endIndex) ?? cleaned.endIndex
        let slice = String(cleaned[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return slice.isEmpty ? nil : slice
    }

    private static func sectionBody(_ sections: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let body = sections[key], !body.isEmpty { return body }
        }
        return nil
    }

    private static func numberedBodies(_ sections: [String: String], prefix: String) -> [String] {
        sections.keys
            .filter { $0.hasPrefix(prefix) }
            .sorted()
            .compactMap { sections[$0] }
            .filter { !$0.isEmpty }
    }
}
