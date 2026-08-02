//
//  RunDraft.swift
//  ShadowDeck
//
//  Editable draft for Phase 2F “mission PDF → planned run” flow.
//  Not persisted until the GM confirms Create.
//

import Foundation

/// Intermediate editable mission draft before becoming a planning `Run`.
public struct RunDraft: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var missionCode: String?
    public var client: String
    public var location: String
    public var objectives: [String]
    public var oppositionSummary: String
    public var expectedPayoutNuyen: Int?
    public var expectedKarma: Int?
    /// Typical Street Cred award from the mission (often conditional).
    public var expectedStreetCred: Int?
    public var expectedNotoriety: Int?
    public var expectedPublicAwareness: Int?
    /// Free-text mission reputation conditions (e.g. “+1 SC if …”).
    public var reputationNotes: String
    public var playerFacingSummary: String
    public var knownRisks: String
    public var gmNotes: String
    public var sourcePDFID: UUID?
    public var sourcePDFTitle: String?
    public var sourcePageRange: ClosedRange<Int>?
    public var warnings: [String]
    public var usedOnDeviceAI: Bool

    public init(
        id: UUID = UUID(),
        title: String = "",
        missionCode: String? = nil,
        client: String = "",
        location: String = "",
        objectives: [String] = [],
        oppositionSummary: String = "",
        expectedPayoutNuyen: Int? = nil,
        expectedKarma: Int? = nil,
        expectedStreetCred: Int? = nil,
        expectedNotoriety: Int? = nil,
        expectedPublicAwareness: Int? = nil,
        reputationNotes: String = "",
        playerFacingSummary: String = "",
        knownRisks: String = "",
        gmNotes: String = "",
        sourcePDFID: UUID? = nil,
        sourcePDFTitle: String? = nil,
        sourcePageRange: ClosedRange<Int>? = nil,
        warnings: [String] = [],
        usedOnDeviceAI: Bool = false
    ) {
        self.id = id
        self.title = title
        self.missionCode = missionCode
        self.client = client
        self.location = location
        self.objectives = objectives
        self.oppositionSummary = oppositionSummary
        self.expectedPayoutNuyen = expectedPayoutNuyen
        self.expectedKarma = expectedKarma
        self.expectedStreetCred = expectedStreetCred
        self.expectedNotoriety = expectedNotoriety
        self.expectedPublicAwareness = expectedPublicAwareness
        self.reputationNotes = reputationNotes
        self.playerFacingSummary = playerFacingSummary
        self.knownRisks = knownRisks
        self.gmNotes = gmNotes
        self.sourcePDFID = sourcePDFID
        self.sourcePDFTitle = sourcePDFTitle
        self.sourcePageRange = sourcePageRange
        self.warnings = warnings
        self.usedOnDeviceAI = usedOnDeviceAI
    }

    /// Build a planning `Run` from this draft (does not save).
    public func makeRun(edition: Edition = .sr5, campaignID: UUID? = nil) -> Run {
        var run = Run.makeDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Job"
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            edition: edition,
            campaignID: campaignID
        )
        run.client = client
        run.location = location
        run.playerFacingSummary = playerFacingSummary
        run.knownRisks = knownRisks
        run.opposition = oppositionSummary
        if !gmNotes.isEmpty {
            run.gmNotes = gmNotes
        }
        if let n = expectedPayoutNuyen, let k = expectedKarma {
            run.expectedPayout = RunPayout(nuyen: max(0, n), karma: max(0, k))
        } else if let n = expectedPayoutNuyen {
            run.expectedPayout = RunPayout(nuyen: max(0, n), karma: 0)
        } else if let k = expectedKarma {
            run.expectedPayout = RunPayout(nuyen: 0, karma: max(0, k))
        }
        run.objectives = objectives
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in
                RunObjective(text: text, isPrimary: index == 0, status: .pending)
            }
        if let code = missionCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            if !run.tags.contains(where: { $0.caseInsensitiveCompare(code) == .orderedSame }) {
                run.tags.insert(code, at: 0)
            }
        }
        if let pdfTitle = sourcePDFTitle, !pdfTitle.isEmpty {
            let note = "Drafted from PDF: \(pdfTitle)"
                + (sourcePageRange.map { " (pp. \($0.lowerBound)–\($0.upperBound))" } ?? "")
            if run.gmNotes.isEmpty {
                run.gmNotes = note
            } else {
                run.gmNotes = note + "\n\n" + run.gmNotes
            }
        }
        // Mission reputation expectations (Apply Awards still sets per-runner deltas at wrap-up).
        var repLines: [String] = []
        if let sc = expectedStreetCred, sc != 0 { repLines.append("Street Cred \(sc > 0 ? "+\(sc)" : "\(sc)")") }
        if let n = expectedNotoriety, n != 0 { repLines.append("Notoriety \(n > 0 ? "+\(n)" : "\(n)")") }
        if let pa = expectedPublicAwareness, pa != 0 {
            repLines.append("Public Awareness \(pa > 0 ? "+\(pa)" : "\(pa)")")
        }
        let repNotes = reputationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !repLines.isEmpty || !repNotes.isEmpty {
            var block = "Mission reputation (from draft):"
            if !repLines.isEmpty {
                block += " " + repLines.joined(separator: ", ")
            }
            if !repNotes.isEmpty {
                block += "\n" + repNotes
            }
            if run.gmNotes.isEmpty {
                run.gmNotes = block
            } else {
                run.gmNotes += "\n\n" + block
            }
        }
        return run
    }
}
