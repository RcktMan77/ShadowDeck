//
//  RunAwardApplicator.swift
//  ShadowDeck
//
//  Pure preview + apply for distributing run nuyen/karma to linked characters.
//  UI owns library I/O; this type never loads or saves.
//

import Foundation

// MARK: - Preview / result models

public struct AwardShare: Sendable, Hashable, Identifiable {
    public var characterID: UUID
    public var name: String
    public var nuyen: Int
    public var karma: Int

    public var id: UUID { characterID }

    public init(characterID: UUID, name: String, nuyen: Int, karma: Int) {
        self.characterID = characterID
        self.name = name
        self.nuyen = nuyen
        self.karma = karma
    }
}

public struct SkippedParticipant: Sendable, Hashable, Identifiable {
    public var characterID: UUID
    public var reason: String

    public var id: UUID { characterID }

    public init(characterID: UUID, reason: String) {
        self.characterID = characterID
        self.reason = reason
    }
}

public struct AwardPreview: Sendable, Hashable {
    /// `"actual"` or `"expected"` — matches payout source used for the split.
    public var sourceLabel: String
    public var totalNuyen: Int
    public var totalKarma: Int
    public var perCharacter: [AwardShare]
    public var skipped: [SkippedParticipant]
    /// False when already applied, no shares, zero totals, or other hard blocks.
    public var canApply: Bool
    /// Human-readable block reason when `canApply` is false (empty when applicable).
    public var blockReason: String

    public init(
        sourceLabel: String,
        totalNuyen: Int,
        totalKarma: Int,
        perCharacter: [AwardShare],
        skipped: [SkippedParticipant],
        canApply: Bool,
        blockReason: String = ""
    ) {
        self.sourceLabel = sourceLabel
        self.totalNuyen = totalNuyen
        self.totalKarma = totalKarma
        self.perCharacter = perCharacter
        self.skipped = skipped
        self.canApply = canApply
        self.blockReason = blockReason
    }
}

public struct ApplyResult: Sendable, Hashable {
    public var applied: [AwardShare]
    public var skipped: [SkippedParticipant]
    public var appliedAt: Date

    public init(applied: [AwardShare], skipped: [SkippedParticipant], appliedAt: Date) {
        self.applied = applied
        self.skipped = skipped
        self.appliedAt = appliedAt
    }
}

// MARK: - Errors

public enum RunAwardApplicatorError: Error, Equatable, LocalizedError {
    case alreadyApplied
    case runNotTerminal
    case noParticipants
    case noAwards
    case noAvailableParticipants
    case characterSetMismatch

    public var errorDescription: String? {
        switch self {
        case .alreadyApplied:
            return "Awards have already been applied for this run."
        case .runNotTerminal:
            return "Awards can only be applied when the run is Completed or Failed."
        case .noParticipants:
            return "Link at least one runner before applying awards."
        case .noAwards:
            return "Set a non-zero expected or actual payout before applying awards."
        case .noAvailableParticipants:
            return "None of the linked runners are in the character library."
        case .characterSetMismatch:
            return "Character set does not match the run’s available participants."
        }
    }
}

// MARK: - Engine

public enum RunAwardApplicator {

    /// Equal floor split of preferred payout among **available** characters.
    /// Remainder nuyen/karma goes to the first available participant (run list order).
    public static func preview(run: Run, charactersByID: [UUID: Character]) -> AwardPreview {
        let source = run.actualPayout ?? run.expectedPayout
        let sourceLabel = run.actualPayout != nil ? "actual" : "expected"
        let totalNuyen = max(0, source.nuyen)
        let totalKarma = max(0, source.karma)

        let (availableIDs, skipped) = resolveParticipants(run: run, charactersByID: charactersByID)
        let shares = splitAwards(
            totalNuyen: totalNuyen,
            totalKarma: totalKarma,
            orderedIDs: availableIDs,
            charactersByID: charactersByID
        )

        let (canApply, blockReason) = evaluateCanApply(
            run: run,
            totalNuyen: totalNuyen,
            totalKarma: totalKarma,
            shareCount: shares.count
        )

        return AwardPreview(
            sourceLabel: sourceLabel,
            totalNuyen: totalNuyen,
            totalKarma: totalKarma,
            perCharacter: shares,
            skipped: skipped,
            canApply: canApply,
            blockReason: blockReason
        )
    }

