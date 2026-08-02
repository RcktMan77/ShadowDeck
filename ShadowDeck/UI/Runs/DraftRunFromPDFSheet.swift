//
//  DraftRunFromPDFSheet.swift
//  ShadowDeck
//
//  Phase 2F (experimental): pick a library mission PDF → draft → review → create planning run.
//

import PDFKit
import SwiftUI

struct DraftRunFromPDFSheet: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    var preferredCampaignID: UUID?
    /// When opened from a shelf mission card, pre-select that PDF.
    var preselectedPDFID: UUID?
    var onCancel: () -> Void
    var onCreated: (UUID) -> Void

    @State private var pdfItems: [PDFLibraryItem] = []
    @State private var selectedPDFID: UUID?
    @State private var pageStart: Int = 1
    @State private var pageEnd: Int = 4
    @State private var documentPageCount: Int = 1
    @State private var campaignID: UUID?
    @State private var campaigns: [CampaignSummary] = []
    @State private var edition: Edition = .sr5
    @State private var draft: RunDraft?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var statusNote: String?
    @State private var phase: Phase = .pick

    private enum Phase {
        case pick
        case review
    }

    init(
        preferredCampaignID: UUID? = nil,
        preselectedPDFID: UUID? = nil,
        onCancel: @escaping () -> Void,
        onCreated: @escaping (UUID) -> Void
    ) {
        self.preferredCampaignID = preferredCampaignID
        self.preselectedPDFID = preselectedPDFID
        self.onCancel = onCancel
        self.onCreated = onCreated
        // Seed selection before first render so the picker is not briefly/stuck on first item.
        _selectedPDFID = State(initialValue: preselectedPDFID)
        _campaignID = State(initialValue: preferredCampaignID)
    }

    private var extractionLimits: PDFMissionTextExtractor.Limits {
        .current(aiAvailable: RunDraftGenerator.isOnDeviceAIAvailable)
    }

    private var selectedItem: PDFLibraryItem? {
        pdfItems.first { $0.id == selectedPDFID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                switch phase {
                case .pick:
                    pickForm
                case .review:
                    if let draft {
                        reviewForm(draft)
                    } else {
                        ProgressView("Preparing draft…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: phase == .review ? 680 : 560,
            idealWidth: phase == .review ? 720 : 560,
            minHeight: phase == .review ? 700 : 620,
            idealHeight: phase == .review ? 780 : 620
        )
        .onAppear {
            loadShelf()
        }
        .onChange(of: preselectedPDFID) { _, newID in
            // Parent may repair preselection after mount; honor it.
            if let newID, pdfItems.contains(where: { $0.id == newID }) || pdfItems.isEmpty {
                selectedPDFID = newID
                if !pdfItems.isEmpty {
                    refreshPageBounds()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(phase == .pick ? "Draft run from PDF (Experimental)" : "Review draft")
                    .font(.headline)
                Text(
                    phase == .pick
                        ? pickHeaderSubtitle
                        : (draft?.usedOnDeviceAI == true
                            ? "Experimental on-device AI draft. Edit freely before saving."
                            : "Experimental heuristic draft from PDF text. Edit freely before saving.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            AppChromeButton.title("Cancel", help: "Close without creating a run") {
                onCancel()
            }
        }
        .padding()
    }

    private var pickHeaderSubtitle: String {
        if RunDraftGenerator.isOnDeviceAIAvailable {
            return "Experimental: extract a page range from a mission PDF. On-device AI fills a draft when available — always review before saving."
        }
        return "Experimental: extract a page range from a mission PDF. Without on-device AI, text heuristics fill the draft — always review before saving."
    }

    private var pickForm: some View {
        Form {
            Section {
                if pdfItems.isEmpty {
                    Text(
                        "No Missions & Adventures PDFs on the shelf yet. "
                            + "Open Rules Reference → Library, add a PDF, set its section to Missions & Adventures "
                            + "(Book settings), then return here — or use the sparkles control on a mission cover."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Picker("Mission PDF", selection: $selectedPDFID) {
                        Text("Select…").tag(Optional<UUID>.none)
                        ForEach(pdfItems) { item in
                            Text(item.displayTitle).tag(Optional(item.id))
                        }
                    }
                    .onChange(of: selectedPDFID) { _, _ in
                        refreshPageBounds()
                    }
                }

                HStack {
                    Text("Pages")
                    TextField("Start", value: $pageStart, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("–")
                    TextField("End", value: $pageEnd, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("of \(documentPageCount)")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(pageRangeHelp)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker("Campaign", selection: $campaignID) {
                    Text("Unassigned").tag(Optional<UUID>.none)
                    ForEach(campaigns) { c in
                        Text(c.name).tag(Optional(c.id))
                    }
                }
                Picker("Edition", selection: $edition) {
                    ForEach(Edition.allCases) { ed in
                        Text(ed.shortName).tag(ed)
                    }
                }
                .pickerStyle(.segmented)

                Text(RunDraftGenerator.availabilityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            if let statusNote {
                Text(statusNote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    AppChromeButton.title(
                        "Extract & Draft…",
                        help: "Extract the page range and build a reviewable draft",
                        style: .prominent,
                        isEnabled: selectedPDFID != nil && !isWorking && pageStart <= pageEnd
                    ) {
                        Task { await extractAndDraft() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
    }

    private var pageRangeHelp: String {
        let limits = extractionLimits
        if RunDraftGenerator.isOnDeviceAIAvailable {
            return "Prefer briefing / setup pages. Max \(limits.hardMaxPages) pages (AI context budget)."
        }
        return "Prefer briefing / setup pages, or take a wider range when needed. Max \(limits.hardMaxPages) pages · up to \(limits.maxCharacters.formatted()) characters (heuristic budget)."
    }

    private func reviewForm(_ draftBinding: RunDraft) -> some View {
        Form {
            if !draftBinding.warnings.isEmpty {
                Section("Notes") {
                    ForEach(draftBinding.warnings, id: \.self) { w in
                        Text(w)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Job") {
                expandingField("Title", text: draftTitle, minLines: 1, maxLines: 4)
                expandingField("Mission code / tag", text: draftMissionCode, minLines: 1, maxLines: 3)
                expandingField("Client", text: draftClient, minLines: 1, maxLines: 6)
                expandingField("Location", text: draftLocation, minLines: 1, maxLines: 6)
            }

            Section("Player-facing") {
                expandingField(
                    "What runners know",
                    text: draftPlayerSummary,
                    minLines: 6,
                    maxLines: 80
                )
                expandingField(
                    "Known risks",
                    text: draftKnownRisks,
                    minLines: 4,
                    maxLines: 60
                )
            }

            Section {
                // No inner caption — section title is enough; avoids redundant in-field labels.
                TextField("", text: draftObjectivesText, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(5...40)
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                    }
            } header: {
                Text("Objectives")
            } footer: {
                Text("One objective per line.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("GM-only") {
                expandingField(
                    "Opposition summary",
                    text: draftOpposition,
                    minLines: 4,
                    maxLines: 60
                )
                expandingField(
                    "GM notes",
                    text: draftGMNotes,
                    minLines: 8,
                    maxLines: 120
                )
                HStack {
                    TextField("Expected ¥", value: draftNuyen, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    TextField("Karma", value: draftKarma, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }
                HStack {
                    TextField("Street Cred", value: draftStreetCred, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .help("Typical Street Cred award from the mission")
                    TextField("Notoriety", value: draftNotoriety, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    TextField("Public Awareness", value: draftPublicAwareness, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }
                expandingField(
                    "Reputation notes",
                    text: draftReputationNotes,
                    minLines: 3,
                    maxLines: 20
                )
            }

            Section {
                HStack {
                    AppChromeButton.title("Back", help: "Return to PDF selection") {
                        phase = .pick
                        draft = nil
                    }
                    Spacer()
                    AppChromeButton.title(
                        "Create Planning Run",
                        help: "Save this draft as a planning run",
                        style: .prominent,
                        isEnabled: !(draft?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    ) {
                        createRun()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Multi-line field that grows with content so draft text is not clipped.
    /// Uses an empty prompt so the caption label is not repeated inside the field.
    private func expandingField(
        _ title: String,
        text: Binding<String>,
        minLines: Int,
        maxLines: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", text: text, axis: .vertical)
                .labelsHidden()
                .lineLimit(minLines...maxLines)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.plain)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    // MARK: - Draft field bindings

    private var draftTitle: Binding<String> {
        Binding(
            get: { draft?.title ?? "" },
            set: { draft?.title = $0 }
        )
    }

    private var draftMissionCode: Binding<String> {
        Binding(
            get: { draft?.missionCode ?? "" },
            set: { draft?.missionCode = $0.isEmpty ? nil : $0 }
        )
    }

    private var draftClient: Binding<String> {
        Binding(get: { draft?.client ?? "" }, set: { draft?.client = $0 })
    }

    private var draftLocation: Binding<String> {
        Binding(get: { draft?.location ?? "" }, set: { draft?.location = $0 })
    }

    private var draftPlayerSummary: Binding<String> {
        Binding(get: { draft?.playerFacingSummary ?? "" }, set: { draft?.playerFacingSummary = $0 })
    }

    private var draftKnownRisks: Binding<String> {
        Binding(get: { draft?.knownRisks ?? "" }, set: { draft?.knownRisks = $0 })
    }

    private var draftOpposition: Binding<String> {
        Binding(get: { draft?.oppositionSummary ?? "" }, set: { draft?.oppositionSummary = $0 })
    }

    private var draftGMNotes: Binding<String> {
        Binding(get: { draft?.gmNotes ?? "" }, set: { draft?.gmNotes = $0 })
    }

    private var draftNuyen: Binding<Int?> {
        Binding(get: { draft?.expectedPayoutNuyen }, set: { draft?.expectedPayoutNuyen = $0 })
    }

    private var draftKarma: Binding<Int?> {
        Binding(get: { draft?.expectedKarma }, set: { draft?.expectedKarma = $0 })
    }

    private var draftStreetCred: Binding<Int?> {
        Binding(get: { draft?.expectedStreetCred }, set: { draft?.expectedStreetCred = $0 })
    }

    private var draftNotoriety: Binding<Int?> {
        Binding(get: { draft?.expectedNotoriety }, set: { draft?.expectedNotoriety = $0 })
    }

    private var draftPublicAwareness: Binding<Int?> {
        Binding(get: { draft?.expectedPublicAwareness }, set: { draft?.expectedPublicAwareness = $0 })
    }

    private var draftReputationNotes: Binding<String> {
        Binding(get: { draft?.reputationNotes ?? "" }, set: { draft?.reputationNotes = $0 })
    }

    private var draftObjectivesText: Binding<String> {
        Binding(
            get: { (draft?.objectives ?? []).joined(separator: "\n") },
            set: { text in
                draft?.objectives = text
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    // MARK: - Actions

    private func loadShelf() {
        let store = PDFLibraryStore.loadDefault()
        // Drafting is only meaningful for Missions & Adventures PDFs.
        pdfItems = store.items
            .filter { $0.shelfSection == .mission }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        campaigns = (try? libraryEnvironment.campaignLibrary.listSummaries()) ?? []
        // Prefer explicit preselection (from shelf badge); never clobber it with “first on shelf”.
        if let preselectedPDFID, pdfItems.contains(where: { $0.id == preselectedPDFID }) {
            selectedPDFID = preselectedPDFID
        } else if let selectedPDFID, pdfItems.contains(where: { $0.id == selectedPDFID }) {
            // Keep seed from init if still valid.
        } else {
            selectedPDFID = pdfItems.first?.id
        }
        if campaignID == nil {
            campaignID = preferredCampaignID
        }
        refreshPageBounds()
    }

    private func refreshPageBounds() {
        guard let item = selectedItem else {
            documentPageCount = 1
            return
        }
        let store = PDFLibraryStore.loadDefault()
        let url = store.fileURL(for: item)
        if let doc = PDFDocument(url: url) {
            documentPageCount = max(1, doc.pageCount)
        } else {
            documentPageCount = item.pageCount ?? 1
        }
        let limits = extractionLimits
        pageStart = min(max(1, pageStart), documentPageCount)
        pageEnd = min(max(pageStart, pageEnd), documentPageCount)
        if pageEnd - pageStart + 1 > limits.defaultMaxPages {
            pageEnd = min(documentPageCount, pageStart + limits.defaultMaxPages - 1)
        }
    }

    @MainActor
    private func extractAndDraft() async {
        guard let item = selectedItem else { return }
        isWorking = true
        errorMessage = nil
        statusNote = "Extracting PDF text…"
        defer { isWorking = false }

        let store = PDFLibraryStore.loadDefault()
        let url = store.fileURL(for: item)
        let range = pageStart...max(pageStart, pageEnd)
        let limits = extractionLimits
        do {
            let extracted = try PDFMissionTextExtractor.extract(
                url: url,
                pageRange: range,
                maxPages: limits.hardMaxPages,
                limits: limits
            )
            statusNote = RunDraftGenerator.isOnDeviceAIAvailable
                ? "Drafting with on-device AI…"
                : "Building heuristic draft…"
            let source = RunDraftGenerator.Source(
                pdfID: item.id,
                pdfTitle: item.displayTitle,
                pageRange: extracted.extractedPages,
                extractedText: extracted.text
            )
            var result = await RunDraftGenerator.generate(from: source)
            result.warnings = extracted.warnings + result.warnings
            draft = result
            phase = .review
            statusNote = nil
        } catch {
            errorMessage = error.localizedDescription
            statusNote = nil
        }
    }

    private func createRun() {
        guard let current = draft else { return }
        let run = current.makeRun(edition: edition, campaignID: campaignID)
        do {
            try libraryEnvironment.runLibrary.save(run)
            libraryEnvironment.refreshRunCount()
            onCreated(run.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
