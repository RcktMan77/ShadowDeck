//
//  RulesReferenceView+Reader.swift
//  ShadowDeck
//
//  Open-book reader for the Rules Reference window.
//

import PDFKit
import SwiftUI

extension RulesReferenceView {
    // MARK: Reader (one book)

    @ViewBuilder
    var libraryReader: some View {
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

    func readerChrome(for item: PDFLibraryItem) -> some View {
        HStack(alignment: .center, spacing: 8) {
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

            // More menu left of title (vertically centered on title line only);
            // subtitle sits under the title, indented past the icon.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Menu {
                        if item.shelfSection == .mission {
                            Button("Draft run from PDF…") { beginDraftRun(from: item) }
                            Divider()
                        }
                        Button("Rename…") { beginRename(item) }
                        Button("Reveal in Finder") { revealInFinder(item) }
                        Button("Refresh cover from page 1") { refreshCover(item.id) }
                        Divider()
                        Button("Remove from library", role: .destructive) {
                            removePDF(item.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22, height: 22)
                    .help("More book actions")
                    .accessibilityLabel("More")

                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                }

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
                // Align metadata under title text (22 icon + 6 spacing).
                .padding(.leading, 28)
            }

            Spacer(minLength: 8)

            if item.shelfSection == .mission {
                AppChromeButton.labeled(
                    "Draft run…",
                    systemImage: "sparkles",
                    help: "Draft a planning run from this mission PDF"
                ) {
                    beginDraftRun(from: item)
                }
            }

            // Flush trailing: book settings only.
            AppChromeButton.labeled(
                (item.bookKey?.isEmpty == false) ? "Book settings" : "Book settings…",
                systemImage: "slider.horizontal.3",
                help: "Section, book key, and metadata for page chips"
            ) {
                beginBookSettings(item)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    func beginDraftRun(from item: PDFLibraryItem) {
        guard item.shelfSection == .mission else { return }
        // Unique presentation id each time so sheet(item:) always remounts with this pdfID.
        draftRunRequest = DraftRunSheetRequest(pdfID: item.id)
    }

    /// Open a shelf book (controller already defers publishes off the view-update stack).
    func openBookDeferred(_ id: UUID, page: Int? = nil) {
        controller.selectPDF(id, page: page)
    }

    var pageBinding: Binding<Int> {
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

    func zoomBinding(for itemID: UUID) -> Binding<PDFZoomPreset> {
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

}
