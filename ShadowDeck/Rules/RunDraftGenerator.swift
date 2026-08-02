//
//  RunDraftGenerator.swift
//  ShadowDeck
//
//  Phase 2F: turn extracted mission PDF text into an editable `RunDraft`.
//  Prefer on-device Foundation Models when available; always have a heuristic fallback.
//

import Foundation

public enum RunDraftGenerator {
    public struct Source: Sendable, Hashable {
        public var pdfID: UUID?
        public var pdfTitle: String
        public var pageRange: ClosedRange<Int>?
        public var extractedText: String

        public init(
            pdfID: UUID? = nil,
            pdfTitle: String,
            pageRange: ClosedRange<Int>? = nil,
            extractedText: String
        ) {
            self.pdfID = pdfID
            self.pdfTitle = pdfTitle
            self.pageRange = pageRange
            self.extractedText = extractedText
        }
    }

    /// Whether Apple on-device Foundation Models can be used for structured drafting.
    public static var isOnDeviceAIAvailable: Bool {
        if #available(macOS 26.0, *) {
            return FoundationModelsRunDraftBridge.isAvailable
        }
        return false
    }

    public static var availabilityMessage: String {
        if isOnDeviceAIAvailable {
            return "On-device Apple Intelligence is available for structured drafting."
        }
        return "On-device AI is unavailable on this Mac. ShadowDeck will draft from PDF text heuristics — review carefully."
    }

    /// Build a draft. Uses Foundation Models when available; otherwise heuristics.
    public static func generate(from source: Source) async -> RunDraft {
        var warnings: [String] = []
        let text = source.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            warnings.append("No text to analyze.")
            return RunDraft(
                title: source.pdfTitle,
                sourcePDFID: source.pdfID,
                sourcePDFTitle: source.pdfTitle,
                sourcePageRange: source.pageRange,
                warnings: warnings,
                usedOnDeviceAI: false
            )
        }

        if #available(macOS 26.0, *), FoundationModelsRunDraftBridge.isAvailable {
            do {
                var draft = try await FoundationModelsRunDraftBridge.generate(text: text, source: source)
                draft.usedOnDeviceAI = true
                draft.sourcePDFID = source.pdfID
                draft.sourcePDFTitle = source.pdfTitle
                draft.sourcePageRange = source.pageRange
                draft.warnings = warnings + draft.warnings
                if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft.title = source.pdfTitle
                }
                return draft
            } catch {
                warnings.append("On-device AI draft failed (\(error.localizedDescription)). Used text heuristics instead.")
            }
        } else {
            warnings.append(availabilityMessage)
        }

        var draft = heuristicDraft(from: text, fallbackTitle: source.pdfTitle)
        draft.sourcePDFID = source.pdfID
        draft.sourcePDFTitle = source.pdfTitle
        draft.sourcePageRange = source.pageRange
        draft.warnings = warnings + draft.warnings
        draft.usedOnDeviceAI = false
        return draft
    }

    // MARK: - Heuristic fallback

    public static func heuristicDraft(from text: String, fallbackTitle: String) -> RunDraft {
        var warnings: [String] = []
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("--- Page") }

        var title = fallbackTitle
        if let missionLine = lines.first(where: {
            $0.range(of: #"^SRM\s*\d"#, options: .regularExpression) != nil
                || $0.localizedCaseInsensitiveContains("mission")
        }) {
            title = missionLine
        } else if let first = lines.first, first.count < 80 {
            title = first
        }

        var missionCode: String?
        if let match = text.range(of: #"SRM\s*[\dA-Za-z\-–]+"#, options: .regularExpression) {
            missionCode = String(text[match])
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }

        var client = ""
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("mr. johnson") || lower.contains("ms. johnson") || lower.hasPrefix("johnson") {
                client = line
                break
            }
            if lower.hasPrefix("client:") {
                client = line.replacingOccurrences(of: "Client:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }

        var location = ""
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("location:") || lower.hasPrefix("setting:") {
                location = line
                    .replacingOccurrences(of: "Location:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Setting:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                break
            }
            if lower.contains("seattle") || lower.contains("metroplex") || lower.contains("district") {
                location = line
                break
            }
        }

        var objectives: [String] = []
        for line in lines {
            if line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*") {
                let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-* "))
                if cleaned.count > 8, cleaned.count < 160 {
                    objectives.append(cleaned)
                }
            }
            if objectives.count >= 6 { break }
        }
        if objectives.isEmpty {
            warnings.append("No bullet objectives found — add them manually.")
        }

        // Player-facing: first non-header paragraphs, lightly.
        let summaryCandidates = lines.filter {
            $0.count > 40 && $0.count < 400
                && !$0.lowercased().hasPrefix("page")
                && !$0.contains("copyright")
        }
        let playerFacing = summaryCandidates.prefix(2).joined(separator: " ")

        var nuyen: Int?
        if let m = text.range(of: #"¥\s*[\d,]+|[\d,]+\s*nuyen"#, options: [.regularExpression, .caseInsensitive]) {
            let raw = String(text[m]).filter(\.isNumber)
            if let v = Int(raw), v > 0 { nuyen = v }
        }
        var karma: Int?
        if let m = text.range(of: #"\b(\d+)\s*karma\b"#, options: [.regularExpression, .caseInsensitive]) {
            let digits = String(text[m]).filter(\.isNumber)
            if let v = Int(digits), v > 0, v < 50 { karma = v }
        }

        return RunDraft(
            title: title,
            missionCode: missionCode,
            client: client,
            location: location,
            objectives: Array(objectives.prefix(6)),
            oppositionSummary: "",
            expectedPayoutNuyen: nuyen,
            expectedKarma: karma,
            playerFacingSummary: String(playerFacing.prefix(800)),
            knownRisks: "",
            gmNotes: "",
            warnings: warnings,
            usedOnDeviceAI: false
        )
    }
}

