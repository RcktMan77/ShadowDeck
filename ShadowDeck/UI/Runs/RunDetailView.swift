//
//  RunDetailView.swift
//  ShadowDeck
//
//  GM detail editor for a single run / mission.
//

import SwiftUI

struct RunDetailView: View {
    @Environment(LibraryEnvironment.self) var libraryEnvironment

    let runID: UUID
    var onBack: () -> Void
    var onDeleted: () -> Void

    @State var run: Run?
    @State var characterSummaries: [CharacterSummary] = []
    @State var campaignOptions: [CampaignSummary] = []
    @State var statusMessage: String?
    @State var errorMessage: String?
    @State var confirmDelete = false
    @State var showEmptyOutcomeReminder = false
    @State var pendingStatus: RunStatus?
    @State var newTag = ""
    @State var newObjectiveText = ""
    @State var newObjectiveIsPrimary = true
    @State var newLogKind: RunLogEntryKind = .note
    @State var newLogText = ""
    /// Local RTF drafts so typing doesn’t thrash library saves every keystroke.
    @State var oppositionDraft = ""
    @State var complicationsDraft = ""
    @State var outcomeDraft = ""
    @State var gmNotesDraft = ""
    /// Reference type so delete can flip this *immediately* (before `onDisappear`).
    /// `@State` bool updates can apply too late, letting auto-save re-insert a deleted run.
    @State var session = RunDetailSession()
    /// Marketing GIF: scroll + pulse a section so storyboard action is on-screen.
    @State var marketingAnchor: String?
    @State var marketingHighlight: String?
    /// Non-nil while Apply Awards sheet is open (`sheet(item:)` avoids blank empty sheets).
    @State var applyAwardsPresentation: ApplyAwardsPresentation?
    @State var showSaveAsTemplate = false
    @State var saveTemplateName = ""
    @State var showAddContactSheet = false
    @State var showAddUnlinkedContact = false
    @State var unlinkedName = ""
    @State var unlinkedRole: RunContactRole = .other
    @State var unlinkedRoleLabel = ""

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
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.marketingFocus)) { note in
            marketingAnchor = note.userInfo?["anchor"] as? String
            marketingHighlight = note.userInfo?["highlight"] as? String
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
        .sheet(item: $applyAwardsPresentation) { presentation in
            ApplyAwardsSheet(
                runTitle: presentation.runTitle,
                preview: presentation.preview,
                runHeatDelta: presentation.heatDelta,
                onCancel: { applyAwardsPresentation = nil },
                onConfirm: { shares, note, heatNote in
                    applyAwards(shares: shares, note: note, heatNote: heatNote)
                }
            )
        }
        .sheet(isPresented: $showSaveAsTemplate) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Save as Template")
                    .font(.headline)
                Text("Reusable job pattern for Create → New Run from Template.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Template name", text: $saveTemplateName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showSaveAsTemplate = false }
                    Button("Save Template") { commitSaveAsTemplate() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(saveTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(minWidth: 360)
        }
        .sheet(isPresented: $showAddContactSheet) {
            AddRunContactSheet(
                characterSummaries: characterSummaries,
                existingLinkedKeys: RunContactLinkKey.set(from: run?.contacts ?? []),
                onCancel: { showAddContactSheet = false },
                onAdd: { links in
                    updateRun { r in
                        for link in links {
                            r.addContactLink(link)
                        }
                    }
                    showAddContactSheet = false
                }
            )
            .environment(libraryEnvironment)
        }
        .sheet(isPresented: $showAddUnlinkedContact) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add unlinked person")
                    .font(.headline)
                TextField("Name", text: $unlinkedName)
                    .textFieldStyle(.roundedBorder)
                Picker("Role", selection: $unlinkedRole) {
                    ForEach(RunContactRole.allCases) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                if unlinkedRole == .other {
                    TextField("Role label (optional)", text: $unlinkedRoleLabel)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showAddUnlinkedContact = false
                        unlinkedName = ""
                        unlinkedRoleLabel = ""
                    }
                    Button("Add") {
                        let name = unlinkedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let link = RunContactLink(
                            role: unlinkedRole,
                            displayName: name,
                            displayRoleLabel: unlinkedRole == .other
                                ? (unlinkedRoleLabel.isEmpty ? nil : unlinkedRoleLabel)
                                : nil
                        )
                        updateRun { $0.addContactLink(link) }
                        showAddUnlinkedContact = false
                        unlinkedName = ""
                        unlinkedRoleLabel = ""
                        unlinkedRole = .other
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(unlinkedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(minWidth: 360)
        }
    }

    private func prepareSaveAsTemplate() {
        commitRichTextDrafts(force: true)
        saveTemplateName = run?.title.isEmpty == false ? "\(run!.title) template" : "Custom template"
        showSaveAsTemplate = true
    }

    private func commitSaveAsTemplate() {
        guard let run else { return }
        let template = run.asTemplate(name: saveTemplateName)
        do {
            try libraryEnvironment.runTemplateStore.saveUserTemplate(template)
            statusMessage = "Saved template “\(template.name)”."
            errorMessage = nil
            showSaveAsTemplate = false
        } catch {
            errorMessage = error.localizedDescription
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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        titleField
                            .id("overview")

                        overviewSection
                            .id("overviewBody")
                        contactsSection
                            .id("contacts")
                        objectivesSection
                            .id("objectives")
                            .modifier(MarketingHighlightPulse(active: marketingHighlight == "objectives"))
                        oppositionSection
                        payoutSection
                        teamSection
                            .id("team")
                            .modifier(MarketingHighlightPulse(active: marketingHighlight == "team"))
                        sessionLogSection
                            .id("sessionLog")
                            .modifier(MarketingHighlightPulse(active: marketingHighlight == "sessionLog"))
                        outcomeSection
                            .id("outcome")
                            .modifier(MarketingHighlightPulse(active: marketingHighlight == "outcome"))
                    }
                    .padding(24)
                    .frame(maxWidth: 960, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: marketingAnchor) { _, anchor in
                    guard let anchor else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(anchor, anchor: .center)
                    }
                }
            }

            Divider()

            // Bottom-right save: flush rich-text drafts and return to Run Library.
            // Edits still auto-save while working; this is explicit confirmation + leave.
            HStack {
                Spacer()
                Button("Save") {
                    saveAndReturn()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func saveAndReturn() {
        commitRichTextDrafts(force: true)
        goBack()
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

            Button("Look up", systemImage: "book.pages") {
                RulesReferenceOpener.request(query: "run")
            }
            .help("Open Rules Reference for awards, heat, and downtime topics")

            Button("Save as Template…", systemImage: "list.bullet.rectangle") {
                prepareSaveAsTemplate()
            }
            .help("Save this job’s structure as a reusable run template")

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

    // MARK: - Bindings & mutations

    var titleBinding: Binding<String> {
        Binding(
            get: { run?.title ?? "" },
            set: { newValue in
                updateRun { $0.title = newValue }
            }
        )
    }

    var statusBinding: Binding<RunStatus> {
        Binding(
            get: { run?.status ?? .planning },
            set: { newStatus in
                requestStatusChange(newStatus)
            }
        )
    }

    var plannedDateBinding: Binding<Date> {
        Binding(
            get: { run?.plannedDate ?? Date() },
            set: { newValue in
                updateRun { $0.plannedDate = newValue }
            }
        )
    }

    var expectedNuyenBinding: Binding<Int> {
        Binding(
            get: { run?.expectedPayout.nuyen ?? 0 },
            set: { v in updateRun { $0.expectedPayout.nuyen = max(0, v) } }
        )
    }

    var expectedKarmaBinding: Binding<Int> {
        Binding(
            get: { run?.expectedPayout.karma ?? 0 },
            set: { v in updateRun { $0.expectedPayout.karma = max(0, v) } }
        )
    }

    var actualNuyenBinding: Binding<Int> {
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

    var actualKarmaBinding: Binding<Int> {
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

    var heatBinding: Binding<Int> {
        Binding(
            get: { run?.heatDelta ?? 0 },
            set: { v in updateRun { $0.heatDelta = v } }
        )
    }

    func binding(_ keyPath: WritableKeyPath<Run, String>) -> Binding<String> {
        Binding(
            get: { run?[keyPath: keyPath] ?? "" },
            set: { newValue in
                updateRun { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    func objectiveTextBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { run?.objectives.first { $0.id == id }?.text ?? "" },
            set: { newValue in
                updateRun { r in
                    if let i = r.objectives.firstIndex(where: { $0.id == id }) {
                        r.objectives[i].text = newValue
                    }
                }
            }
        )
    }

    func objectiveStatusBinding(_ id: UUID) -> Binding<RunObjectiveStatus> {
        Binding(
            get: { run?.objectives.first { $0.id == id }?.status ?? .pending },
            set: { newValue in
                updateRun { r in
                    if let i = r.objectives.firstIndex(where: { $0.id == id }) {
                        r.objectives[i].status = newValue
                    }
                }
            }
        )
    }

    var editionBinding: Binding<Edition> {
        Binding(
            get: { run?.edition ?? .sr5 },
            set: { newEdition in
                updateRun { r in
                    guard r.edition != newEdition else { return }
                    r.edition = newEdition
                    let map = Dictionary(
                        uniqueKeysWithValues: characterSummaries.compactMap { s -> (UUID, Edition)? in
                            guard let ed = s.edition else { return nil }
                            return (s.id, ed)
                        }
                    )
                    r.pruneIneligibleParticipants(characterEditions: map)
                }
            }
        )
    }

    var campaignBinding: Binding<UUID?> {
        Binding(
            get: { run?.campaignID },
            set: { newID in
                updateRun { $0.campaignID = newID }
            }
        )
    }

    func participantToggle(_ id: UUID, enabled: Bool = true) -> Binding<Bool> {
        Binding(
            get: { run?.participantCharacterIDs.contains(id) == true },
            set: { on in
                guard enabled else { return }
                updateRun { r in
                    if on {
                        if let summary = characterSummaries.first(where: { $0.id == id }),
                           summary.edition != r.edition {
                            return
                        }
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

    func requestStatusChange(_ newStatus: RunStatus) {
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

    func applyStatusConfirmed(_ newStatus: RunStatus) {
        pendingStatus = nil
        updateRun { $0.applyStatus(newStatus) }
        statusMessage = "Status → \(newStatus.displayName)."
    }

    func commitRichTextDrafts(force: Bool = false) {
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

    func loadRichTextDrafts(from current: Run) {
        oppositionDraft = current.opposition
        complicationsDraft = current.complicationsNotes
        outcomeDraft = current.outcomeSummary
        gmNotesDraft = current.gmNotes
    }

    func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        updateRun { r in
            if !r.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                r.tags.append(tag)
            }
        }
        newTag = ""
    }

    func addObjective() {
        let text = newObjectiveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        updateRun {
            $0.objectives.append(
                RunObjective(text: text, isPrimary: newObjectiveIsPrimary, status: .pending)
            )
        }
        newObjectiveText = ""
    }

    func addLogEntry() {
        let text = newLogText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        updateRun {
            $0.sessionLog.append(RunLogEntry(kind: newLogKind, text: text))
        }
        newLogText = ""
    }

    func characterTitle(_ id: UUID) -> String {
        characterSummaries.first { $0.id == id }?.displayTitle ?? "Missing runner"
    }

    // MARK: - Apply awards

    func presentApplyAwardsSheet() {
        guard var current = run else { return }
        // Ensure rich-text drafts are flushed before we read/mutate the run.
        commitRichTextDrafts(force: true)
        current = run ?? current

        var charactersByID: [UUID: Character] = [:]
        for id in current.participantCharacterIDs {
            if let character = try? libraryEnvironment.library.fetch(id: id) {
                charactersByID[id] = character
            }
        }
        let preview = RunAwardApplicator.preview(run: current, charactersByID: charactersByID)
        applyAwardsPresentation = ApplyAwardsPresentation(
            runTitle: current.title,
            heatDelta: current.heatDelta,
            preview: preview
        )
    }

    func applyAwards(shares: [AwardShare], note: String, heatNote: String) {
        guard var current = run else {
            applyAwardsPresentation = nil
            return
        }
        commitRichTextDrafts(force: true)
        current = run ?? current

        var characters: [Character] = []
        var missingIDs: [UUID] = []
        for id in current.participantCharacterIDs {
            if let character = try? libraryEnvironment.library.fetch(id: id) {
                characters.append(character)
            } else {
                missingIDs.append(id)
            }
        }

        do {
            let result = try RunAwardApplicator.apply(
                run: &current,
                characters: &characters,
                shares: shares,
                note: note,
                heatNote: heatNote
            )

            // Persist characters first, then the run (applied marker last).
            var failedSaves: [String] = []
            for character in characters where result.applied.contains(where: { $0.characterID == character.id }) {
                do {
                    try libraryEnvironment.library.save(character)
                } catch {
                    failedSaves.append(character.displayTitle)
                }
            }

            if !failedSaves.isEmpty {
                errorMessage =
                    "Some character saves failed (\(failedSaves.joined(separator: ", "))). "
                    + "Verify those sheets before applying again — awards were not marked applied on the run."
                applyAwardsPresentation = nil
                // Do not save run with awardsAppliedAt if character saves failed mid-way.
                // Note: pure apply already mutated `current` in memory; reload to discard.
                reload()
                return
            }

            try libraryEnvironment.runLibrary.save(current)
            run = current
            characterSummaries = try libraryEnvironment.library.listSummaries()
            statusMessage = awardsStatusMessage(result: result, missingCount: missingIDs.count)
            errorMessage = nil
            applyAwardsPresentation = nil
        } catch {
            errorMessage = error.localizedDescription
            applyAwardsPresentation = nil
        }
    }

    func awardsStatusMessage(result: ApplyResult, missingCount: Int) -> String {
        let nuyen = result.applied.map(\.nuyen).reduce(0, +)
        let karma = result.applied.map(\.karma).reduce(0, +)
        var message =
            "Applied awards to \(result.applied.count) runner(s): "
            + "\(RunSupport.formatNuyen(nuyen)) + \(karma) karma."
        if result.applied.contains(where: \.hasReputationDelta) {
            message += " Reputation updated."
        }
        if result.heatNote != nil {
            message += " Heat note logged."
        }
        if !result.skipped.isEmpty || missingCount > 0 {
            message += " Skipped \(result.skipped.count) missing."
        }
        return message
    }

    func updateRun(_ mutate: (inout Run) -> Void) {
        guard session.allowAutoSave else { return }
        guard var current = run else { return }
        mutate(&current)
        persist(current)
    }

    func persist(_ current: Run) {
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

    func reload() {
        do {
            let loaded = try libraryEnvironment.runLibrary.require(runID)
            run = loaded
            loadRichTextDrafts(from: loaded)
            characterSummaries = try libraryEnvironment.library.listSummaries()
            campaignOptions = try libraryEnvironment.campaignLibrary.listSummaries(includeArchived: true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            run = nil
        }
    }

    func goBack() {
        commitRichTextDrafts(force: true)
        onBack()
    }

    func deleteRun() {
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
final class RunDetailSession {
    var allowAutoSave = true
}
