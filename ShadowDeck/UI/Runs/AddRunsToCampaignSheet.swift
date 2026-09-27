//
//  CampaignsListView.swift
//  ShadowDeck
//
//  Campaign library list + campaign detail (runs under a campaign).
//

import SwiftUI
struct AddRunsToCampaignSheet: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    let campaignID: UUID
    let campaignEdition: Edition
    let alreadyAssignedIDs: Set<UUID>
    var onCancel: () -> Void
    var onAdded: () -> Void

    @State private var candidates: [RunSummary] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var onlyMatchingEdition = true
    @State private var errorMessage: String?

    private var visible: [RunSummary] {
        candidates.filter { summary in
            if alreadyAssignedIDs.contains(summary.id) { return false }
            if onlyMatchingEdition, summary.edition != campaignEdition { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add Runs from Library")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add \(selectedIDs.isEmpty ? "" : "\(selectedIDs.count) ")Run\(selectedIDs.count == 1 ? "" : "s")") {
                    assignSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding()

            Divider()

            HStack {
                Toggle("Only \(campaignEdition.shortName) ruleset", isOn: $onlyMatchingEdition)
                    .toggleStyle(.checkbox)
                Spacer()
                Text("\(visible.count) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if visible.isEmpty {
                ContentUnavailableView {
                    Label("No Runs to Add", systemImage: "list.clipboard")
                } description: {
                    Text(
                        onlyMatchingEdition
                            ? "No unassigned \(campaignEdition.shortName) runs (or runs in other campaigns) match. Create a new run or clear the ruleset filter."
                            : "Every run is already in this campaign, or the library is empty."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedIDs) {
                    ForEach(visible) { summary in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.title)
                                    .font(.body.weight(.medium))
                                HStack(spacing: 8) {
                                    RunStatusBadge(status: summary.status)
                                    RunEditionBadge(edition: summary.edition)
                                    if let other = summary.campaignID, other != campaignID {
                                        Text("Reassign from another campaign")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    } else if summary.campaignID == nil {
                                        Text("Unassigned")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .tag(summary.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { refreshCandidates() }
    }

    private func refreshCandidates() {
        do {
            candidates = try libraryEnvironment.runLibrary.listSummaries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assignSelected() {
        do {
            for id in selectedIDs {
                var run = try libraryEnvironment.runLibrary.require(id)
                run.campaignID = campaignID
                try libraryEnvironment.runLibrary.save(run)
            }
            libraryEnvironment.refreshRunCount()
            onAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