// MARK: - Foundation Models bridge (macOS 26+)

/// Isolated so callers on older OS versions never touch FoundationModels types.
enum FoundationModelsRunDraftBridge {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return FoundationModelsRunDraftBridgeImpl.isAvailable
        }
        return false
    }

    @available(macOS 26.0, *)
    static func generate(text: String, source: RunDraftGenerator.Source) async throws -> RunDraft {
        try await FoundationModelsRunDraftBridgeImpl.generate(text: text, source: source)
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
private enum FoundationModelsRunDraftBridgeImpl {
    static var isAvailable: Bool {
        // Apple Intelligence + system language model must be ready.
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    static func generate(text: String, source: RunDraftGenerator.Source) async throws -> RunDraft {
        let model = SystemLanguageModel.default
        let session = LanguageModelSession(model: model)
        let clipped = String(text.prefix(12_000))
        let prompt = """
        You are helping a Shadowrun gamemaster draft a run tracker entry from mission PDF text.
        Extract only what the text supports. Prefer player-safe summaries for playerFacingSummary and knownRisks.
        Put spoiler-heavy opposition in oppositionSummary (GM-facing).
        Return concise fields. If unknown, use empty string or omit numbers.

        PDF title: \(source.pdfTitle)

        Text:
        \(clipped)
        """

        let response = try await session.respond(
            to: prompt,
            generating: GeneratedMissionDraft.self
        )
        let g = response.content
        var warnings: [String] = []
        if g.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("AI left title empty — using PDF name.")
        }
        return RunDraft(
            title: g.title.isEmpty ? source.pdfTitle : g.title,
            missionCode: g.missionCode.nilIfEmpty,
            client: g.client,
            location: g.location,
            objectives: g.objectives.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            oppositionSummary: g.oppositionSummary,
            expectedPayoutNuyen: g.expectedPayoutNuyen,
            expectedKarma: g.expectedKarma,
            playerFacingSummary: g.playerFacingSummary,
            knownRisks: g.knownRisks,
            gmNotes: g.gmNotes,
            warnings: warnings,
            usedOnDeviceAI: true
        )
    }
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedMissionDraft {
    var title: String
    var missionCode: String
    var client: String
    var location: String
    var objectives: [String]
    var oppositionSummary: String
    var expectedPayoutNuyen: Int?
    var expectedKarma: Int?
    var playerFacingSummary: String
    var knownRisks: String
    var gmNotes: String
}

#else

@available(macOS 26.0, *)
private enum FoundationModelsRunDraftBridgeImpl {
    static var isAvailable: Bool { false }

    static func generate(text: String, source: RunDraftGenerator.Source) async throws -> RunDraft {
        throw NSError(
            domain: "ShadowDeck.RunDraft",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "FoundationModels framework not linked."]
        )
    }
}

#endif

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
