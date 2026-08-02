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
        return "On-device AI is unavailable on this Mac. Experimental text heuristics will draft the run — review carefully."
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

        var draft = heuristicDraft(from: text, fallbackTitle: source.pdfTitle, pageRange: source.pageRange)
        draft.sourcePDFID = source.pdfID
        draft.sourcePDFTitle = source.pdfTitle
        draft.sourcePageRange = source.pageRange
        draft.warnings = warnings + draft.warnings
        draft.usedOnDeviceAI = false
        return draft
    }

    // MARK: - Heuristic fallback

    /// Offline draft from extracted PDF text (no on-device model).
    /// Uses SRM-aware section parsing — see `RunDraftHeuristic`.
    public static func heuristicDraft(
        from text: String,
        fallbackTitle: String,
        pageRange: ClosedRange<Int>? = nil
    ) -> RunDraft {
        // `pageRange` is recorded by callers on `RunDraft.sourcePageRange`; the heuristic
        // only needs the extracted text (kept for call-site compatibility).
        _ = pageRange
        return RunDraftHeuristic.draft(from: text, fallbackTitle: fallbackTitle)
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
        // Keep model prompt within a tight context window; extraction already
        // used the AI budget when AI is available.
        let clipped = String(text.prefix(12_000))
        let prompt = """
        You are helping a Shadowrun gamemaster draft a run tracker entry from mission PDF text.

        Rules:
        - Extract only what the text supports.
        - playerFacingSummary and knownRisks must be player-safe (no deep spoilers).
        - oppositionSummary is GM-facing (brief).
        - gmNotes: a concise 1–3 paragraph GM background / mission synopsis only. \
        Do NOT paste full scene text, NPC stat blocks, attribute rows (B A R S W…), \
        gear lists, or markdown headers. No field labels inside values.
        - objectives: short action lines, not full paragraphs.
        - expectedStreetCred / expectedNotoriety / expectedPublicAwareness: typical awards \
        from “Picking Up the Pieces” when stated (often +1); use reputationNotes for conditions.
        - expectedPayoutNuyen / expectedKarma from rewards when stated.
        - Be concise. Empty string if unknown.

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
            expectedStreetCred: g.expectedStreetCred,
            expectedNotoriety: g.expectedNotoriety,
            expectedPublicAwareness: g.expectedPublicAwareness,
            reputationNotes: g.reputationNotes,
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
    var expectedStreetCred: Int?
    var expectedNotoriety: Int?
    var expectedPublicAwareness: Int?
    var reputationNotes: String
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
