//
//  PlayerBriefingMarkdown.swift
//  ShadowDeck
//
//  Pure player-safe briefing render for Run Tracker Phase 2E.
//  Intentionally omits GM notes, full opposition, complications, heat, awards math.
//

import Foundation

public enum PlayerBriefingMarkdown {
    public struct Options: Sendable, Hashable {
        /// Include secondary objectives in the briefing.
        public var includeSecondaryObjectives: Bool
        /// When true, omit objectives marked failed (post-run spoiler hygiene).
        public var hideFailedObjectives: Bool

        public init(
            includeSecondaryObjectives: Bool = true,
            hideFailedObjectives: Bool = true
        ) {
            self.includeSecondaryObjectives = includeSecondaryObjectives
            self.hideFailedObjectives = hideFailedObjectives
        }

        public static let `default` = Options()
    }

    /// Markdown suitable for paste to players / Discord / notes.
    public static func render(_ run: Run, options: Options = .default) -> String {
        var lines: [String] = []

        let title = run.title.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("# \(title.isEmpty ? "Untitled Job" : title)")
        lines.append("")
        lines.append("_What runners know — GM-only prep is not included._")
        lines.append("")

        // Meta
        let client = run.displayClientName
        if !client.isEmpty {
            lines.append("**Client:** \(client)")
        }
        let location = run.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty {
            lines.append("**Location:** \(location)")
        }
        if !run.tags.isEmpty {
            lines.append("**Tags:** \(run.tags.joined(separator: ", "))")
        }
        lines.append("**Status:** \(run.status.displayName)")
        lines.append("")

        // Player-facing summary
        let summary = run.playerFacingSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            lines.append("## What you know")
            lines.append("")
            lines.append(summary)
            lines.append("")
        }

        // Objectives
        let primary = filteredObjectives(run.primaryObjectives, hideFailed: options.hideFailedObjectives)
        let secondary = options.includeSecondaryObjectives
            ? filteredObjectives(run.secondaryObjectives, hideFailed: options.hideFailedObjectives)
            : []

        if !primary.isEmpty || !secondary.isEmpty {
            lines.append("## Objectives")
            lines.append("")
            if !primary.isEmpty {
                lines.append("### Primary")
                lines.append("")
                for obj in primary {
                    lines.append("- \(objectiveLine(obj))")
                }
                lines.append("")
            }
            if !secondary.isEmpty {
                lines.append("### Secondary")
                lines.append("")
                for obj in secondary {
                    lines.append("- \(objectiveLine(obj))")
                }
                lines.append("")
            }
        }

        // Pay (simple totals only — no per-runner split / award math)
        let payLines = payoutLines(run)
        if !payLines.isEmpty {
            lines.append("## Pay")
            lines.append("")
            lines.append(contentsOf: payLines)
            lines.append("")
        }

        // Known risks (player-safe; not full opposition)
        let risks = run.knownRisks.trimmingCharacters(in: .whitespacesAndNewlines)
        if !risks.isEmpty {
            lines.append("## Known risks")
            lines.append("")
            lines.append(risks)
            lines.append("")
        }

        lines.append("---")
        lines.append("")
        lines.append(
            "_Omitted from this briefing: GM notes, full opposition, complications, session heat, award splits, and contact secrets._"
        )

        return lines.joined(separator: "\n")
    }

    // MARK: - Internals

    private static func filteredObjectives(
        _ objectives: [RunObjective],
        hideFailed: Bool
    ) -> [RunObjective] {
        objectives.filter { obj in
            let text = obj.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            if hideFailed, obj.status == .failed { return false }
            return true
        }
    }

    private static func objectiveLine(_ obj: RunObjective) -> String {
        let text = obj.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Status only when not pending — still player-safe (complete / pending).
        switch obj.status {
        case .pending:
            return text
        case .complete:
            return "\(text) _(complete)_"
        case .failed:
            return "\(text) _(failed)_"
        }
    }

    private static func payoutLines(_ run: Run) -> [String] {
        var lines: [String] = []
        let expected = run.expectedPayout
        if !expected.isZero {
            lines.append("**Expected:** \(formatPayout(expected))")
        }
        if let actual = run.actualPayout, !actual.isZero {
            lines.append("**Actual:** \(formatPayout(actual))")
        }
        return lines
    }

    private static func formatPayout(_ p: RunPayout) -> String {
        "¥\(p.nuyen.formatted()) + \(p.karma) karma"
    }
}