    /// Credits each available character and marks the run applied.
    /// - Parameter characters: Inout array of full characters to mutate. Must include every
    ///   available participant from `run.participantCharacterIDs` (order ignored; matched by id).
    ///   Missing IDs are skipped. Extra characters not on the run are left unchanged and ignored.
    public static func apply(
        run: inout Run,
        characters: inout [Character],
        note: String? = nil,
        at date: Date = Date(),
        appendSessionLog: Bool = true
    ) throws -> ApplyResult {
        try validateForApply(run: run)

        var byID = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        let preview = preview(run: run, charactersByID: byID)

        guard !preview.perCharacter.isEmpty else {
            throw RunAwardApplicatorError.noAvailableParticipants
        }

        // Ensure every share target is present in the inout array.
        let shareIDs = Set(preview.perCharacter.map(\.characterID))
        let providedIDs = Set(characters.map(\.id))
        guard shareIDs.isSubset(of: providedIDs) else {
            throw RunAwardApplicatorError.characterSetMismatch
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteForStorage = (trimmedNote?.isEmpty == false) ? trimmedNote : nil

        for share in preview.perCharacter {
            guard var character = byID[share.characterID] else {
                throw RunAwardApplicatorError.characterSetMismatch
            }
            character.nuyen += share.nuyen
            character.karmaAvailable += share.karma
            character.karmaTotal += share.karma

            let summary = ledgerSummary(
                runTitle: run.title,
                nuyen: share.nuyen,
                karma: share.karma
            )
            character.appendAdvancementLedger(
                AdvancementLedgerEntry(
                    date: date,
                    kind: .runAward,
                    summary: summary,
                    karmaSpent: -share.karma, // negative = gained
                    nuyenDelta: share.nuyen,
                    relatedRunID: run.id
                )
            )
            character.touch()
            byID[share.characterID] = character
        }

        // Write mutated characters back into the inout array (preserve caller's order).
        for index in characters.indices {
            if let updated = byID[characters[index].id], shareIDs.contains(updated.id) {
                characters[index] = updated
            }
        }

        run.awardsAppliedAt = date
        run.awardsAppliedNote = noteForStorage

        if appendSessionLog {
            let totalLine = formatTotals(nuyen: preview.totalNuyen, karma: preview.totalKarma)
            var logText = "Awards applied — \(totalLine) split among \(preview.perCharacter.count) runner(s)."
            if let noteForStorage {
                logText += " Note: \(noteForStorage)"
            }
            run.sessionLog.append(
                RunLogEntry(createdAt: date, kind: .note, text: logText)
            )
        }

        run.touch()

        return ApplyResult(
            applied: preview.perCharacter,
            skipped: preview.skipped,
            appliedAt: date
        )
    }

    // MARK: - Internals

    private static func validateForApply(run: Run) throws {
        if run.awardsAppliedAt != nil {
            throw RunAwardApplicatorError.alreadyApplied
        }
        guard run.status.isTerminal else {
            throw RunAwardApplicatorError.runNotTerminal
        }
        guard !run.participantCharacterIDs.isEmpty else {
            throw RunAwardApplicatorError.noParticipants
        }
        let source = run.actualPayout ?? run.expectedPayout
        guard !source.isZero else {
            throw RunAwardApplicatorError.noAwards
        }
    }

    private static func evaluateCanApply(
        run: Run,
        totalNuyen: Int,
        totalKarma: Int,
        shareCount: Int
    ) -> (Bool, String) {
        if run.awardsAppliedAt != nil {
            return (false, RunAwardApplicatorError.alreadyApplied.errorDescription ?? "")
        }
        if !run.status.isTerminal {
            return (false, RunAwardApplicatorError.runNotTerminal.errorDescription ?? "")
        }
        if run.participantCharacterIDs.isEmpty {
            return (false, RunAwardApplicatorError.noParticipants.errorDescription ?? "")
        }
        if totalNuyen == 0 && totalKarma == 0 {
            return (false, RunAwardApplicatorError.noAwards.errorDescription ?? "")
        }
        if shareCount == 0 {
            return (false, RunAwardApplicatorError.noAvailableParticipants.errorDescription ?? "")
        }
        return (true, "")
    }

    private static func resolveParticipants(
        run: Run,
        charactersByID: [UUID: Character]
    ) -> (available: [UUID], skipped: [SkippedParticipant]) {
        var available: [UUID] = []
        var skipped: [SkippedParticipant] = []
        for id in run.participantCharacterIDs {
            if charactersByID[id] != nil {
                available.append(id)
            } else {
                skipped.append(
                    SkippedParticipant(characterID: id, reason: "Missing from library")
                )
            }
        }
        return (available, skipped)
    }

    private static func splitAwards(
        totalNuyen: Int,
        totalKarma: Int,
        orderedIDs: [UUID],
        charactersByID: [UUID: Character]
    ) -> [AwardShare] {
        guard !orderedIDs.isEmpty else { return [] }
        let count = orderedIDs.count
        let baseNuyen = totalNuyen / count
        let baseKarma = totalKarma / count
        let remNuyen = totalNuyen % count
        let remKarma = totalKarma % count

        return orderedIDs.enumerated().map { index, id in
            let character = charactersByID[id]!
            return AwardShare(
                characterID: id,
                name: character.displayTitle,
                nuyen: baseNuyen + (index == 0 ? remNuyen : 0),
                karma: baseKarma + (index == 0 ? remKarma : 0)
            )
        }
    }

    private static func ledgerSummary(runTitle: String, nuyen: Int, karma: Int) -> String {
        let title = runTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = title.isEmpty ? "Run" : title
        return "\(label) — \(formatTotals(nuyen: nuyen, karma: karma))"
    }

    private static func formatTotals(nuyen: Int, karma: Int) -> String {
        let nuyenPart = "¥\(nuyen.formatted())"
        let karmaPart = "\(karma) karma"
        return "\(nuyenPart) + \(karmaPart)"
    }
}
