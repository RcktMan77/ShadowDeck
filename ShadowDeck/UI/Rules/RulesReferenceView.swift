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

/// Token for `sheet(item:)` so Draft Run always opens with a concrete mission PDF id.
struct DraftRunSheetRequest: Identifiable, Hashable {
    /// Unique per presentation so reopening the same PDF remounts a fresh sheet.
    let id: UUID
    let pdfID: UUID

    init(pdfID: UUID) {
        self.id = UUID()
        self.pdfID = pdfID
    }
}

struct RulesReferenceView: View {
    @ObservedObject var controller: RulesReferenceController
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    @State private var isImportingPDF = false
    @State var libraryError: String?
    @State var renameDraft: String = ""
    @State var itemPendingRename: PDFLibraryItem?
    @State var itemPendingBookSettings: PDFLibraryItem?
    @State private var isShelfDropTargeted = false
    /// Presents Draft Run sheet with a stable preselected mission PDF id.
    /// Uses `sheet(item:)` so the id is not lost to the isPresented + separate state race.
    @State var draftRunRequest: DraftRunSheetRequest?
    /// Preview-style find for the open PDF.
    @StateObject var pdfSearch = PDFSearchBridge()

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
        .background(RulesWindowTitleSetter(title: windowTitle))
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
        .sheet(item: $draftRunRequest) { request in
            DraftRunFromPDFSheet(
                preselectedPDFID: request.pdfID,
                onCancel: { draftRunRequest = nil },
                onCreated: { runID in
                    draftRunRequest = nil
                    libraryEnvironment.refreshRunCount()
                    NotificationCenter.default.post(
                        name: AppCommand.openRunDetail,
                        object: nil,
                        userInfo: ["runID": runID]
                    )
                }
            )
            .environment(libraryEnvironment)
            // Force a fresh sheet identity per request (same PDF re-opened after dismiss).
            .id(request.id)
        }
    }

    /// Plain title-bar string. A navigation title would bring back the macOS 27 toolbar row.
    private var windowTitle: String {
        controller.mode == .library ? "PDF Shelf" : "Rules Reference"
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
        HSplitView {
            referenceCategorySidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280, maxHeight: .infinity)
            referenceTopicList
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 380, maxHeight: .infinity)
            referenceCardDetail
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
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
                onDraftRun: { beginDraftRun(from: $0) },
                onDropProviders: { handleShelfFileDrop($0) }
            )
        }
    }

    // MARK: Reader status (shelf uses LibraryShelfBrowseView)

    @ViewBuilder
    var statusBanners: some View {
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

/// Sets the window title from the mode. A SwiftUI navigation title would install
/// the macOS 27 sidebar toolbar and move the mode switch.
private struct RulesWindowTitleSetter: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> NSView {
        let view = RulesWindowTitleView()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? RulesWindowTitleView else { return }
        view.title = title
        DispatchQueue.main.async {
            view.applyTitle()
        }
    }
}

private final class RulesWindowTitleView: NSView {
    var title = "" {
        didSet { applyTitle() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: window
        )
        applyTitle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// The setter sits behind the whole window. It must not take clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func windowDidUpdate(_ notification: Notification) {
        applyTitle()
    }

    func applyTitle() {
        guard let window, window.title != title else { return }
        window.title = title
    }
}
