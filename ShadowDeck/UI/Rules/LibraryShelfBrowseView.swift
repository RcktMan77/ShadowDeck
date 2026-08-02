//
//  LibraryShelfBrowseView.swift
//  ShadowDeck
//
//  Library shelf browse phase: filter, full-text search results, gallery/list.
//  Extracted from RulesReferenceView for maintainability.
//

import SwiftUI

/// Shelf browse content (not the PDF reader). Host owns import / rename / settings actions.
struct LibraryShelfBrowseView: View {
    @ObservedObject var controller: RulesReferenceController
    @Binding var isImportingPDF: Bool
    @Binding var isShelfDropTargeted: Bool
    var libraryError: String?
    var coverURL: (PDFLibraryItem) -> URL?
    var onOpen: (PDFLibraryItem) -> Void
    var onBookSettings: (PDFLibraryItem) -> Void
    var onRename: (PDFLibraryItem) -> Void
    var onReveal: (PDFLibraryItem) -> Void
    var onRemove: (PDFLibraryItem) -> Void
    /// Draft a planning run from a Missions & Adventures PDF.
    var onDraftRun: (PDFLibraryItem) -> Void
    var onDropProviders: ([NSItemProvider]) -> Bool

    private var shelfFieldWidth: CGFloat { 240 }

