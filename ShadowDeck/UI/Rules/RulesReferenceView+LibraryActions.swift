//
//  RulesReferenceView+LibraryActions.swift
//  ShadowDeck
//
//  Shelf import, rename, book settings, and cover refresh.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension RulesReferenceView {
    func renameSheet(for item: PDFLibraryItem) -> some View {
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

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            libraryError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            importPDF(from: url, openReader: true)
        }
    }

    func handleShelfFileDrop(_ providers: [NSItemProvider]) -> Bool {
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

    func importPDF(from url: URL, openReader: Bool) {
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

    func removePDF(_ id: UUID) {
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

    func bindBookKey(_ id: UUID, key: String?) {
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

    func beginRename(_ item: PDFLibraryItem) {
        renameDraft = item.displayTitle
        itemPendingRename = item
    }

    func commitRename(_ item: PDFLibraryItem) {
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

    func beginBookSettings(_ item: PDFLibraryItem) {
        // PDFView often holds first responder; resign so sheet controls receive clicks.
        NSApp.keyWindow?.makeFirstResponder(nil)
        // Defer presentation past the current event so the sheet is fully interactive.
        Task { @MainActor in
            await Task.yield()
            itemPendingBookSettings = item
        }
    }

    func commitBookSettings(
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

    func coverURL(for item: PDFLibraryItem) -> URL? {
        controller.pdfLibrary.coverURL(for: item)
    }

    func ensureMissingCovers() {
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

    func refreshCover(_ id: UUID) {
        var library = controller.pdfLibrary
        if library.refreshCover(id: id) {
            controller.replacePDFLibrary(library)
            Task { @MainActor in
                controller.libraryStatusMessage = "Cover refreshed from page 1."
            }
        }
    }

    func revealInFinder(_ item: PDFLibraryItem) {
        let url = controller.pdfLibrary.fileURL(for: item)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func persistLastPage(itemID: UUID, page: Int) {
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

    func handlePageRef(_ ref: PageRef) {
        if controller.pdfLibrary.item(bookKey: ref.bookKey) != nil {
            libraryError = nil
            controller.openPageRef(ref)
        } else {
            libraryError = "No PDF bound to “\(ref.bookKey)”. Open Library, open your book, and use Book settings to set that key."
            controller.switchMode(.library)
            controller.backToShelf()
        }
    }
}
