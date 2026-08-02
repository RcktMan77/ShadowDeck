//
//  NewRunFromTemplateSheet.swift
//  ShadowDeck
//
//  Pick a built-in or user template and mint a planning run.
//

import SwiftUI

struct NewRunFromTemplateSheet: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    /// Pre-select this campaign (e.g. opened from campaign detail).
    var preferredCampaignID: UUID? = nil
    var onCancel: () -> Void
    /// Called with the new run id after save.
    var onCreated: (UUID) -> Void

    @State private var templates: [RunTemplate] = []
    @State private var selectedID: UUID?
    @State private var location = ""
    @State private var campaignID: UUID?
    @State private var campaigns: [CampaignSummary] = []
    @State private var errorMessage: String?

    private var selected: RunTemplate? {
        templates.first { $0.id == selectedID }
    }

    private var previewTitle: String {
        selected?.resolvedTitle(location: location) ?? "—"
    }

    private var userTemplates: [RunTemplate] {
        templates.filter { !$0.isBuiltin }
    }

    private var builtinTemplates: [RunTemplate] {
        templates.filter(\.isBuiltin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Run from Template")
                        .font(.headline)
                    Text("Choose a job pattern. Only {location} is filled into the title. Your saved templates appear under “Your templates”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create Run") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedID == nil)
            }
            .padding()

            Divider()

            HStack(alignment: .top, spacing: 0) {
                List(selection: $selectedID) {
                    Section("Built-in") {
                        ForEach(builtinTemplates) { template in
                            templateRow(template)
                                .tag(template.id)
                        }
                    }
                    Section("Your templates") {
                        if userTemplates.isEmpty {
                            Text("None yet — use Save as Template… on a run.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(userTemplates) { template in
                                templateRow(template)
                                    .tag(template.id)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(width: 260)
                .frame(maxHeight: .infinity)

                Divider()

                // Fixed-size detail pane so switching templates does not resize the sheet.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let selected {
                            Text(selected.name)
                                .font(.title3.weight(.semibold))
                            if selected.isBuiltin {
                                Text("Built-in starter")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Your template")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            LabeledContent("Title preview") {
                                Text(previewTitle)
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)
                            }
                            LabeledContent("Location") {
                                TextField("District, city… (optional)", text: $location)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 280)
                            }
                            LabeledContent("Campaign") {
                                Picker("Campaign", selection: $campaignID) {
                                    Text("Unassigned").tag(Optional<UUID>.none)
                                    ForEach(campaigns.filter { !$0.isArchived }) { c in
                                        Text(c.name).tag(Optional(c.id))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 280)
                            }
                            if !selected.tags.isEmpty {
                                RunTagChips(tags: selected.tags)
                            }
                            Text("Objectives")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(selected.objectives) { obj in
                                Text("• \(obj.isPrimary ? "" : "(secondary) ")\(obj.text)")
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !selected.oppositionPrompt.isEmpty {
                                Text("Opposition")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                Text(selected.oppositionPrompt)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(
                                "Expected ¥\(selected.expectedPayout.nuyen) · \(selected.expectedPayout.karma) karma"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        } else {
                            ContentUnavailableView {
                                Label("Select a template", systemImage: "list.clipboard")
                            } description: {
                                Text("Built-in starters and any templates you saved from a run.")
                            }
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Fixed outer size — content scrolls instead of growing the window.
        .frame(width: 720, height: 520)
        .onAppear { refresh() }
    }

    private func templateRow(_ template: RunTemplate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.name)
                .font(.body.weight(.medium))
            Text(template.titlePattern)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func refresh() {
        // Always re-read store so templates saved this session appear under “Your templates”.
        templates = libraryEnvironment.runTemplateStore.allTemplates()
        campaigns = (try? libraryEnvironment.campaignLibrary.listSummaries(includeArchived: true)) ?? []
        if selectedID == nil || templates.contains(where: { $0.id == selectedID }) == false {
            selectedID = templates.first?.id
        }
        if campaignID == nil, let preferredCampaignID {
            campaignID = preferredCampaignID
        }
        errorMessage = nil
    }

    private func create() {
        guard let selected else { return }
        var run = Run.makeDraft(from: selected, location: location, campaignID: campaignID)
        if let campaignID,
           let campaign = try? libraryEnvironment.campaignLibrary.fetch(id: campaignID) {
            run.edition = selected.editionHint ?? campaign.edition
        }
        do {
            try libraryEnvironment.runLibrary.save(run)
            libraryEnvironment.refreshRunCount()
            onCreated(run.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
