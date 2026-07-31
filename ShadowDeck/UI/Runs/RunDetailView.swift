//
//  RunDetailView.swift
//  ShadowDeck
//
//  GM detail editor for a single run / mission.
//

import SwiftUI

struct RunDetailView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    let runID: UUID
    var onBack: () -> Void
    var onDeleted: () -> Void

    @State private var run: Run?
    @State private var characterSummaries: [CharacterSummary] = []
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var showEmptyOutcomeReminder = false
    @State private var pendingStatus: RunStatus?
    @State private var newTag = ""
    @State private var newObjectiveText = ""
    @State private var newObjectiveIsPrimary = true
    @State private var newLogKind: RunLogEntryKind = .note
    @State private var newLogText = ""
    /// Local RTF drafts so typing doesn’t thrash library saves every keystroke.
    @State private var oppositionDraft = ""
    @State private var complicationsDraft = ""
    @State private var outcomeDraft = ""
    @State private var gmNotesDraft = ""
    /// Reference type so delete can flip this *immediately* (before `onDisappear`).
    /// `@State` bool updates can apply too late, letting auto-save re-insert a deleted run.
    @State private var session = RunDetailSession()

    var body: some View {
        Group {
            if let run {
                editor(run)
            } else {
                ProgressView("Loading run…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { reload() }
        .onChange(of: runID) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.marketingReloadRun)) { _ in
            reload()
        }
        .onDisappear {
            guard session.allowAutoSave else { return }
            commitRichTextDrafts(force: true)
        }
        .confirmationDialog(
            "Delete this run?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Run", role: .destructive) {
                deleteRun()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Add an outcome summary?", isPresented: $showEmptyOutcomeReminder) {
            Button("Add outcome later") {
                if let pendingStatus {
                    applyStatusConfirmed(pendingStatus)
                }
            }
            Button("Stay and edit", role: .cancel) {
                pendingStatus = nil
            }
        } message: {
            Text("You’re marking this run finished without an outcome summary. You can still save — a short write-up helps later when looking up the job.")
        }
    }

    @ViewBuilder
    private func editor(_ current: Run) -> some View {
        // Sticky chrome (Back / Status / Delete) like the character workspace toolbar.
        VStack(spacing: 0) {
            stickyToolbar(current)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleField

                    overviewSection
                    objectivesSection
                    oppositionSection
                    payoutSection
                    teamSection
                    sessionLogSection
                    outcomeSection
                }
                .padding(24)
                .frame(maxWidth: 960, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sticky toolbar

    private func stickyToolbar(_ current: Run) -> some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Label("Runs", systemImage: "chevron.left")
            }

            Text(current.title.isEmpty ? "Untitled Run" : current.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Status", selection: statusBinding) {
                ForEach(RunStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
            .help("Run status")

            Button("Delete", systemImage: "trash", role: .destructive) {
                confirmDelete = true
            }
        }
    }

    /// Scrolls with the form body — large editable title under sticky chrome.
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Run title (required)", text: titleBinding)
                .font(.title.weight(.bold))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 640, minHeight: 48, alignment: .leading)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1)
                }
        }
    }

    // MARK: - Sections

    private var overviewSection: some View {
        RunSectionCard(title: "Overview") {
            VStack(alignment: .leading, spacing: 10) {
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
                    RunTagChips(tags: run?.tags ?? [])
                    HStack {
                        TextField("Add tag (e.g. Extraction)", text: $newTag)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            .onSubmit { addTag() }
                        Button("Add") { addTag() }
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let tags = run?.tags, !tags.isEmpty {
                            Button("Clear tags", role: .destructive) {
                                updateRun { $0.tags = [] }
                            }
                            .controlSize(.small)
                        }
                    }
                    if let tags = run?.tags, !tags.isEmpty {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Button(role: .destructive) {
                                    updateRun { $0.tags.removeAll { $0 == tag } }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                            .font(.caption)
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

    private var objectivesSection: some View {
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
    private func objectiveList(title: String, primary: Bool) -> some View {
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

    private var oppositionSection: some View {
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

    private func richTextBlock(
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

    private var payoutSection: some View {
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

    private var teamSection: some View {
        RunSectionCard(title: "Team") {
            if characterSummaries.isEmpty {
                Text("No characters in the library yet. Create or import runners, then link them here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(characterSummaries) { summary in
                        Toggle(isOn: participantToggle(summary.id)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(summary.displayTitle)
                                    .font(.body.weight(.medium))
                                Text("\(summary.editionRaw) · \(summary.metatypeRaw.capitalized)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private var sessionLogSection: some View {
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

    private var outcomeSection: some View {
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

                Text("Suggested awards")
                    .font(.subheadline.weight(.semibold))
                Text("Suggestions only — does not change character karma/nuyen. Apply awards manually on each character sheet when you’re ready.")
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

    // MARK: - Bindings & mutations

    private var titleBinding: Binding<String> {
        Binding(
            get: { run?.title ?? "" },
            set: { newValue in
                updateRun { $0.title = newValue }
            }
        )
    }

    private var statusBinding: Binding<RunStatus> {
        Binding(
            get: { run?.status ?? .planning },
            set: { newStatus in
                requestStatusChange(newStatus)
            }
        )
    }

    private var plannedDateBinding: Binding<Date> {
        Binding(
            get: { run?.plannedDate ?? Date() },
            set: { newValue in
                updateRun { $0.plannedDate = newValue }
            }
        )
    }

    private var expectedNuyenBinding: Binding<Int> {
        Binding(
            get: { run?.expectedPayout.nuyen ?? 0 },
            set: { v in updateRun { $0.expectedPayout.nuyen = max(0, v) } }
        )
    }

    private var expectedKarmaBinding: Binding<Int> {
        Binding(
            get: { run?.expectedPayout.karma ?? 0 },
            set: { v in updateRun { $0.expectedPayout.karma = max(0, v) } }
        )
    }

    private var actualNuyenBinding: Binding<Int> {
        Binding(
            get: { run?.actualPayout?.nuyen ?? 0 },
            set: { v in
                updateRun { r in
                    var p = r.actualPayout ?? .zero
                    p.nuyen = max(0, v)
                    r.actualPayout = p
                }
            }
        )
    }

    private var actualKarmaBinding: Binding<Int> {
        Binding(
            get: { run?.actualPayout?.karma ?? 0 },
            set: { v in
                updateRun { r in
                    var p = r.actualPayout ?? .zero
                    p.karma = max(0, v)
                    r.actualPayout = p
                }
            }
        )
    }

    private var heatBinding: Binding<Int> {
        Binding(
            get: { run?.heatDelta ?? 0 },
            set: { v in updateRun { $0.heatDelta = v } }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<Run, String>) -> Binding<String> {
        Binding(
            get: { run?[keyPath: keyPath] ?? "" },
            set: { newValue in
                updateRun { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func objectiveTextBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { run?.objectives.first(where: { $0.id == id })?.text ?? "" },
            set: { newValue in
                updateRun { r in
                    if let i = r.objectives.firstIndex(where: { $0.id == id }) {
                        r.objectives[i].text = newValue
                    }
                }
            }
        )
    }

    private func objectiveStatusBinding(_ id: UUID) -> Binding<RunObjectiveStatus> {
        Binding(
            get: { run?.objectives.first(where: { $0.id == id })?.status ?? .pending },
            set: { newValue in
                updateRun { r in
                    if let i = r.objectives.firstIndex(where: { $0.id == id }) {
                        r.objectives[i].status = newValue
                    }
                }
            }
        )
    }

    private func participantToggle(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { run?.participantCharacterIDs.contains(id) == true },
            set: { on in
                updateRun { r in
                    if on {
                        if !r.participantCharacterIDs.contains(id) {
                            r.participantCharacterIDs.append(id)
                        }
                    } else {
                        r.participantCharacterIDs.removeAll { $0 == id }
                    }
                }
            }
        )
    }

    private func requestStatusChange(_ newStatus: RunStatus) {
        guard let current = run, current.status != newStatus else { return }
        commitRichTextDrafts(force: true)
        // Mild reminder when finishing without outcome (plain or empty RTF).
        if newStatus.isTerminal, Run.isBlankNote(outcomeDraft) {
            pendingStatus = newStatus
            showEmptyOutcomeReminder = true
            return
        }
        applyStatusConfirmed(newStatus)
    }

    private func applyStatusConfirmed(_ newStatus: RunStatus) {
        pendingStatus = nil
        updateRun { $0.applyStatus(newStatus) }
        statusMessage = "Status → \(newStatus.displayName)."
    }

    private func commitRichTextDrafts(force: Bool = false) {
        guard session.allowAutoSave else { return }
        guard var current = run else { return }
        var changed = false
        if force || current.opposition != oppositionDraft {
            current.opposition = oppositionDraft
            changed = true
        }
        if force || current.complicationsNotes != complicationsDraft {
            current.complicationsNotes = complicationsDraft
            changed = true
        }
        if force || current.outcomeSummary != outcomeDraft {
            current.outcomeSummary = outcomeDraft
            changed = true
        }
        if force || current.gmNotes != gmNotesDraft {
            current.gmNotes = gmNotesDraft
            changed = true
        }
        guard changed else { return }
        persist(current)
    }

    private func loadRichTextDrafts(from current: Run) {
        oppositionDraft = current.opposition
        complicationsDraft = current.complicationsNotes
        outcomeDraft = current.outcomeSummary
        gmNotesDraft = current.gmNotes
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        updateRun { r in
            if !r.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                r.tags.append(tag)
            }
        }
        newTag = ""
    }

    private func addObjective() {
        let text = newObjectiveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        updateRun {
            $0.objectives.append(
                RunObjective(text: text, isPrimary: newObjectiveIsPrimary, status: .pending)
            )
        }
        newObjectiveText = ""
    }

    private func addLogEntry() {
        let text = newLogText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        updateRun {
            $0.sessionLog.append(RunLogEntry(kind: newLogKind, text: text))
        }
        newLogText = ""
    }

    private func characterTitle(_ id: UUID) -> String {
        characterSummaries.first(where: { $0.id == id })?.displayTitle ?? "Missing runner"
    }

    private func updateRun(_ mutate: (inout Run) -> Void) {
        guard session.allowAutoSave else { return }
        guard var current = run else { return }
        mutate(&current)
        persist(current)
    }

    private func persist(_ current: Run) {
        guard session.allowAutoSave else { return }
        do {
            try libraryEnvironment.runLibrary.save(current)
            // Keep local state; avoid require() if we just deleted or tore down.
            if session.allowAutoSave {
                run = current
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            // Reload last good copy if save failed (e.g. empty title).
            if session.allowAutoSave {
                reload()
            }
        }
    }

    private func reload() {
        do {
            let loaded = try libraryEnvironment.runLibrary.require(runID)
            run = loaded
            loadRichTextDrafts(from: loaded)
            characterSummaries = try libraryEnvironment.library.listSummaries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            run = nil
        }
    }

    private func goBack() {
        commitRichTextDrafts(force: true)
        onBack()
    }

    private func deleteRun() {
        // 1) Kill all auto-save paths immediately (reference flag).
        // 2) Delete in the store (also blocks re-insert by id in RunLibrary).
        // 3) Leave — onDisappear / delayed NotesEditor commits cannot resurrect.
        session.allowAutoSave = false
        let idToDelete = runID
        run = nil
        do {
            try libraryEnvironment.runLibrary.delete(id: idToDelete)
            libraryEnvironment.refreshRunCount()
            onDeleted()
        } catch {
            // Deletion failed — allow editing again and reload.
            session.allowAutoSave = true
            errorMessage = error.localizedDescription
            reload()
        }
    }
}

/// Mutable session flags for `RunDetailView` (not `@State` bools — those can lag).
@MainActor
private final class RunDetailSession {
    var allowAutoSave = true
}
