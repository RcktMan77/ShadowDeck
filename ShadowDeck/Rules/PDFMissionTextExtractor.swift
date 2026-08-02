//
//  PDFMissionTextExtractor.swift
//  ShadowDeck
//
//  Bounded PDFKit text extraction for Phase 2F mission drafts.
//  Never loads an entire long book by default — requires a page range.
//

import Foundation
import PDFKit

public enum PDFMissionTextExtractor {
    public static let defaultMaxPages = 8
    public static let hardMaxPages = 20
    public static let maxCharacters = 24_000

    public struct ExtractResult: Sendable, Hashable {
        public var text: String
        public var pageCount: Int
        public var extractedPages: ClosedRange<Int>
        public var warnings: [String]

        public init(text: String, pageCount: Int, extractedPages: ClosedRange<Int>, warnings: [String]) {
            self.text = text
            self.pageCount = pageCount
            self.extractedPages = extractedPages
            self.warnings = warnings
        }
    }

    /// 1-based inclusive page range. Clamped to document bounds and `hardMaxPages`.
    public static func extract(
        url: URL,
        pageRange: ClosedRange<Int>? = nil,
        maxPages: Int = defaultMaxPages
    ) throws -> ExtractResult {
        guard let document = PDFDocument(url: url) else {
            throw ExtractError.couldNotOpen
        }
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw ExtractError.emptyDocument
        }

        var warnings: [String] = []
        let cap = min(max(1, maxPages), hardMaxPages)
        let requested = pageRange ?? 1...min(cap, pageCount)
        let lower = max(1, min(requested.lowerBound, pageCount))
        var upper = max(lower, min(requested.upperBound, pageCount))
        if upper - lower + 1 > cap {
            upper = lower + cap - 1
            warnings.append("Page range capped to \(cap) pages for a focused draft.")
        }

        var chunks: [String] = []
        var totalChars = 0
        for pageIndex in (lower - 1)..<upper {
            guard let page = document.page(at: pageIndex) else { continue }
            let raw = page.string ?? ""
            let trimmed = raw
                .replacingOccurrences(of: "\u{0c}", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                warnings.append("Page \(pageIndex + 1) had no extractable text (may be image-only).")
                continue
            }
            let labeled = "--- Page \(pageIndex + 1) ---\n\(trimmed)"
            if totalChars + labeled.count > maxCharacters {
                warnings.append("Stopped early at character budget (\(maxCharacters)).")
                break
            }
            chunks.append(labeled)
            totalChars += labeled.count
        }

        let text = chunks.joined(separator: "\n\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("No text extracted. Scanned PDFs may need OCR outside ShadowDeck.")
        }

        return ExtractResult(
            text: text,
            pageCount: pageCount,
            extractedPages: lower...upper,
            warnings: warnings
        )
    }

    public enum ExtractError: Error, LocalizedError {
        case couldNotOpen
        case emptyDocument

        public var errorDescription: String? {
            switch self {
            case .couldNotOpen: "Could not open the PDF."
            case .emptyDocument: "This PDF has no pages."
            }
        }
    }
}

private extension ClosedRange where Bound == Int {
    func clamped(to limits: ClosedRange<Int>) -> ClosedRange<Int> {
        let lo = Swift.max(lowerBound, limits.lowerBound)
        let hi = Swift.min(upperBound, limits.upperBound)
        return lo...Swift.max(lo, hi)
    }
}
