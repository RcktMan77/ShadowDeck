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

    /// In-memory library with SR4/5/6 samples (no runs — the mission GIF creates one).
    /// Used for README marquee captures so personal disk libraries never appear.
    public static func marketingCapture() throws -> LibraryEnvironment {
        let env = try ephemeral()
        try env.seedSampleCharactersWithPortraits()
        env.refreshRunCount()
        return env
    }

    public static func preview(seedSamples: Bool = true) -> LibraryEnvironment {
        do {
            let env = try ephemeral()
            if seedSamples {
                try env.seedSampleCharactersWithPortraits()
            }
            return env
        } catch {
            fatalError("Preview library failed: \(error)")
        }
    }

    /// Saves sample runners with bundled role/metatype art as avatars (gallery + list thumbs).
    public func seedSampleCharactersWithPortraits() throws {
        for sample in SampleCharacters.makeAll() {
            var character = sample
            let archetype = SampleCharacters.portraitArchetype(for: character.id)
            if let data = ChargenArtLoader.preferredPortraitData(
                archetype: archetype,
                metatype: character.metatype
            ) {
                character.avatar.inlineData = data
                character.avatar.mimeType = "image/jpeg"
                character.avatar.isAnimated = false
                try library.save(character, avatarData: data)
            } else {
                try library.save(character)
            }
        }
    }

    public func refreshCount() -> Int {
        (try? library.count()) ?? 0
    }

    public func refreshRunCount() {
        runCount = (try? runLibrary.count()) ?? 0
    }
}
