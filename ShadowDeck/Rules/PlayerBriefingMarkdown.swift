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
        /// When true, omit objectives marked failed.
        public var hideFailedObjectives: Bool
        /// When true, annotate objectives with complete/failed (post-run debrief style).
        public var showObjectiveProgress: Bool
        /// Display names for linked runners (optional one-line team roster).
        public var teamNames: [String]

        public init(
            includeSecondaryObjectives: Bool = true,
            hideFailedObjectives: Bool = true,
            showObjectiveProgress: Bool = false,
            teamNames: [String] = []
        ) {
            self.includeSecondaryObjectives = includeSecondaryObjectives
            self.hideFailedObjectives = hideFailedObjectives
            self.showObjectiveProgress = showObjectiveProgress
            self.teamNames = teamNames
        }

        public static let `default` = Self()

        /// Defaults that match UI: progress off for planning/active, on for terminal runs.
        public static func defaults(for status: RunStatus, teamNames: [String] = []) -> Self {
            Self(
                includeSecondaryObjectives: true,
                hideFailedObjectives: true,
                showObjectiveProgress: status.isTerminal,
                teamNames: teamNames
            )
        }
    }

    /// Markdown suitable for paste to players / Discord / notes.
    public static func render(_ run: Run, options: Options = .default) -> String {
        var lines: [String] = []

        let title = displayTitle(run.title)
        lines.append("# \(title.isEmpty ? "Untitled Job" : title)")
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

        let team = options.teamNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !team.isEmpty {
            lines.append("**Runners:** \(team.joined(separator: ", "))")
        }
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
                    lines.append("- \(objectiveLine(obj, showProgress: options.showObjectiveProgress))")
                }
                lines.append("")
            }
            if !secondary.isEmpty {
                lines.append("### Secondary")
                lines.append("")
                for obj in secondary {
                    lines.append("- \(objectiveLine(obj, showProgress: options.showObjectiveProgress))")
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

        // Known risks (player-safe; not full opposition) — after pay
        let risks = run.knownRisks.trimmingCharacters(in: .whitespacesAndNewlines)
        if !risks.isEmpty {
            lines.append("## Known risks")
            lines.append("")
            lines.append(risks)
            lines.append("")
        }

        // Trim trailing blank lines for clean paste / PDF.
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Ensure readable spacing after a colon (e.g. `SRM 05-01: Chasing the Wind`).
    public static func displayTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Normalize `:` / `:  ` / missing space → single space after each colon.
        guard let regex = try? NSRegularExpression(pattern: ":\\s*") else { return trimmed }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: ": ")
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

    private static func objectiveLine(_ obj: RunObjective, showProgress: Bool) -> String {
        let text = obj.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard showProgress else { return text }
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
