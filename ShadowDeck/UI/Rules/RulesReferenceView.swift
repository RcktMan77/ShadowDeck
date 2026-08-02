//
//  RulesReferenceView.swift
//  ShadowDeck
//
//  Dedicated-window Rules Reference with two modes:
//  Reference (cards + calculators) and Library (shelf browse + reader).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RulesReferenceView: View {
    @ObservedObject var controller: RulesReferenceController
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isImportingPDF = false
    @State private var libraryError: String?
    @State private var renameDraft: String = ""
    @State private var itemPendingRename: PDFLibraryItem?
    @State private var itemPendingBookSettings: PDFLibraryItem?
    @State private var isShelfDropTargeted = false
    /// Preview-style find for the open PDF.
    @StateObject private var pdfSearch = PDFSearchBridge()

    var body: some View {
        VStack(spacing: 0) {
            modeChrome
            Divider()
            Group {
                switch controller.mode {
                case .reference:
                    referenceSplit
                case .library:
                    libraryContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Window scene already titles the chrome “Rules Reference”; avoid a second nav title + toolbar clutter.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Defer: writing @Published during onAppear can still trip
            // “Publishing changes from within view updates” on macOS.
            Task { @MainActor in
                controller.ensureInitialSelection()
                ensureMissingCovers()
            }
        }
        .onChange(of: controller.mode) { _, mode in
            if mode == .library {
                Task { @MainActor in ensureMissingCovers() }
            }
        }
        .fileImporter(
            isPresented: $isImportingPDF,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: $itemPendingRename) { item in
            renameSheet(for: item)
        }
        .sheet(item: $itemPendingBookSettings) { item in
            // Self-contained editor: owns its controls so parent re-renders
            // (PDF page ticks, search) cannot freeze or reset the sheet mid-edit.
            BookSettingsSheet(
                item: item,
                coverURL: coverURL(for: item),
                onCancel: { itemPendingBookSettings = nil },
                onSave: { section, key, offset in
                    commitBookSettings(itemID: item.id, section: section, bookKey: key, pageOffset: offset)
                }
            )
        }
    }

    // MARK: - Mode switch

    private var modeChrome: some View {
        HStack(spacing: 16) {
            modeSwitch
                .frame(maxWidth: 280)

            if controller.mode == .reference {
                referenceSearchField
            }
            // Library filter lives on the shelf toolbar (not here) so reader stays uncluttered.

            if let edition = controller.editionFilter, controller.mode == .reference {
                HStack(spacing: 6) {
                    Text(edition.shortName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(.tint)
                    Button {
                        Task { @MainActor in controller.editionFilter = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear edition filter")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Toggle between Reference (off) and Library (on).
    private var modeSwitch: some View {
        HStack(spacing: 10) {
            Text("Reference")
                .font(.body.weight(controller.mode == .reference ? .semibold : .regular))
                .foregroundStyle(controller.mode == .reference ? Color.primary : Color.secondary)
                .onTapGesture { controller.switchMode(.reference) }

            Toggle(
                "Library mode",
                isOn: Binding(
                    get: { controller.mode == .library },
                    set: { on in controller.switchMode(on ? .library : .reference) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("Reference or Library mode")
            .accessibilityValue(controller.mode == .library ? "Library" : "Reference")

            Text("Library")
                .font(.body.weight(controller.mode == .library ? .semibold : .regular))
                .foregroundStyle(controller.mode == .library ? Color.primary : Color.secondary)
                .onTapGesture { controller.switchMode(.library) }
        }
    }

    private var referenceSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search rules…", text: $controller.query)
                .textFieldStyle(.plain)
            if !controller.query.isEmpty {
                Button {
                    Task { @MainActor in controller.query = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 360)
    }

    // MARK: - Reference mode

    private var referenceSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            referenceCategorySidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            referenceTopicList
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
        } detail: {
            referenceCardDetail
        }
    }

    private var referenceCategorySidebar: some View {
        List {
            Section("Categories") {
                categorySidebarRow(
                    title: "All topics",
                    symbol: "square.grid.2x2.fill",
                    category: nil
                )
                ForEach(RuleCategory.allCases.filter { $0 != .catalog && $0 != .other }) { cat in
                    categorySidebarRow(
                        title: cat.displayName,
                        symbol: categorySymbol(cat),
                        category: cat
                    )
                }
            }

            Section("Books") {
                Text("Open Library to browse PDFs you own. Page chips jump there when a book key is set.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                AppChromeButton.labeled(
                    "Open Library",
                    systemImage: "books.vertical.fill",
                    help: "Browse PDFs you own in Library mode"
                ) {
                    controller.switchMode(.library)
                    controller.backToShelf()
                }
            }

            if !controller.loadErrors.isEmpty {
                Section {
                    Text(controller.loadErrors.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 28)
    }

    private func categorySidebarRow(title: String, symbol: String, category: RuleCategory?) -> some View {
        let selected = controller.selectedCategory == category
        return Button {
            controller.selectCategory(category)
        } label: {
            HStack {
                rulesSidebarLabel(title, systemImage: symbol)
                Spacer()
                Text("\(controller.count(for: category))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    /// Match main window sidebar: larger hierarchical glyph + body label.
    private func rulesSidebarLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.body)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 24, height: 20, alignment: .center)
        }
        .labelStyle(.titleAndIcon)
    }

    private var referenceTopicList: some View {
        Group {
            let rows = controller.results
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(
                        controller.store.entries.isEmpty ? "No Rules Loaded" : "No Matches",
                        systemImage: controller.store.entries.isEmpty
                            ? "exclamationmark.triangle"
                            : "magnifyingglass"
                    )
                } description: {
                    Text(
                        controller.store.entries.isEmpty
                            ? "Rules seed failed to load."
                            : "Try another search or category."
                    )
                }
            } else {
                ScrollViewReader { proxy in
                    List(rows, selection: Binding(
                        get: { controller.selectedID },
                        set: { if let id = $0 { controller.selectRule(id) } }
                    )) { hit in
                        resultRow(hit)
                            .tag(hit.entry.id)
                            .id(hit.entry.id)
                    }
                    .listStyle(.inset)
                    .onChange(of: controller.topicsScrollEpoch) { _, _ in
                        scrollTopicsList(proxy: proxy)
                    }
                    .onChange(of: controller.selectedID) { _, newID in
                        // When selection jumps programmatically (Look up), ensure visibility.
                        guard newID != nil, controller.topicsScrollEpoch > 0 else { return }
                        scrollTopicsList(proxy: proxy)
                    }
                    .onChange(of: controller.query) { _, _ in
                        // Typing in search: select best hit and bring it into view.
                        controller.syncRuleSelectionToResults(preferTopHit: true)
                        controller.requestTopicsScrollToSelection()
                    }
                }
            }
        }
        .navigationTitle("Topics")
    }

    private func scrollTopicsList(proxy: ScrollViewProxy) {
        guard let id = controller.selectedID else { return }
        // Wait a turn so List has applied the new data/selection after Look up.
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    private func resultRow(_ hit: RulesReferenceSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.entry.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(hit.entry.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if hit.entry.calculator != nil {
                    Image(systemName: "function")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !hit.entry.pageRefs.isEmpty {
                    Image(systemName: "book.closed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var referenceCardDetail: some View {
        if let entry = controller.selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RuleDetailCard(
                        entry: entry,
                        edition: controller.editionFilter ?? controller.calcContext.edition,
                        houseRules: controller.calcContext.houseRules,
                        diceRules: controller.calcContext.diceRules,
                        calcContext: controller.calcContext,
                        preferPageEdition: controller.editionFilter ?? controller.calcContext.edition,
                        relatedTitle: { controller.store.entry(id: $0)?.title },
                        onPageRefTap: { handlePageRef($0) },
                        bookKeyIsBound: { controller.pdfLibrary.item(bookKey: $0) != nil },
                        onRelatedTap: { relatedID in
                            controller.selectRule(relatedID)
                            controller.requestTopicsScrollToSelection()
                        }
                    )
                    if entry.pageRefs.contains(where: {
                        controller.pdfLibrary.item(bookKey: $0.bookKey) == nil
                    }) {
                        unboundPageRefHelp
                    }
                }
                .padding(20)
            }
            .navigationTitle(entry.title)
        } else {
            ContentUnavailableView {
                Label("Select a Card", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Choose a topic for summary, formula, and calculators. From the character sheet, use Look up on Skills, Plan, Lifestyle, or Dice to jump here with a search.")
            } actions: {
                Button("Clear filters") {
                    controller.clearFilters()
                }
            }
        }
    }

    private var unboundPageRefHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unbound page references")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Open Library, add a PDF you own, open it, and use Book settings to set a book key. Then chips open that book at the listed page.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            AppChromeButton.labeled(
                "Open Library & Add PDF…",
                systemImage: "doc.badge.plus",
                help: "Switch to Library mode and add a PDF you own"
            ) {
                controller.switchMode(.library)
                controller.backToShelf()
                isImportingPDF = true
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Library mode (shelf ↔ reader)

    @ViewBuilder
    private var libraryContent: some View {
        if controller.selectedPDFItem != nil {
            libraryReader
        } else {
            LibraryShelfBrowseView(
                controller: controller,
                isImportingPDF: $isImportingPDF,
                isShelfDropTargeted: $isShelfDropTargeted,
                libraryError: libraryError,
                coverURL: { coverURL(for: $0) },
                onOpen: { openBookDeferred($0.id) },
                onBookSettings: { beginBookSettings($0) },
                onRename: { beginRename($0) },
                onReveal: { revealInFinder($0) },
                onRemove: { removePDF($0.id) },
                onDropProviders: { handleShelfFileDrop($0) }
            )
        }
    }

    // MARK: Reader status (shelf uses LibraryShelfBrowseView)

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

    // MARK: Reader (one book)

    @ViewBuilder
    private var libraryReader: some View {
        if let item = controller.selectedPDFItem {
            let url = controller.pdfLibrary.fileURL(for: item)
            // Explicit top chrome + flexible reader — avoid VStack intrinsic-size collapse
            // that left PDFKit with a ~0 height host (thin scrollbar strip).
            VStack(spacing: 0) {
                readerChrome(for: item)
                Divider()
                statusBanners
                PDFReaderControlsBar(
                    pageCount: item.pageCount,
                    page: pageBinding,
                    zoomPreset: zoomBinding(for: item.id),
                    search: pdfSearch
                )
                Divider()
                Group {
                    if FileManager.default.fileExists(atPath: url.path) {
                        PDFReaderWorkspace(
                            url: url,
                            page: pageBinding,
                            zoomPreset: zoomBinding(for: item.id),
                            navigationEpoch: controller.pdfNavigationEpoch,
                            searchBridge: pdfSearch
                        ) { page in
                                persistLastPage(itemID: item.id, page: page)
                        }
                        .id(item.id)
                        .onAppear {
                            // Clear find results after the mount update (not mid-body).
                            Task { @MainActor in
                                await Task.yield()
                                pdfSearch.clear()
                            }
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Missing File", systemImage: "doc.questionmark")
                        } description: {
                            Text("This shelf entry’s file is missing. Remove it and add the PDF again.")
                        } actions: {
                            AppChromeButton.title("Back to shelf", help: "Return to the Library shelf") {
                                controller.backToShelf()
                            }
                            AppChromeButton.title(
                                "Remove",
                                help: "Remove this shelf entry",
                                style: .destructive
                            ) {
                                removePDF(item.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func readerChrome(for item: PDFLibraryItem) -> some View {
        HStack(spacing: 8) {
            AppChromeButton.labeled(
                "All books",
                systemImage: "chevron.left",
                help: "Back to the Library shelf (clears PDF text search)"
            ) {
                controller.backToShelf()
            }

            if controller.canReturnToSearchResults {
                AppChromeButton.labeled(
                    "Search results",
                    systemImage: "doc.text.magnifyingglass",
                    help: "Back to PDF text search results"
                ) {
                    controller.backToSearchResults()
                }
            }

            if controller.canReturnToCard {
                AppChromeButton.labeled(
                    "Back to card",
                    systemImage: "doc.text",
                    help: "Back to the Rules Reference card"
                ) {
                    controller.backToCard()
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.shelfSection.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let key = item.bookKey, !key.isEmpty {
                        Text(key)
                            .font(.caption2.weight(.semibold).monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(.tint)
                    } else {
                        Text("No book key")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let count = item.pageCount {
                        Text("\(count) pages")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            // Trailing chrome: Book settings + single ellipsis more (no pull-down caret).
            HStack(alignment: .center, spacing: 8) {
                AppChromeButton.labeled(
                    (item.bookKey?.isEmpty == false) ? "Book settings" : "Book settings…",
                    systemImage: "slider.horizontal.3",
                    help: "Section, book key, and metadata for page chips"
                ) {
                    beginBookSettings(item)
                }

                Menu {
                    Button("Rename…") { beginRename(item) }
                    Button("Reveal in Finder") { revealInFinder(item) }
                    Button("Refresh cover from page 1") { refreshCover(item.id) }
                    Divider()
                    Button("Remove from library", role: .destructive) {
                        removePDF(item.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: AppChromeButton.chromeHeight, height: AppChromeButton.chromeHeight)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: AppChromeButton.chromeHeight, height: AppChromeButton.chromeHeight)
                .help("More book actions")
                .accessibilityLabel("More")
            }
            .frame(height: AppChromeButton.chromeHeight)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Open a shelf book (controller already defers publishes off the view-update stack).
    private func openBookDeferred(_ id: UUID, page: Int? = nil) {
        controller.selectPDF(id, page: page)
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { controller.pdfTargetPage },
            set: { new in
                let page = max(1, new)
                guard controller.pdfTargetPage != page else { return }
                // Text field / buttons: user-driven, outside representable update.
                // PDFKit still publishes page via afterViewUpdate → this setter.
                controller.pdfTargetPage = page
            }
        )
    }

    private func zoomBinding(for itemID: UUID) -> Binding<PDFZoomPreset> {
        Binding(
            get: { controller.zoomPreset(for: itemID) },
            set: { new in
                guard controller.zoomPreset(for: itemID) != new else { return }
                // Write immediately so get() and the reader match the Picker.
                controller.setZoomPreset(new, for: itemID)
            }
        )
    }

    // MARK: - Sheets

    private func renameSheet(for item: PDFLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename book")
                .font(.headline)
            TextField("Title", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitRename(item) }
            HStack {
                Spacer()
                Button("Cancel") { itemPendingRename = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { commitRename(item) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            libraryError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            importPDF(from: url, openReader: true)
        }
    }

    private func handleShelfFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let urlItem = item as? URL {
                url = urlItem
            } else if let str = item as? String {
                url = URL(fileURLWithPath: str)
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                importPDF(from: url, openReader: false)
            }
        }
        return true
    }

    private func importPDF(from url: URL, openReader: Bool) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            var library = controller.pdfLibrary
            let item = try library.addPDF(from: url)
            controller.replacePDFLibrary(library)
            if openReader {
                openBookDeferred(item.id)
            }
            Task { @MainActor in
                controller.libraryStatusMessage = "Added “\(item.displayTitle)”."
            }
            libraryError = nil
        } catch {
            libraryError = error.localizedDescription
        }
    }

    private func removePDF(_ id: UUID) {
        do {
            let title = controller.pdfLibrary.item(id: id)?.displayTitle ?? "Book"
            var library = controller.pdfLibrary
            try library.remove(id: id)
            controller.replacePDFLibrary(library)
            if controller.selectedLibraryItemID == id {
                controller.backToShelf()
            }
            Task { @MainActor in
                controller.libraryStatusMessage = "Removed “\(title)”."
            }
            libraryError = nil
        } catch {
            libraryError = error.localizedDescription
        }
    }

    private func bindBookKey(_ id: UUID, key: String?) {
        do {
            var library = controller.pdfLibrary
            try library.setBookKey(id: id, bookKey: key)
            controller.replacePDFLibrary(library)
            let title = library.item(id: id)?.displayTitle ?? "Book"
            Task { @MainActor in
                if let key, !key.isEmpty {
                    let label = PDFBookKeyCatalog.curated.first { $0.key == key }?.label ?? key
                    controller.libraryStatusMessage = "“\(title)” bound as \(label) (\(key))."
                } else {
                    controller.libraryStatusMessage = "Cleared book key on “\(title)”."
                }
            }
            libraryError = nil
        } catch {
            libraryError = error.localizedDescription
        }
    }

    private func beginRename(_ item: PDFLibraryItem) {
        renameDraft = item.displayTitle
        itemPendingRename = item
    }

    private func commitRename(_ item: PDFLibraryItem) {
        let title = renameDraft
        itemPendingRename = nil
        do {
            var library = controller.pdfLibrary
            try library.setTitle(id: item.id, title: title)
            controller.replacePDFLibrary(library)
            Task { @MainActor in
                controller.libraryStatusMessage = "Renamed to “\(library.item(id: item.id)?.displayTitle ?? title)”."
            }
            libraryError = nil
        } catch {
            libraryError = error.localizedDescription
        }
    }

    private func beginBookSettings(_ item: PDFLibraryItem) {
        // PDFView often holds first responder; resign so sheet controls receive clicks.
        NSApp.keyWindow?.makeFirstResponder(nil)
        // Defer presentation past the current event so the sheet is fully interactive.
        Task { @MainActor in
            await Task.yield()
            itemPendingBookSettings = item
        }
    }

    private func commitBookSettings(
        itemID: UUID,
        section: PDFShelfSection,
        bookKey: String?,
        pageOffset: Int
    ) {
        itemPendingBookSettings = nil
        let offset = max(0, pageOffset)
        do {
            var library = controller.pdfLibrary
            try library.setShelfSection(id: itemID, section: section)
            try library.setBookKey(id: itemID, bookKey: bookKey)
            try library.setPageOffset(id: itemID, pageOffset: offset)
            controller.replacePDFLibrary(library)
            let title = library.item(id: itemID)?.displayTitle ?? "Book"
            Task { @MainActor in
                var parts = [section.displayName]
                if let bookKey, !bookKey.isEmpty {
                    parts.append(bookKey)
                } else {
                    parts.append("no book key")
                }
                if offset > 0 {
                    parts.append("offset +\(offset)")
                }
                controller.libraryStatusMessage = "Updated “\(title)” · \(parts.joined(separator: " · "))."
            }
            libraryError = nil
        } catch {
            libraryError = error.localizedDescription
        }
    }

    private func coverURL(for item: PDFLibraryItem) -> URL? {
        controller.pdfLibrary.coverURL(for: item)
    }

    private func ensureMissingCovers() {
        var library = controller.pdfLibrary
        var changed = false
        for item in library.items where library.coverURL(for: item) == nil {
            if library.ensureCover(id: item.id) {
                changed = true
            }
        }
        if changed {
            controller.replacePDFLibrary(library)
        }
    }

    private func refreshCover(_ id: UUID) {
        var library = controller.pdfLibrary
        if library.refreshCover(id: id) {
            controller.replacePDFLibrary(library)
            Task { @MainActor in
                controller.libraryStatusMessage = "Cover refreshed from page 1."
            }
        }
    }

    private func revealInFinder(_ item: PDFLibraryItem) {
        let url = controller.pdfLibrary.fileURL(for: item)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func persistLastPage(itemID: UUID, page: Int) {
        // Page callbacks can nest under view updates; never publish the store inline.
        Task { @MainActor in
            do {
                var library = controller.pdfLibrary
                if library.item(id: itemID)?.lastOpenedPage == page { return }
                try library.setLastOpenedPage(id: itemID, page: page)
                controller.replacePDFLibrary(library)
            } catch {
                // Non-fatal
            }
        }
    }

    private func handlePageRef(_ ref: PageRef) {
        if controller.pdfLibrary.item(bookKey: ref.bookKey) != nil {
            libraryError = nil
            controller.openPageRef(ref)
        } else {
            libraryError = "No PDF bound to “\(ref.bookKey)”. Open Library, open your book, and use Book settings to set that key."
            controller.switchMode(.library)
            controller.backToShelf()
        }
    }

    private func categorySymbol(_ cat: RuleCategory) -> String {
        switch cat {
        case .dice: "dice.fill"
        case .advancement: "arrow.up.heart.fill"
        case .lifestyle: "house.fill"
        case .combat: "shield.lefthalf.filled"
        case .magic: "sparkles"
        case .matrix: "network"
        case .social: "person.2.fill"
        case .chargen: "person.badge.plus"
        case .catalog: "books.vertical.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

// MARK: - Book settings sheet

/// Self-contained editor so library/reader parent updates cannot freeze controls.
private struct BookSettingsSheet: View {
    let item: PDFLibraryItem
    let coverURL: URL?
    var onCancel: () -> Void
    var onSave: (_ section: PDFShelfSection, _ bookKey: String?, _ pageOffset: Int) -> Void

    @State private var section: PDFShelfSection
    /// `"none"` | curated key | `"custom"`.
    @State private var keyChoice: String
    @State private var customKey: String
    @State private var pageOffset: Int

    init(
        item: PDFLibraryItem,
        coverURL: URL?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (PDFShelfSection, String?, Int) -> Void
    ) {
        self.item = item
        self.coverURL = coverURL
        self.onCancel = onCancel
        self.onSave = onSave

        _section = State(initialValue: item.shelfSection)
        _pageOffset = State(initialValue: max(0, item.pageOffset))

        if let key = item.bookKey, !key.isEmpty {
            if PDFBookKeyCatalog.curated.contains(where: { $0.key == key }) {
                _keyChoice = State(initialValue: key)
                _customKey = State(initialValue: "")
            } else {
                _keyChoice = State(initialValue: "custom")
                _customKey = State(initialValue: key)
            }
        } else {
            _keyChoice = State(initialValue: "none")
            _customKey = State(initialValue: "")
        }
    }

    private var canSave: Bool {
        if keyChoice == "custom" {
            return !customKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var pageOffsetHelp: String {
        if pageOffset == 0 {
            return "Printed p. 1 = PDF page 1 (no offset)."
        }
        let pdfForPrint1 = 1 + pageOffset
        return "Printed p. 1 = PDF page \(pdfForPrint1). Example: chip p. 2 opens PDF page \(2 + pageOffset)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                PDFCoverImage(coverURL: coverURL, cornerRadius: 6)
                    .frame(width: 72, height: 96)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Book settings")
                        .font(.headline)
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text("Shelf section and book key control how this PDF appears and which page chips open it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .padding(.bottom, 4)

            Form {
                Section {
                    Picker("Shelf section", selection: $section) {
                        ForEach(PDFShelfSection.allCases) { s in
                            Label(s.displayName, systemImage: s.systemImage)
                                .tag(s)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                } header: {
                    Text("Shelf section")
                }

                Section {
                    Picker("Book key", selection: $keyChoice) {
                        Text("None").tag("none")
                        ForEach(PDFBookKeyCatalog.curated, id: \.key) { entry in
                            Text("\(entry.label)  ·  \(entry.key)").tag(entry.key)
                        }
                        Text("Custom…").tag("custom")
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    if keyChoice == "custom" {
                        TextField("custom-book-key", text: $customKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                    }

                    Text("Reference cards open this PDF when their chip uses the same key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Book key (page chips)")
                }

                Section {
                    Stepper(value: $pageOffset, in: 0...50) {
                        HStack {
                            Text("Front matter pages")
                            Spacer()
                            Text("\(pageOffset)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Reference chips use printed page numbers. Unnumbered front matter sits before printed page 1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(pageOffsetHelp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Page numbering")
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 420)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(minWidth: 460, idealWidth: 480)
        .onAppear {
            // Belt-and-suspenders: sheet window should own key focus, not PDFKit.
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private func save() {
        let resolvedKey: String?
        switch keyChoice {
        case "none":
            resolvedKey = nil
        case "custom":
            let trimmed = customKey.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedKey = trimmed.isEmpty ? nil : trimmed
        default:
            resolvedKey = keyChoice
        }
        onSave(section, resolvedKey, max(0, pageOffset))
    }
}

// MARK: - Window root

struct RulesReferenceWindowRoot: View {
    /// Observe the session root so the window stays tied to the process-wide session.
    /// The controller is still the source of `@Published` UI state for the view tree.
    @ObservedObject private var session = RulesReferenceSession.shared

    var body: some View {
        RulesReferenceView(controller: session.controller)
            .frame(minWidth: 880, minHeight: 520)
    }
}
