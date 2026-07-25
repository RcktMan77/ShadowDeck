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
    public var lastErrorMessage: String?

    public init(container: ModelContainer, library: CharacterLibrary) {
        self.container = container
        self.library = library
    }

    public static func live() throws -> LibraryEnvironment {
        let container = try PersistenceController.makeContainer(inMemory: false)
        let library = try PersistenceController.makeLibrary(container: container)
        return LibraryEnvironment(container: container, library: library)
    }

    /// Empty in-memory library (no disk, no seed data).
    public static func ephemeral() throws -> LibraryEnvironment {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Ephemeral-Avatars-\(UUID().uuidString)", isDirectory: true)
        let library = try PersistenceController.makeLibrary(container: container, avatarRoot: temp)
        return LibraryEnvironment(container: container, library: library)
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
}
