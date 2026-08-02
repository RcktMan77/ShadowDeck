//
//  RunAwardApplicator.swift
//  ShadowDeck
//
//  Pure preview + apply for distributing run nuyen/karma (and optional reputation)
//  to linked characters. UI owns library I/O; this type never loads or saves.
//

import Foundation

// MARK: - Preview / result models

public struct AwardShare: Sendable, Hashable, Identifiable {
    public var characterID: UUID
    public var name: String
    public var nuyen: Int
    public var karma: Int
    /// Street Cred delta for this runner (Phase 2D). Default 0.
    public var streetCredDelta: Int
    /// Notoriety delta for this runner (Phase 2D). Default 0.
    public var notorietyDelta: Int
    /// Public Awareness delta for this runner (Phase 2D). Default 0.
    public var publicAwarenessDelta: Int

    public var id: UUID { characterID }

    public init(
        characterID: UUID,
        name: String,
        nuyen: Int,
        karma: Int,
        streetCredDelta: Int = 0,
        notorietyDelta: Int = 0,
        publicAwarenessDelta: Int = 0
    ) {
        self.characterID = characterID
        self.name = name
        self.nuyen = nuyen
        self.karma = karma
        self.streetCredDelta = streetCredDelta
        self.notorietyDelta = notorietyDelta
        self.publicAwarenessDelta = publicAwarenessDelta
    }

    public var hasReputationDelta: Bool {
        streetCredDelta != 0 || notorietyDelta != 0 || publicAwarenessDelta != 0
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
    /// Heat note written to the session log, if any.
    public var heatNote: String?

    public init(
        applied: [AwardShare],
        skipped: [SkippedParticipant],
        appliedAt: Date,
        heatNote: String? = nil
    ) {
        self.applied = applied
        self.skipped = skipped
        self.appliedAt = appliedAt
        self.heatNote = heatNote
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
    case shareSetMismatch

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
        case .shareSetMismatch:
            return "Award shares do not match the run’s available participants."
        }
    }
}

// MARK: - Engine

