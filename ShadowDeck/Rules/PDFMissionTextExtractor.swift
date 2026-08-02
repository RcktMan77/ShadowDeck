//
//  PDFMissionTextExtractor.swift
//  ShadowDeck
//
//  Bounded PDFKit text extraction for Phase 2F mission drafts.
//  Never loads an entire long book by default — requires a page range.
//  Budgets tighten when feeding on-device AI; relax for heuristic drafting.
//

import Foundation
import PDFKit

public enum PDFMissionTextExtractor {
    /// Character / page budgets for extraction.
    public struct Limits: Sendable, Hashable {
        public var defaultMaxPages: Int
        public var hardMaxPages: Int
        public var maxCharacters: Int

        public init(defaultMaxPages: Int, hardMaxPages: Int, maxCharacters: Int) {
            self.defaultMaxPages = max(1, defaultMaxPages)
            self.hardMaxPages = max(self.defaultMaxPages, hardMaxPages)
            self.maxCharacters = max(4_000, maxCharacters)
        }

        /// Tight budget so on-device models stay within a focused context window.
        public static let onDeviceAI = Self(
            defaultMaxPages: 8,
            hardMaxPages: 20,
            maxCharacters: 24_000
        )

        /// Relaxed budget when drafting from text heuristics (no model context cap).
        public static let heuristic = Self(
            defaultMaxPages: 24,
            hardMaxPages: 60,
            maxCharacters: 200_000
        )

        /// Pick budget based on whether on-device AI will consume the extract.
        public static func current(aiAvailable: Bool = RunDraftGenerator.isOnDeviceAIAvailable) -> Self {
            aiAvailable ? .onDeviceAI : .heuristic
        }
    }

    /// Back-compat aliases (AI-era defaults). Prefer `Limits`.
    public static var defaultMaxPages: Int { Limits.current().defaultMaxPages }
    public static var hardMaxPages: Int { Limits.current().hardMaxPages }
    public static var maxCharacters: Int { Limits.current().maxCharacters }

    public struct ExtractResult: Sendable, Hashable {
        public var text: String
        public var pageCount: Int
        public var extractedPages: ClosedRange<Int>
        public var warnings: [String]
        public var limits: Limits

        public init(
            text: String,
            pageCount: Int,
            extractedPages: ClosedRange<Int>,
            warnings: [String],
            limits: Limits = .onDeviceAI
        ) {
            self.text = text
            self.pageCount = pageCount
            self.extractedPages = extractedPages
            self.warnings = warnings
            self.limits = limits
        }
    }

    /// 1-based inclusive page range. Clamped to document bounds and `limits.hardMaxPages`.
    public static func extract(
        url: URL,
        pageRange: ClosedRange<Int>? = nil,
        maxPages: Int? = nil,
        limits: Limits = .current()
    ) throws -> ExtractResult {
        guard let document = PDFDocument(url: url) else {
            throw ExtractError.couldNotOpen
        }
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw ExtractError.emptyDocument
        }

        var warnings: [String] = []
        let requestedCap = maxPages ?? limits.defaultMaxPages
        let cap = min(max(1, requestedCap), limits.hardMaxPages)
        let requested = pageRange ?? 1...min(cap, pageCount)
        let lower = max(1, min(requested.lowerBound, pageCount))
        var upper = max(lower, min(requested.upperBound, pageCount))
        if upper - lower + 1 > cap {
            upper = lower + cap - 1
            warnings.append("Page range capped to \(cap) pages for drafting.")
        }

        var chunks: [String] = []
        var totalChars = 0
        var lastIncludedPage = lower
        for pageIndex in (lower - 1)..<upper {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageNumber = pageIndex + 1
            let raw = pageText(page)
            let cleaned = normalizePageText(raw)
            if cleaned.isEmpty {
                warnings.append("Page \(pageNumber) had no extractable text (may be image-only).")
                continue
            }
            let labeled = "--- Page \(pageNumber) ---\n\(cleaned)"
            if totalChars + labeled.count > limits.maxCharacters {
                warnings.append(
                    "Stopped early at character budget (\(limits.maxCharacters.formatted()) characters)."
                )
                break
            }
            chunks.append(labeled)
            totalChars += labeled.count
            lastIncludedPage = pageNumber
        }

        let text = chunks.joined(separator: "\n\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("No text extracted. Scanned PDFs may need OCR outside ShadowDeck.")
        }

        return ExtractResult(
            text: text,
            pageCount: pageCount,
            extractedPages: lower...max(lower, lastIncludedPage),
            warnings: warnings,
            limits: limits
        )
    }

    // MARK: - Page text quality

    /// Prefer plain `string`; fall back to attributed string when empty.
    private static func pageText(_ page: PDFPage) -> String {
        if let s = page.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        if let attr = page.attributedString?.string,
           !attr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return attr
        }
        return page.string ?? ""
    }

    /// Normalize PDF line-breaking so heuristics see readable paragraphs.
    public static func normalizePageText(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "\u{0c}", with: "\n") // form feed
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ") // nbsp

        // Rejoin hyphenated line wraps: "corpo-\nration" → "corporation"
        s = s.replacingOccurrences(
            of: #"(\p{L})-\n(\p{L})"#,
            with: "$1$2",
            options: .regularExpression
        )

        // Trim leading/trailing pad from two-column PDF layout so UI is left-justified.
        let lines = s.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        var paragraphs: [String] = []
        var current: [String] = []

        func flush() {
            guard !current.isEmpty else { return }
            let joined = current.joined(separator: " ")
                .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                paragraphs.append(joined)
            }
            current = []
        }

        for line in lines {
            if line.isEmpty {
                flush()
                continue
            }
            // Skip lone page numbers / running footers.
            if line.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil {
                continue
            }
            if looksLikeParagraphBreak(beforeAppending: line, current: current) {
                flush()
            }
            current.append(line)
        }
        flush()

        return paragraphs.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Start a new paragraph when the next line looks like a heading or list item.
    private static func looksLikeParagraphBreak(beforeAppending line: String, current: [String]) -> Bool {
        guard !current.isEmpty else { return false }
        if line.hasPrefix("•") || line.hasPrefix("- ") || line.hasPrefix("* ") { return true }
        if line.range(of: #"^\d+[\.\)]\s+\S"#, options: .regularExpression) != nil { return true }
        // ALL-CAPS short headings common in mission PDFs
        if line.count <= 48,
           line == line.uppercased(),
           line.rangeOfCharacter(from: .letters) != nil,
           !line.contains(".") {
            return true
        }
        // Labeled fields
        if line.range(
            of: #"^(Client|Location|Setting|Johnson|Objectives?|Synopsis|Briefing|Hook|Rewards?|Payout|Karma|Opposition|Threats?|Risks?)\s*:"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        return false
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
