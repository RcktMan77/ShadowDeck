//
//  PlayerBriefingView.swift
//  ShadowDeck
//
//  Read-only player-safe briefing sheet (Phase 2E) with Copy Markdown.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Payload for `sheet(item:)` so the briefing never presents empty content.
struct PlayerBriefingPresentation: Identifiable, Hashable {
    let id = UUID()
    var run: Run
    /// Display titles for linked team members (order preserved).
    var teamNames: [String] = []
}

struct PlayerBriefingView: View {
    let run: Run
    var teamNames: [String] = []
    var onDismiss: () -> Void

    @State private var includeSecondary = true
    @State private var hideFailed = true
    /// Progress chips / complete labels — off for pre-run handouts by default.
    @State private var showProgress = false
    @State private var copyStatus: String?
    @State private var didConfigureDefaults = false
    @State private var exportError: String?

    private var options: PlayerBriefingMarkdown.Options {
        PlayerBriefingMarkdown.Options(
            includeSecondaryObjectives: includeSecondary,
            hideFailedObjectives: hideFailed,
            showObjectiveProgress: showProgress,
            teamNames: teamNames
        )
    }

    private var markdown: String {
        PlayerBriefingMarkdown.render(run, options: options)
    }

    private var titleText: String {
        let t = PlayerBriefingMarkdown.displayTitle(run.title)
        return t.isEmpty ? "Untitled job" : t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    optionsBar
                    briefingBody
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 520, height: 600)
        .onAppear {
            guard !didConfigureDefaults else { return }
            didConfigureDefaults = true
            // Pre-run handout: no completion chips. Terminal runs: show progress by default.
            showProgress = run.status.isTerminal
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Player briefing")
                .font(.title2.weight(.semibold))
            Text(titleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var optionsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What runners know")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Toggle("Secondary objectives", isOn: $includeSecondary)
                    .toggleStyle(.checkbox)
                Toggle("Hide failed", isOn: $hideFailed)
                    .toggleStyle(.checkbox)
                Toggle("Show progress", isOn: $showProgress)
                    .toggleStyle(.checkbox)
                    .help("Annotate objectives as complete/failed (handy for post-run debrief; off for pre-game handouts)")
                Spacer()
            }
            .font(.callout)
            Text("GM notes, full opposition, complications, heat, and award splits stay off this view.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack {
            if let copyStatus {
                Text(copyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            AppChromeButton.title(
                "Copy Markdown",
                help: "Copy the player-safe briefing as Markdown",
                keyEquivalent: "c",
                keyModifiers: [.command, .shift]
            ) {
                copyMarkdown()
            }
            AppChromeButton.title(
                "Export PDF…",
                help: "Save a printable player-safe PDF handout (same content as Markdown)"
            ) {
                exportPDF()
            }
            AppChromeButton.title("Done", help: "Close player briefing") {
                onDismiss()
            }
        }
    }

    // MARK: - Body

    private var briefingBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            metaBlock
            if !summaryText.isEmpty {
                section("What you know") {
                    Text(summaryText)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            objectivesBlock
            payBlock
            if !risksText.isEmpty {
                section("Known risks") {
                    Text(risksText)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if isMostlyEmpty {
                Text("Add location, objectives, pay, and player-facing summary/risks on the run to flesh this out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleText == "Untitled job" ? "Untitled Job" : titleText)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            if !run.displayClientName.isEmpty {
                labeled("Client", run.displayClientName)
            }
            let location = run.location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !location.isEmpty {
                labeled("Location", location)
            }
            if !run.tags.isEmpty {
                labeled("Tags", run.tags.joined(separator: ", "))
            }
            labeled("Status", run.status.displayName)
            let team = cleanedTeamNames
            if !team.isEmpty {
                labeled("Runners", team.joined(separator: ", "))
            }
        }
    }

    @ViewBuilder
    private var objectivesBlock: some View {
        let primary = filterObjectives(run.primaryObjectives)
        let secondary = includeSecondary ? filterObjectives(run.secondaryObjectives) : []
        if !primary.isEmpty || !secondary.isEmpty {
            section("Objectives") {
                if !primary.isEmpty {
                    Text("Primary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(primary) { obj in
                        objectiveRow(obj)
                    }
                }
                if !secondary.isEmpty {
                    Text("Secondary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, primary.isEmpty ? 0 : 6)
                    ForEach(secondary) { obj in
                        objectiveRow(obj)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var payBlock: some View {
        let expected = run.expectedPayout
        let actual = run.actualPayout
        let hasExpected = !expected.isZero
        let hasActual = actual.map { !$0.isZero } ?? false
        if hasExpected || hasActual {
            section("Pay") {
                if hasExpected {
                    labeled("Expected", formatPayout(expected))
                }
                if let actual, hasActual {
                    labeled("Actual", formatPayout(actual))
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout.weight(.medium))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func objectiveRow(_ obj: RunObjective) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(obj.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .textSelection(.enabled)
            if showProgress, obj.status != .pending {
                Text(obj.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Data helpers

    private var summaryText: String {
        run.playerFacingSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var risksText: String {
        run.knownRisks.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanedTeamNames: [String] {
        teamNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isMostlyEmpty: Bool {
        summaryText.isEmpty
            && risksText.isEmpty
            && run.displayClientName.isEmpty
            && run.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && filterObjectives(run.objectives).isEmpty
            && run.expectedPayout.isZero
            && (run.actualPayout?.isZero ?? true)
            && cleanedTeamNames.isEmpty
    }

    private func filterObjectives(_ list: [RunObjective]) -> [RunObjective] {
        list.filter { obj in
            let text = obj.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            if hideFailed, obj.status == .failed { return false }
            return true
        }
    }

    private func formatPayout(_ p: RunPayout) -> String {
        "\(RunSupport.formatNuyen(p.nuyen)) + \(p.karma) karma"
    }

    private func copyMarkdown() {
        exportError = nil
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown, forType: .string)
        withAnimation {
            copyStatus = "Copied Markdown to clipboard"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if copyStatus == "Copied Markdown to clipboard" {
                    copyStatus = nil
                }
            }
        }
    }

    private func exportPDF() {
        exportError = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let base = PlayerBriefingMarkdown.displayTitle(run.title)
        let fileBase = base.isEmpty ? "Player-Briefing" : base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
        panel.nameFieldStringValue = "\(fileBase).pdf"
        panel.message = "Export a player-safe briefing PDF (no GM-only fields)."
        panel.prompt = "Export PDF"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PlayerBriefingPDF.write(
                markdown: markdown,
                runTitle: base,
                to: url
            )
            withAnimation {
                copyStatus = "Saved PDF"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation {
                    if copyStatus == "Saved PDF" {
                        copyStatus = nil
                    }
                }
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}
