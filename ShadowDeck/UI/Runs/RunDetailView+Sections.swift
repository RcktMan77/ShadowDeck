//
//  RunDetailView+Sections.swift
//  ShadowDeck
//
//  Run editor form sections (extracted from RunDetailView).
//

import SwiftUI

extension RunDetailView {
    // MARK: - Sections

    var overviewSection: some View {
        RunSectionCard(title: "Overview") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Campaign") {
                    Picker("Campaign", selection: campaignBinding) {
                        Text("Unassigned").tag(Optional<UUID>.none)
                        ForEach(campaignOptions) { summary in
                            Text(summary.isArchived ? "\(summary.name) (archived)" : summary.name)
                                .tag(Optional(summary.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                }
                Text("Optional folder for this job. Deleting a campaign leaves runs Unassigned.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                LabeledContent("Ruleset") {
                    Picker("Ruleset", selection: editionBinding) {
                        ForEach(Edition.allCases) { edition in
                            Text(edition.shortName).tag(edition)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .help("Only runners built for this edition can be added to the team.")
                }
                Text("Team picks are limited to characters that match this ruleset.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                LabeledContent("Client / Johnson") {
                    TextField("Mr. Johnson…", text: binding(\.client))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
                LabeledContent("Location") {
                    TextField("District, city…", text: binding(\.location))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Planned date")
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "",
                        selection: plannedDateBinding,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    if run?.plannedDate != nil {
                        Button("Clear") {
                            updateRun { $0.plannedDate = nil }
                        }
                        .controlSize(.small)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags / job type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    RunTagChips(tags: run?.tags ?? []) { tag in
                        updateRun { $0.tags.removeAll { $0 == tag } }
                    }
                    HStack {
                        TextField("Add tag (e.g. Extraction)", text: $newTag)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            .onSubmit { addTag() }
                        Button("Add") { addTag() }
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let tags = run?.tags, !tags.isEmpty {
                            Button("Clear all", role: .destructive) {
                                updateRun { $0.tags = [] }
                            }
                            .controlSize(.small)
                            .help("Remove every tag from this run")
                        }
                    }
                }
                richTextBlock(
                    caption: "GM Notes",
                    help: "Private prep notes for this job.",
                    text: $gmNotesDraft,
                    height: 140
                ) {
                    commitRichTextDrafts()
                }
            }
        }
    }

    var objectivesSection: some View {
        RunSectionCard(title: "Objectives") {
            VStack(alignment: .leading, spacing: 12) {
                objectiveList(title: "Primary", primary: true)
                objectiveList(title: "Secondary", primary: false)
                Divider()
                HStack {
                    Picker("Kind", selection: $newObjectiveIsPrimary) {
                        Text("Primary").tag(true)
                        Text("Secondary").tag(false)
                    }
                    .frame(maxWidth: 140)
                    TextField("New objective…", text: $newObjectiveText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addObjective() }
                    Button("Add") { addObjective() }
                        .disabled(newObjectiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    func objectiveList(title: String, primary: Bool) -> some View {
        let items = (run?.objectives ?? []).filter { $0.isPrimary == primary }
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        if items.isEmpty {
            Text("None yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            ForEach(items) { objective in
                HStack(alignment: .top, spacing: 8) {
                    Picker("Status", selection: objectiveStatusBinding(objective.id)) {
                        ForEach(RunObjectiveStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    TextField("Objective", text: objectiveTextBinding(objective.id))
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        updateRun { $0.objectives.removeAll { $0.id == objective.id } }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    var oppositionSection: some View {
        RunSectionCard(title: "Opposition & Complications") {
            VStack(alignment: .leading, spacing: 12) {
                richTextBlock(
                    caption: "Opposition / Threats",
                    help: "Threats, security posture, known opposition.",
                    text: $oppositionDraft,
                    height: 140
                ) {
                    commitRichTextDrafts()
                }

                richTextBlock(
                    caption: "Standing Complications",
                    help: "Ongoing complications and risks for this job.",
                    text: $complicationsDraft,
                    height: 120
                ) {
                    commitRichTextDrafts()
                }
            }
        }
    }

    func richTextBlock(
        caption: String,
        help: String,
        text: Binding<String>,
        height: CGFloat,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(help)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            NotesEditor(text: text, onCommit: onCommit)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
    }

    var payoutSection: some View {
        RunSectionCard(title: "Payout & Heat") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Expected ¥")
                    TextField("0", value: expectedNuyenBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("Expected karma")
                    TextField("0", value: expectedKarmaBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                GridRow {
                    Text("Actual ¥")
                    TextField("—", value: actualNuyenBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("Actual karma")
                    TextField("—", value: actualKarmaBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                GridRow {
                    Text("Heat Δ")
                    TextField("0", value: heatBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("")
                    Text("")
                }
            }
            Text("Leave actual blank until the run resolves. Heat is a simple integer for now (campaign heat ledger later).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    var teamSection: some View {
        RunSectionCard(title: "Team") {
            if characterSummaries.isEmpty {
                Text("No characters in the library yet. Create or import runners, then link them here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let runEdition = run?.edition ?? .sr5
                let eligible = characterSummaries.filter { $0.edition == runEdition }
                let ineligible = characterSummaries.filter { $0.edition != runEdition }

                VStack(alignment: .leading, spacing: 10) {
                    if eligible.isEmpty {
                        Text("No \(runEdition.shortName) runners in the library yet. Create or import a matching character to build the team.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(runEdition.shortName) runners")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(eligible) { summary in
                            teamToggleRow(summary, enabled: true, reason: nil)
                        }
                    }

                    if !ineligible.isEmpty {
                        DisclosureGroup("Other editions (\(ineligible.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(ineligible) { summary in
                                    teamToggleRow(
                                        summary,
                                        enabled: false,
                                        reason: "Built for \(summary.editionRaw) — this run is \(runEdition.shortName)"
                                    )
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    func teamToggleRow(_ summary: CharacterSummary, enabled: Bool, reason: String?) -> some View {
        Toggle(isOn: participantToggle(summary.id, enabled: enabled)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(enabled ? .primary : .secondary)
                Text("\(summary.editionRaw) · \(summary.metatypeRaw.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.72)
    }

    var sessionLogSection: some View {
        RunSectionCard(title: "Session Log") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Picker("Kind", selection: $newLogKind) {
                        ForEach(RunLogEntryKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .frame(width: 140)
                    TextField("What happened…", text: $newLogText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    Button("Add entry") { addLogEntry() }
                        .disabled(newLogText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                let entries = run?.sessionLogNewestFirst ?? []
                if entries.isEmpty {
                    Text("No log entries yet. Capture complications, heat spikes, and session beats as you play.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: entry.kind.systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.kind.displayName)
                                        .font(.caption.weight(.semibold))
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(entry.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
                            Button(role: .destructive) {
                                updateRun { $0.sessionLog.removeAll { $0.id == entry.id } }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
    }

    var outcomeSection: some View {
        RunSectionCard(title: "Outcome & Suggested Awards") {
            VStack(alignment: .leading, spacing: 12) {
                richTextBlock(
                    caption: "Outcome Summary",
                    help: "Success level, consequences, follow-ups.",
                    text: $outcomeDraft,
                    height: 160
                ) {
                    commitRichTextDrafts()
                }

                if Run.isBlankNote(outcomeDraft), run?.status.isTerminal == true {
                    Label(
                        "No outcome summary yet — consider jotting success level and consequences.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Divider()

                awardsBlock

                if let run {
                    HStack(spacing: 16) {
                        if let started = run.startedAt {
                            Label("Started \(RunSupport.formatDate(started))", systemImage: "play")
                        }
                        if let completed = run.completedAt {
                            Label("Ended \(RunSupport.formatDate(completed))", systemImage: "flag")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var awardsBlock: some View {
        if let run, run.awardsAppliedAt != nil {
            appliedAwardsBlock(run)
        } else {
            pendingAwardsBlock
        }
    }

    func appliedAwardsBlock(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Awards applied on \(RunSupport.formatDate(run.awardsAppliedAt))",
                systemImage: "checkmark.seal.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)

            Text("Awards applied to linked runners. See each character’s Plan tab ledger for the credit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = run.awardsAppliedNote, !note.isEmpty {
                Text("Note: \(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Collapse prior suggestion breakdown so it is clearly non-actionable.
            let awards = run.suggestedAwards()
            if !awards.isEmpty {
                DisclosureGroup("Previous suggestion breakdown") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(awards) { award in
                            HStack {
                                Text(characterTitle(award.characterID))
                                Spacer()
                                Text(RunSupport.formatNuyen(award.nuyen))
                                    .monospacedDigit()
                                Text("\(award.karma) karma")
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    var pendingAwardsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested awards")
                .font(.subheadline.weight(.semibold))
            Text("Suggestions only — does not change character karma/nuyen until you apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let awards = run?.suggestedAwards() ?? []
            if awards.isEmpty {
                Text("Link at least one runner and set expected or actual payout to see a split.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(awards) { award in
                    HStack {
                        Text(characterTitle(award.characterID))
                            .font(.body.weight(.medium))
                        Spacer()
                        Text(RunSupport.formatNuyen(award.nuyen))
                            .monospacedDigit()
                        Text("\(award.karma) karma")
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.callout)
                }
                Text(awards.first?.note ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            applyAwardsControls
        }
    }

    var applyAwardsControls: some View {
        let eligible = canOfferApplyAwards
        return VStack(alignment: .leading, spacing: 6) {
            Button("Apply Awards…") {
                presentApplyAwardsSheet()
            }
            .disabled(!eligible)
            .help(applyAwardsHelp)

            if !eligible, let hint = applyAwardsDisabledHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 4)
    }

    var canOfferApplyAwards: Bool {
        guard let run else { return false }
        guard run.awardsAppliedAt == nil else { return false }
        guard run.status.isTerminal else { return false }
        guard !run.participantCharacterIDs.isEmpty else { return false }
        let source = run.actualPayout ?? run.expectedPayout
        return !source.isZero
    }

    var applyAwardsHelp: String {
        if canOfferApplyAwards {
            return "Credit equal-split nuyen and karma to linked runners"
        }
        return applyAwardsDisabledHint ?? "Apply awards when the run is finished"
    }

    var applyAwardsDisabledHint: String? {
        guard let run else { return nil }
        if run.awardsAppliedAt != nil { return nil }
        if !run.status.isTerminal {
            return "Mark the run Completed or Failed to apply awards."
        }
        if run.participantCharacterIDs.isEmpty {
            return "Link at least one runner on the team."
        }
        let source = run.actualPayout ?? run.expectedPayout
        if source.isZero {
            return "Set a non-zero expected or actual payout first."
        }
        return nil
    }
}