    var body: some View {
        VStack(spacing: 0) {
            shelfToolbar
            Divider()
            statusBanners
            shelfBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isShelfDropTargeted) { providers in
            onDropProviders(providers)
        }
        .overlay {
            if isShelfDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Toolbar

    private var shelfToolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            shelfSearchField

            HStack(spacing: 8) {
                shelfTextSearchField
                if controller.libraryTextSearching {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching PDFs")
                }
                Button("Search") {
                    controller.runLibraryTextSearch()
                }
                .controlSize(.small)
                .disabled(
                    controller.libraryTextQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || controller.libraryTextSearching
                )
                .accessibilityLabel("Search inside PDFs")
                if controller.libraryTextSearchActive || !controller.libraryTextQuery.isEmpty {
                    Button("Clear") {
                        controller.clearLibraryTextSearch()
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Clear PDF search")
                }
            }

            Spacer(minLength: 8)

            shelfChromeControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var shelfChromeControls: some View {
        // Match regular-size AppChromeButton (34pt host) with regular pickers.
        let h = AppChromeButton.chromeHeight
        return HStack(alignment: .center, spacing: 10) {
            Picker("Layout", selection: Binding(
                get: { controller.libraryLayout },
                set: { controller.libraryLayout = $0; controller.persistUIState() }
            )) {
                ForEach(LibraryShelfLayout.allCases) { layout in
                    Image(systemName: layout.systemImage)
                        .tag(layout)
                        .help(layout.title)
                        .accessibilityLabel(layout.title)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .labelsHidden()
            .frame(width: 88, height: h)
            .help("List or Gallery view")
            .accessibilityLabel("Shelf layout")

            Picker("Sort", selection: Binding(
                get: { controller.librarySort },
                set: { controller.librarySort = $0; controller.persistUIState() }
            )) {
                ForEach(LibraryShelfSort.allCases) { sort in
                    Text(sort.menuLabel).tag(sort)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.regular)
            .frame(minWidth: 110, idealWidth: 140, maxWidth: 160, minHeight: h, maxHeight: h)
            .help("Sort within each section")
            .accessibilityLabel("Sort shelf")

            AppChromeButton.labeled(
                "Add PDF…",
                systemImage: "doc.badge.plus",
                help: "Add a PDF you own to the Library shelf"
            ) {
                isImportingPDF = true
            }
        }
        .frame(height: h)
    }

    private var shelfSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Filter books…", text: $controller.libraryFilter)
                .textFieldStyle(.plain)
            if !controller.libraryFilter.isEmpty {
                Button {
                    Task { @MainActor in controller.libraryFilter = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear book filter")
            }
        }
        .padding(7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: shelfFieldWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter books")
    }

    private var shelfTextSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search inside PDFs…", text: $controller.libraryTextQuery)
                .textFieldStyle(.plain)
                .onSubmit { controller.runLibraryTextSearch() }
            if !controller.libraryTextQuery.isEmpty {
                Button {
                    controller.clearLibraryTextSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear PDF search query")
            }
        }
        .padding(7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: shelfFieldWidth, alignment: .leading)
        .help("Search text inside shelf PDFs. Multi-word queries match pages that contain all words.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search inside PDFs")
    }

    // MARK: Status + body

    @ViewBuilder
    private var statusBanners: some View {
        if let libraryError {
            Text(libraryError)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
        }
        if let status = controller.libraryStatusMessage {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
        }
    }

    @ViewBuilder
    private var shelfBody: some View {
        if controller.libraryTextSearchActive {
            libraryTextResultsList
        } else {
            shelfBooksBody
        }
    }

    @ViewBuilder
    private var libraryTextResultsList: some View {
        if controller.libraryTextSearching {
            VStack(spacing: 12) {
                ProgressView("Searching PDFs…")
                Text("Large rulebooks can take a few seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.libraryTextHits.isEmpty {
            ContentUnavailableView {
                Label("No Matches", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text(controller.libraryTextSearchStatus
                    ?? "No text matches. Try fewer or different words.")
            } actions: {
                Button("Back to shelf") {
                    controller.clearLibraryTextSearch()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                libraryTextResultsChrome
                Divider()
                List(selection: Binding(
                    get: { controller.libraryTextHitIndex },
                    set: { controller.selectLibraryHitIndex($0) }
                )) {
                    Section {
                        Text("\(controller.libraryTextHits.count) match(es) · best matches first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(controller.libraryTextHits.enumerated()), id: \.element.id) { index, hit in
                        Button {
                            controller.selectLibraryHitIndex(index)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(hit.bookTitle)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(hit.relevanceLabel)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(
                                            hit.matchedTokenCount >= hit.queryTokenCount
                                                ? Color.accentColor : Color.secondary
                                        )
                                    Text("p. \(hit.page)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(hit.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                        .listRowBackground(
                            index == controller.libraryTextHitIndex
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var libraryTextResultsChrome: some View {
        HStack(spacing: 8) {
            AppChromeButton.labeled(
                "Previous",
                systemImage: "chevron.up",
                help: "Previous search result",
                isEnabled: controller.canGoToPreviousLibraryHit
            ) {
                controller.goToPreviousLibraryHit()
            }

            AppChromeButton.labeled(
                "Next",
                systemImage: "chevron.down",
                help: "Next search result",
                isEnabled: controller.canGoToNextLibraryHit
            ) {
                controller.goToNextLibraryHit()
            }

            if !controller.libraryTextHits.isEmpty {
                Text("\(controller.libraryTextHitIndex + 1) of \(controller.libraryTextHits.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Result \(controller.libraryTextHitIndex + 1) of \(controller.libraryTextHits.count)"
                    )
            }

            Spacer()

            AppChromeButton.title("Back to shelf", help: "Clear PDF text search and return to the shelf") {
                controller.clearLibraryTextSearch()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var shelfSummaryLine: String {
        let items = controller.pdfLibrary.items
        var parts: [String] = ["\(items.count) book(s)"]
        for section in PDFShelfSection.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let count = items.filter { $0.shelfSection == section }.count
            guard count > 0 else { continue }
            parts.append(shelfSectionCountLabel(count, section: section))
        }
        return parts.joined(separator: " · ")
    }

    private func shelfSectionCountLabel(_ count: Int, section: PDFShelfSection) -> String {
        switch section {
        case .coreRulebook: return "\(count) core rulebook(s)"
        case .mission: return "\(count) mission & adventure(s)"
        case .sourcebook: return "\(count) sourcebook(s)"
        case .other: return "\(count) other"
        }
    }

    @ViewBuilder
    private var shelfBooksBody: some View {
        let groups = controller.librarySectionGroups
        if groups.isEmpty {
            if controller.pdfLibrary.items.isEmpty {
                // Primary path is Add PDF… in the shelf header (and drag-and-drop).
                // Match Runs/Campaigns: copy only — no duplicate empty-state CTA.
                ContentUnavailableView {
                    Label("No Books Yet", systemImage: "books.vertical.fill")
                } description: {
                    Text(
                        "Add PDFs you legally own. They stay on this Mac only. "
                            + "Drag a PDF onto this shelf, or use Add PDF… above."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "magnifyingglass")
                } description: {
                    Text("No books match the filter.")
                } actions: {
                    AppChromeButton.title("Clear Filter", help: "Clear the book filter") {
                        Task { @MainActor in controller.libraryFilter = "" }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(shelfSummaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                switch controller.libraryLayout {
                case .gallery:
                    PDFLibraryGalleryView(
                        groups: groups,
                        coverURL: coverURL,
                        onOpen: onOpen,
                        onBookSettings: onBookSettings,
                        onRename: onRename,
                        onReveal: onReveal,
                        onRemove: onRemove,
                        onDraftRun: onDraftRun
                    )
                case .list:
                    PDFLibraryListView(
                        groups: groups,
                        coverURL: coverURL,
                        onOpen: onOpen,
                        onBookSettings: onBookSettings,
                        onRename: onRename,
                        onReveal: onReveal,
                        onRemove: onRemove,
                        onDraftRun: onDraftRun
                    )
                }
            }
        }
    }
}
