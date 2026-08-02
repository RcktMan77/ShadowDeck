//
//  RulesReferenceStore.swift
//  ShadowDeck
//
//  Loads bundled RulesSeed.json and provides search / category filtering.
//

import Foundation

public struct RulesReferenceSearchResult: Sendable, Hashable, Identifiable {
    public var entry: RuleEntry
    public var score: Int

    public var id: String { entry.id }

    public init(entry: RuleEntry, score: Int) {
        self.entry = entry
        self.score = score
    }
}

public enum RulesReferenceStoreError: Error, Equatable, LocalizedError {
    case seedNotFound
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .seedNotFound:
            return "Rules seed file was not found in app resources."
        case .decodeFailed(let detail):
            return "Failed to decode rules seed: \(detail)"
        }
    }
}

public final class RulesReferenceStore: @unchecked Sendable {
    public private(set) var entries: [RuleEntry]
    public private(set) var schemaVersion: Int
    public private(set) var loadErrors: [String]

    public init(entries: [RuleEntry] = [], schemaVersion: Int = 1, loadErrors: [String] = []) {
        // Always sort page chips by edition era for stable UI.
        self.entries = entries.map { entry in
            var e = entry
            e.pageRefs = PageRef.sortedForDisplay(entry.pageRefs)
            return e
        }
        self.schemaVersion = schemaVersion
        self.loadErrors = loadErrors
    }

    /// Load bundled seed (or source-tree fallback for tests).
    public static func loadBundled() -> RulesReferenceStore {
        do {
            let file = try loadSeedFile()
            return RulesReferenceStore(entries: file.entries, schemaVersion: file.schemaVersion)
        } catch {
            return RulesReferenceStore(
                entries: [],
                schemaVersion: 0,
                loadErrors: [error.localizedDescription]
            )
        }
    }

    public static func loadSeedFile() throws -> RulesSeedFile {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "RulesSeed", withExtension: "json", subdirectory: "Rules"),
            Bundle.main.url(forResource: "RulesSeed", withExtension: "json"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Rules/
                .deletingLastPathComponent() // ShadowDeck/
                .appendingPathComponent("Resources/Rules/RulesSeed.json")
        ]
        guard let url = candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw RulesReferenceStoreError.seedNotFound
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(RulesSeedFile.self, from: data)
        } catch let error as RulesReferenceStoreError {
            throw error
        } catch {
            throw RulesReferenceStoreError.decodeFailed(error.localizedDescription)
        }
    }

    // MARK: - Query

    public func entry(id: String) -> RuleEntry? {
        entries.first { $0.id == id }
    }

    public func entries(
        category: RuleCategory? = nil,
        edition: Edition? = nil
    ) -> [RuleEntry] {
        entries.filter { entry in
            if let category, entry.category != category { return false }
            return entry.applies(to: edition)
        }
    }

    /// Ranked search over title, tags, summary, formula, and category display name.
    public func search(
        query: String,
        category: RuleCategory? = nil,
        edition: Edition? = nil,
        limit: Int = 50
    ) -> [RulesReferenceSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = entries(category: category, edition: edition)
        guard !trimmed.isEmpty else {
            return base
                .prefix(limit)
                .map { RulesReferenceSearchResult(entry: $0, score: 0) }
        }

        let tokens = trimmed
            .lowercased()
            .split { $0.isWhitespace || $0 == "," }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return base.prefix(limit).map { RulesReferenceSearchResult(entry: $0, score: 0) }
        }

        var scored: [RulesReferenceSearchResult] = []
        for entry in base {
            let score = relevanceScore(entry: entry, tokens: tokens)
            if score > 0 {
                scored.append(RulesReferenceSearchResult(entry: entry, score: score))
            }
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.entry.title.localizedCaseInsensitiveCompare($1.entry.title) == .orderedAscending
        }
        if scored.count > limit {
            return Array(scored.prefix(limit))
        }
        return scored
    }

    // MARK: - Scoring

    private func relevanceScore(entry: RuleEntry, tokens: [String]) -> Int {
        let title = entry.title.lowercased()
        let tags = entry.tags.map { $0.lowercased() }
        let summary = entry.summary.lowercased()
        let formula = (entry.formula ?? "").lowercased()
        let category = entry.category.displayName.lowercased()
        let id = entry.id.lowercased()

        var score = 0
        for token in tokens {
            var tokenHit = false
            if title == token {
                score += 100
                tokenHit = true
            } else if title.hasPrefix(token) {
                score += 60
                tokenHit = true
            } else if title.contains(token) {
                score += 40
                tokenHit = true
            }
            if tags.contains(where: { $0 == token }) {
                score += 50
                tokenHit = true
            } else if tags.contains(where: { $0.contains(token) }) {
                score += 30
                tokenHit = true
            }
            if id.contains(token) {
                score += 25
                tokenHit = true
            }
            if category.contains(token) {
                score += 15
                tokenHit = true
            }
            if formula.contains(token) {
                score += 20
                tokenHit = true
            }
            if summary.contains(token) {
                score += 10
                tokenHit = true
            }
            if !tokenHit {
                // Require every token to match somewhere — drop weak partials.
                return 0
            }
        }
        return score
    }
}
