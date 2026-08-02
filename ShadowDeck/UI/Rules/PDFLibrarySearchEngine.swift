//
//  PDFLibrarySearchEngine.swift
//  ShadowDeck
//
//  Pure PDFKit ranking for shelf-wide text search (no UI / no store).
//

import Foundation
import PDFKit

/// Ranked page hit from a single document search.
struct PDFLibraryRankedPageHit: Sendable, Equatable {
    var page: Int
    var snippet: String
    var score: Int
    var matchedTokens: Int
    var tokenCount: Int
}

/// Phrase-first, then multi-token intersection via PDFKit `findString`.
/// Multi-word queries prefer pages containing **all** tokens; partials rank lower.
enum PDFLibrarySearchEngine {
    /// Max books searched in parallel (each holds a full `PDFDocument` in memory).
    static let maxConcurrentBooks = 2

    /// Ranked page hits for one document (up to 20).
    static func rankDocument(_ doc: PDFDocument, query: String) -> [PDFLibraryRankedPageHit] {
        let options: NSString.CompareOptions = [.caseInsensitive]
        let tokens = tokenizeQuery(query)
        let tokenCount = max(1, tokens.count)

        // 1) Contiguous phrase — highest relevance.
        let phraseSels = doc.findString(query, withOptions: options)
        if !phraseSels.isEmpty {
            var hits: [PDFLibraryRankedPageHit] = []
            var seen = Set<Int>()
            for sel in phraseSels {
                guard let page = sel.pages.first else { continue }
                let pageIndex = doc.index(for: page) + 1
                if seen.contains(pageIndex) { continue }
                seen.insert(pageIndex)
                hits.append(PDFLibraryRankedPageHit(
                    page: pageIndex,
                    snippet: snippet(from: sel, fallback: query, page: page, tokens: tokens),
                    score: 10_000 + tokenCount * 100,
                    matchedTokens: tokenCount,
                    tokenCount: tokenCount
                ))
                if hits.count >= 20 { break }
            }
            return hits
        }

        guard !tokens.isEmpty else { return [] }

        // 2) Per-token page sets from PDFKit (reliable even when page.string is sparse).
        var pagesByToken: [String: Set<Int>] = [:]
        for token in tokens {
            var pages = Set<Int>()
            for sel in doc.findString(token, withOptions: options) {
                guard let page = sel.pages.first else { continue }
                pages.insert(doc.index(for: page) + 1)
            }
            pagesByToken[token] = pages
        }

        var candidatePages = Set<Int>()
        for pages in pagesByToken.values {
            candidatePages.formUnion(pages)
        }

        let minTokensForPartial: Int = {
            if tokens.count <= 1 { return 1 }
            if tokens.count == 2 { return 2 }
            return max(2, tokens.count - 1)
        }()

        var ranked: [PDFLibraryRankedPageHit] = []
        for pageIndex in candidatePages {
            let matched = tokens.filter { pagesByToken[$0]?.contains(pageIndex) == true }
            let matchedCount = matched.count
            guard matchedCount >= minTokensForPartial else { continue }

            let page = doc.page(at: pageIndex - 1)
            let pageText = page?.string ?? ""
            let snip = multiTokenSnippet(pageText: pageText, tokens: matched, pageIndex: pageIndex)

            var score = matchedCount * 1_000
            if matchedCount == tokenCount {
                score += 5_000
            }
            if matchedCount >= 2, tokenProximityBonus(pageText: pageText, tokens: matched) {
                score += 800
            }
            score += matchedCount * matchedCount * 50

            ranked.append(PDFLibraryRankedPageHit(
                page: pageIndex,
                snippet: snip,
                score: score,
                matchedTokens: matchedCount,
                tokenCount: tokenCount
            ))
        }

        ranked.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.matchedTokens != $1.matchedTokens { return $0.matchedTokens > $1.matchedTokens }
            return $0.page < $1.page
        }
        let full = ranked.filter { $0.matchedTokens == tokenCount }
        if full.count >= 3 {
            return Array(full.prefix(20))
        }
        return Array(ranked.prefix(20))
    }

    // MARK: - Token helpers

    static func tokenizeQuery(_ query: String) -> [String] {
        query
            .lowercased()
            .split { $0.isWhitespace || ",.;:·/\\()[]{}".contains($0) }
            .map(String.init)
            .filter { $0.count >= 3 }
            .filter { !["the", "and", "for", "with", "from", "that", "this", "your"].contains($0) }
    }

    private static func snippet(
        from sel: PDFSelection,
        fallback: String,
        page: PDFPage,
        tokens: [String]
    ) -> String {
        let raw = (sel.string ?? fallback)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.count >= 12 {
            return raw.count > 140 ? String(raw.prefix(137)) + "…" : raw
        }
        return multiTokenSnippet(pageText: page.string ?? "", tokens: tokens, pageIndex: 0)
    }

    private static func multiTokenSnippet(
        pageText: String,
        tokens: [String],
        pageIndex: Int
    ) -> String {
        let collapsed = pageText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let lower = collapsed.lowercased()
        var bestRange: Range<String.Index>?
        for token in tokens {
            if let r = lower.range(of: token) {
                if bestRange == nil || r.lowerBound < bestRange!.lowerBound {
                    bestRange = r
                }
            }
        }
        guard let range = bestRange else {
            let joined = tokens.joined(separator: " · ")
            return pageIndex > 0 ? "p. \(pageIndex): \(joined)" : joined
        }
        let start = collapsed.index(range.lowerBound, offsetBy: -40, limitedBy: collapsed.startIndex)
            ?? collapsed.startIndex
        let end = collapsed.index(range.upperBound, offsetBy: 80, limitedBy: collapsed.endIndex)
            ?? collapsed.endIndex
        var slice = String(collapsed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start != collapsed.startIndex { slice = "…" + slice }
        if end != collapsed.endIndex { slice += "…" }
        return slice.isEmpty ? "Match on page \(pageIndex)" : slice
    }

    private static func tokenProximityBonus(pageText: String, tokens: [String]) -> Bool {
        let lower = pageText.lowercased()
        var positions: [Int] = []
        for token in tokens {
            if let r = lower.range(of: token) {
                positions.append(lower.distance(from: lower.startIndex, to: r.lowerBound))
            }
        }
        guard positions.count >= 2 else { return false }
        positions.sort()
        for i in 0..<(positions.count - 1) {
            if positions[i + 1] - positions[i] <= 80 { return true }
        }
        return false
    }
}
