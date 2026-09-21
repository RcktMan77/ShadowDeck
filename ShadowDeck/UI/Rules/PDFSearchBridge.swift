import AppKit
import PDFKit
import SwiftUI

// MARK: - Search

@MainActor
final class PDFSearchBridge: ObservableObject {
    weak var pdfView: PDFView?

    @Published var query: String = ""
    @Published private(set) var matchCount: Int = 0
    @Published private(set) var activeIndex: Int = 0

    private var matches: [PDFSelection] = []

    /// Clear find UI. Skips @Published writes when already idle (avoids
    /// “Publishing changes from within view updates” storms on book open).
    func clear() {
        let needsPublish = !query.isEmpty || matchCount != 0 || activeIndex != 0 || !matches.isEmpty
        matches = []
        if !query.isEmpty { query = "" }
        if matchCount != 0 { matchCount = 0 }
        if activeIndex != 0 { activeIndex = 0 }
        pdfView?.highlightedSelections = nil
        pdfView?.currentSelection = nil
        _ = needsPublish
    }

    func find(query newQuery: String? = nil) {
        if let newQuery, newQuery != query { query = newQuery }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pdfView, let document = pdfView.document, !q.isEmpty else {
            matches = []
            if matchCount != 0 { matchCount = 0 }
            if activeIndex != 0 { activeIndex = 0 }
            pdfView?.highlightedSelections = nil
            return
        }
        matches = document.findString(q, withOptions: [.caseInsensitive])
        let count = matches.count
        if matchCount != count { matchCount = count }
        if let first = matches.first {
            if activeIndex != 1 { activeIndex = 1 }
            reveal(first, in: pdfView)
        } else {
            if activeIndex != 0 { activeIndex = 0 }
            pdfView.highlightedSelections = []
            pdfView.currentSelection = nil
        }
    }

    func findNext() {
        guard !matches.isEmpty, let pdfView else { return }
        activeIndex = activeIndex >= matches.count ? 1 : activeIndex + 1
        reveal(matches[activeIndex - 1], in: pdfView)
    }

    func findPrevious() {
        guard !matches.isEmpty, let pdfView else { return }
        activeIndex = activeIndex <= 1 ? matches.count : activeIndex - 1
        reveal(matches[activeIndex - 1], in: pdfView)
    }

    private func reveal(_ selection: PDFSelection, in pdfView: PDFView) {
        pdfView.highlightedSelections = matches
        pdfView.currentSelection = selection
        pdfView.go(to: selection)
        DispatchQueue.main.async {
            pdfView.scrollSelectionToVisible(nil)
        }
    }
}