public enum RunAwardApplicator {
    /// Equal floor split of preferred payout among **available** characters.
    /// Remainder nuyen/karma goes to the first available participant (run list order).
    /// Reputation deltas default to 0 — the UI may edit them before `apply`.
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
    /// - Parameters:
    ///   - characters: Inout array of full characters to mutate. Must include every
    ///     available participant from `run.participantCharacterIDs` (order ignored; matched by id).
    ///   - shares: Optional custom shares (e.g. edited reputation). When nil, equal-split
    ///     preview is used. When provided, must cover exactly the available participant set.
    ///   - heatNote: Optional session heat narrative → `RunLogEntryKind.heat` (and awards log).
    public static func apply(
        run: inout Run,
        characters: inout [Character],
        shares: [AwardShare]? = nil,
        note: String? = nil,
        heatNote: String? = nil,
        at date: Date = Date(),
        appendSessionLog: Bool = true
    ) throws -> ApplyResult {
        try validateForApply(run: run)

        var byID = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        let preview = preview(run: run, charactersByID: byID)

        let resolvedShares: [AwardShare]
        if let shares {
            resolvedShares = try validateCustomShares(shares, against: preview.perCharacter)
        } else {
            resolvedShares = preview.perCharacter
        }

        guard !resolvedShares.isEmpty else {
            throw RunAwardApplicatorError.noAvailableParticipants
        }

        // Ensure every share target is present in the inout array.
        let shareIDs = Set(resolvedShares.map(\.characterID))
        let providedIDs = Set(characters.map(\.id))
        guard shareIDs.isSubset(of: providedIDs) else {
            throw RunAwardApplicatorError.characterSetMismatch
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteForStorage = (trimmedNote?.isEmpty == false) ? trimmedNote : nil

        let trimmedHeat = heatNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let heatForStorage = (trimmedHeat?.isEmpty == false) ? trimmedHeat : nil

        for share in resolvedShares {
            guard var character = byID[share.characterID] else {
                throw RunAwardApplicatorError.characterSetMismatch
            }
            character.nuyen += share.nuyen
            character.karmaAvailable += share.karma
            character.karmaTotal += share.karma
            character.applyReputationDeltas(
                streetCred: share.streetCredDelta,
                notoriety: share.notorietyDelta,
                publicAwareness: share.publicAwarenessDelta
            )

            let summary = ledgerSummary(
                runTitle: run.title,
                nuyen: share.nuyen,
                karma: share.karma,
                streetCred: share.streetCredDelta,
                notoriety: share.notorietyDelta,
                publicAwareness: share.publicAwarenessDelta
            )
            character.appendAdvancementLedger(
                AdvancementLedgerEntry(
                    date: date,
                    kind: .runAward,
                    summary: summary,
                    karmaSpent: -share.karma, // negative = gained
                    nuyenDelta: share.nuyen,
                    relatedRunID: run.id,
                    streetCredDelta: share.streetCredDelta,
                    notorietyDelta: share.notorietyDelta,
                    publicAwarenessDelta: share.publicAwarenessDelta
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
            var logText = "Awards applied — \(totalLine) split among \(resolvedShares.count) runner(s)."
            if resolvedShares.contains(where: \.hasReputationDelta) {
                logText += " Reputation adjusted."
            }
            if let noteForStorage {
                logText += " Note: \(noteForStorage)"
            }
            run.sessionLog.append(
                RunLogEntry(createdAt: date, kind: .note, text: logText)
            )

            if let heatForStorage {
                run.sessionLog.append(
                    RunLogEntry(createdAt: date, kind: .heat, text: heatForStorage)
                )
            }
        }

        run.touch()

        return ApplyResult(
            applied: resolvedShares,
            skipped: preview.skipped,
            appliedAt: date,
            heatNote: heatForStorage
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

    /// Custom shares must cover the same character IDs as the equal-split preview (order free).
    /// Nuyen/karma may match preview or be overridden; reputation is free-form.
    private static func validateCustomShares(
        _ shares: [AwardShare],
        against expected: [AwardShare]
    ) throws -> [AwardShare] {
        let expectedIDs = Set(expected.map(\.characterID))
        let shareIDs = Set(shares.map(\.characterID))
        guard shareIDs == expectedIDs, shares.count == expected.count else {
            throw RunAwardApplicatorError.shareSetMismatch
        }
        // Preserve run-list order from expected, merge in edited fields by ID.
        let byID = Dictionary(uniqueKeysWithValues: shares.map { ($0.characterID, $0) })
        return expected.map { base in
            guard let edited = byID[base.characterID] else { return base }
            return AwardShare(
                characterID: base.characterID,
                name: edited.name.isEmpty ? base.name : edited.name,
                nuyen: edited.nuyen,
                karma: edited.karma,
                streetCredDelta: edited.streetCredDelta,
                notorietyDelta: edited.notorietyDelta,
                publicAwarenessDelta: edited.publicAwarenessDelta
            )
        }
    }

    private static func ledgerSummary(
        runTitle: String,
        nuyen: Int,
        karma: Int,
        streetCred: Int,
        notoriety: Int,
        publicAwareness: Int
    ) -> String {
        let title = runTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = title.isEmpty ? "Run" : title
        var parts = [formatTotals(nuyen: nuyen, karma: karma)]
        if streetCred != 0 {
            parts.append(formatSigned(streetCred, suffix: " SC"))
        }
        if notoriety != 0 {
            parts.append(formatSigned(notoriety, suffix: " Not"))
        }
        if publicAwareness != 0 {
            parts.append(formatSigned(publicAwareness, suffix: " PA"))
        }
        return "\(label) — \(parts.joined(separator: ", "))"
    }

    private static func formatTotals(nuyen: Int, karma: Int) -> String {
        let nuyenPart = "¥\(nuyen.formatted())"
        let karmaPart = "\(karma) karma"
        return "\(nuyenPart) + \(karmaPart)"
    }

    private static func formatSigned(_ value: Int, suffix: String) -> String {
        value >= 0 ? "+\(value)\(suffix)" : "\(value)\(suffix)"
    }
}
