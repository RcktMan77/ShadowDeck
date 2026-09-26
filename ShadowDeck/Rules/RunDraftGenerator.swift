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
                if shouldAcceptAIDraft(draft) {
                    draft.usedOnDeviceAI = true
                    if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        draft.title = source.pdfTitle
                        draft.warnings.append("AI left title empty — using PDF name.")
                    }
                    draft.sourcePDFID = source.pdfID
                    draft.sourcePDFTitle = source.pdfTitle
                    draft.sourcePageRange = source.pageRange
                    draft.warnings = warnings + draft.warnings
                    return draft
                }
                warnings.append("Heuristic draft (Apple Intelligence unavailable or the model failed).")
            } catch {
                warnings.append("Heuristic draft (Apple Intelligence unavailable or the model failed).")
            }
        } else {
            warnings.append("Heuristic draft (Apple Intelligence unavailable or the model failed).")
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

    /// A model draft is usable when it names the mission and extracts something real.
    /// Empty fluff must not block the heuristic.
    public static func shouldAcceptAIDraft(_ draft: RunDraft) -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = draft.missionCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasIdentity = !title.isEmpty || !code.isEmpty
        let hasObjectives = draft.objectives.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasAwards = draft.expectedPayoutNuyen != nil
            || draft.expectedKarma != nil
            || draft.expectedStreetCred != nil
            || draft.expectedNotoriety != nil
            || draft.expectedPublicAwareness != nil
        let hasClient = !draft.client.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let fluff = !hasObjectives && !hasAwards && !hasClient
        return hasIdentity && !fluff
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
        let instructions = Instructions(
            """
            Extract a Shadowrun mission into the provided fields.
            Use only facts the text supports. Leave a field empty when it does not.
            Player-facing summary and known risks stay spoiler-light.
            Do not copy Behind the Scenes into player-facing fields.
            Opposition and GM notes are for the gamemaster.
            For nuyen and karma, use one number only when the text states one, \
            and prefer the listed base or typical payout rather than an optional maximum.
            Leave Street Cred, Notoriety, and Public Awareness empty unless a number is stated. \
            Put conditions in reputation notes, not invented integers.
            """
        )
        let session = LanguageModelSession(model: model, instructions: instructions)
        let prepared = try await packedForModel(
            text: text,
            pdfTitle: source.pdfTitle,
            model: model,
            instructions: instructions
        )
        let prompt = userPrompt(pdfTitle: source.pdfTitle, sections: prepared.packed.text)

        #if swift(>=6.4)
        let response = try await session.respond(
            to: prompt,
            generating: GeneratedMissionDraft.self,
            options: GenerationOptions(
                samplingMode: .greedy,
                maximumResponseTokens: prepared.outputReserve
            )
        )
        #else
        let response = try await session.respond(
            to: prompt,
            generating: GeneratedMissionDraft.self
        )
        #endif
        let g = response.content
        var warnings: [String] = []
        warnings.append(contentsOf: prepared.packed.warnings)
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

    private struct PreparedModelInput {
        var packed: RunDraftModelInput.Packed
        var outputReserve: Int
    }

    /// Fit mission sections into the model's context after reserves.
    /// `tokenCount` and the real context size shipped in the macOS 26.4 SDK.
    /// Xcode 26.3 CI compiles the character estimate instead.
    private static func packedForModel(
        text: String,
        pdfTitle: String,
        model: SystemLanguageModel,
        instructions: Instructions
    ) async throws -> PreparedModelInput {
        let context = contextTokenLimit(model)
        let instructionTokens = try await instructionTokenCount(instructions, model: model, context: context)
        let schemaTokens = try await schemaTokenCount(model: model, context: context)
        let outputReserve = max(600, context / 5)
        // Output is capped at outputReserve, so this margin is only tokenizer slop.
        let margin = max(64, context / 20)
        let sourceBudget = max(256, context - instructionTokens - schemaTokens - outputReserve - margin)

        var characterBudget = sourceBudget * 4
        var packed = RunDraftModelInput.pack(text: text, maxCharacters: characterBudget)
        for _ in 0..<6 {
            let prompt = userPrompt(pdfTitle: pdfTitle, sections: packed.text)
            let tokens = try await promptTokenCount(prompt, model: model)
            if tokens <= sourceBudget {
                return PreparedModelInput(packed: packed, outputReserve: outputReserve)
            }
            characterBudget = max(400, characterBudget / 2)
            packed = RunDraftModelInput.pack(text: text, maxCharacters: characterBudget)
        }
        return PreparedModelInput(packed: packed, outputReserve: outputReserve)
    }

    private static func userPrompt(pdfTitle: String, sections: String) -> String {
        """
        PDF title: \(pdfTitle)

        Mission sections:
        \(sections)
        """
    }

    private static func contextTokenLimit(_ model: SystemLanguageModel) -> Int {
        #if swift(>=6.4)
        return model.contextSize
        #else
        _ = model
        return 4096
        #endif
    }

    private static func instructionTokenCount(
        _ instructions: Instructions,
        model: SystemLanguageModel,
        context: Int
    ) async throws -> Int {
        #if swift(>=6.4)
        if #available(macOS 26.4, *) {
            return try await model.tokenCount(for: instructions)
        }
        #endif
        _ = instructions
        _ = model
        return max(200, context / 10)
    }

    private static func schemaTokenCount(
        model: SystemLanguageModel,
        context: Int
    ) async throws -> Int {
        #if swift(>=6.4)
        if #available(macOS 26.4, *) {
            return try await model.tokenCount(for: GeneratedMissionDraft.generationSchema)
        }
        #endif
        _ = model
        return max(200, context / 10)
    }

    private static func promptTokenCount(
        _ prompt: String,
        model: SystemLanguageModel
    ) async throws -> Int {
        #if swift(>=6.4)
        if #available(macOS 26.4, *) {
            return try await model.tokenCount(for: Prompt(prompt))
        }
        #endif
        _ = model
        return max(1, prompt.count / 4)
    }
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedMissionDraft {
    @Guide(description: "Adventure title only, without the mission code.")
    var title: String
    @Guide(description: "Mission code such as SRM 5A-01, or empty.")
    var missionCode: String
    @Guide(description: "Who hires the runners, or empty.")
    var client: String
    @Guide(description: "City or meet location, or empty.")
    var location: String
    @Guide(description: "Short player objectives, one action each. No paragraphs.")
    var objectives: [String]
    @Guide(description: "Brief GM-facing opposition. No stat blocks.")
    var oppositionSummary: String
    @Guide(description: "One nuyen number only when the text states a base or typical total. Not an optional maximum. Omit if unstated.")
    var expectedPayoutNuyen: Int?
    @Guide(description: "One karma number only when the text states a base or typical award. Omit if unstated.")
    var expectedKarma: Int?
    @Guide(description: "Street Cred only when a single number is stated. Otherwise omit.")
    var expectedStreetCred: Int?
    @Guide(description: "Notoriety only when a single number is stated. Otherwise omit.")
    var expectedNotoriety: Int?
    @Guide(description: "Public Awareness only when a single number is stated. Otherwise omit.")
    var expectedPublicAwareness: Int?
    @Guide(description: "Reputation conditions in words, such as +1 Street Cred if the job is completed. No invented integers.")
    var reputationNotes: String
    @Guide(description: "Player-safe summary from Scan This and Tell It to Them Straight. No Behind the Scenes secrets.")
    var playerFacingSummary: String
    @Guide(description: "Player-safe risks. No deep spoilers.")
    var knownRisks: String
    @Guide(description: "Short GM synopsis. No stat blocks, gear lists, or scene dumps.")
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
