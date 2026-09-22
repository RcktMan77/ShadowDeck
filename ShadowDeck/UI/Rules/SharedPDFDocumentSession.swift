import AppKit
import PDFKit
import SwiftUI

// MARK: - Shared document (one PDFDocument for reader + thumbnails)

/// Loads a book once and shares the same `PDFDocument` instance with the continuous
/// reader and the thumbnail strip (avoids 2× decode / peak memory on large CRBs).
@MainActor
final class SharedPDFDocumentSession: ObservableObject {
    let url: URL
    @Published private(set) var document: PDFDocument?
    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?
    private var loadTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
        let target = url
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            let box = PDFDocumentBox()
            autoreleasepool {
                box.document = PDFDocument(url: target)
            }
            guard !Task.isCancelled else { return }
            let opened = box.document
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, self.url == target else { return }
                self.isLoading = false
                if let opened {
                    self.document = opened
                    self.loadError = nil
                } else {
                    self.document = nil
                    self.loadError = "Could not open this PDF."
                }
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }
}

/// Carries a `PDFDocument` from a background open onto the main actor.
private final class PDFDocumentBox: @unchecked Sendable {
    var document: PDFDocument?
}
