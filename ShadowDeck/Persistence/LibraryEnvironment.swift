//
//  LibraryEnvironment.swift
//  ShadowDeck
//
//  App-facing holder for ModelContainer + CharacterLibrary.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
public final class LibraryEnvironment {
    public let container: ModelContainer
    public let library: CharacterLibrary
    public let runLibrary: RunLibrary
    public var lastErrorMessage: String?
    /// Sidebar badge — kept in sync via `refreshRunCount()`.
    public private(set) var runCount: Int = 0

    public init(container: ModelContainer, library: CharacterLibrary, runLibrary: RunLibrary) {
        self.container = container
        self.library = library
        self.runLibrary = runLibrary
        refreshRunCount()
    }

    public static func live() throws -> LibraryEnvironment {
        let container = try PersistenceController.makeContainer(inMemory: false)
        let library = try PersistenceController.makeLibrary(container: container)
        let runLibrary = PersistenceController.makeRunLibrary(container: container)
        return LibraryEnvironment(container: container, library: library, runLibrary: runLibrary)
    }

    /// Empty in-memory library (no disk, no seed data).
    public static func ephemeral() throws -> LibraryEnvironment {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Ephemeral-Avatars-\(UUID().uuidString)", isDirectory: true)
        let library = try PersistenceController.makeLibrary(container: container, avatarRoot: temp)
        let runLibrary = PersistenceController.makeRunLibrary(container: container)
        return LibraryEnvironment(container: container, library: library, runLibrary: runLibrary)
    }

    /// In-memory library with SR4/5/6 samples + one photogenic run.
    /// Used for README marquee captures so personal disk libraries never appear.
    public static func marketingCapture() throws -> LibraryEnvironment {
        let env = try ephemeral()
        for sample in SampleCharacters.makeAll() {
            try env.library.save(sample)
        }
        var run = Run.makeDraft(title: "Datasteal on Renraku Arcology")
        run.tags = ["Datasteal", "Seattle"]
        run.status = .active
        run.client = "Mr. Johnson (Ares cut-out)"
        run.location = "Downtown Seattle · Renraku Arcology"
        run.objectives = [
            RunObjective(text: "Extract paydata from host 77-A", isPrimary: true, status: .pending),
            RunObjective(text: "No civilian casualties", isPrimary: false, status: .pending),
        ]
        run.opposition = "High-threat Matrix IC; two corp security mage teams on rotation."
        run.complicationsNotes = "Johnson may double-cross once the data leaves the building."
        run.expectedPayout = RunPayout(nuyen: 18_000, karma: 6)
        run.heatDelta = 2
        run.participantCharacterIDs = [SampleCharacters.sr5ID, SampleCharacters.sr4ID]
        run.sessionLog = [
            RunLogEntry(kind: .session, text: "Session 1 — matrix recon complete."),
            RunLogEntry(kind: .complication, text: "Spider noticed the probe; clock is ticking."),
        ]
        run.gmNotes = "Keep decker spotlight; Face softens the Johnson if things go south."
        run.applyStatus(.active)
        try env.runLibrary.save(run)
        env.refreshRunCount()
        return env
    }

    public static func preview(seedSamples: Bool = true) -> LibraryEnvironment {
        do {
            let env = try ephemeral()
            if seedSamples {
                for sample in SampleCharacters.makeAll() {
                    try env.library.save(sample)
                }
            }
            return env
        } catch {
            fatalError("Preview library failed: \(error)")
        }
    }

    public func refreshCount() -> Int {
        (try? library.count()) ?? 0
    }

    public func refreshRunCount() {
        runCount = (try? runLibrary.count()) ?? 0
    }
}
