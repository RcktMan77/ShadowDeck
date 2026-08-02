//
//  PersistenceController.swift
//  ShadowDeck
//
//  SwiftData container configuration + migration notes.
//
//  Migration strategy (sketch):
//  1. Character.schemaVersion + payload JSON evolve independently of SwiftData columns.
//  2. Additive SwiftData fields get defaults; avoid renames without a versioned migration plan.
//  3. Breaking payload changes: decode with VersionedPayload migrators before save.
//  4. Always keep .shadowdeck export working so users can rebuild the library.
//  5. Phase 2 stores schemaVersion on the record for future lightweight migration hooks.
//

import Foundation
import SwiftData

@MainActor
public enum PersistenceController {
    public static let schema = Schema([
        CharacterRecord.self,
        RunRecord.self,
        CampaignRecord.self
    ])

    public static func makeContainer(
        inMemory: Bool = false,
        appGroupSupportDirectory: URL? = nil
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makeLibrary(
        container: ModelContainer,
        avatarRoot: URL? = nil
    ) throws -> CharacterLibrary {
        let store: AvatarStore
        if let avatarRoot {
            try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
            store = AvatarStore(rootDirectory: avatarRoot)
        } else {
            store = try AvatarStore.applicationSupportStore()
        }
        return CharacterLibrary(
            modelContext: container.mainContext,
            avatarStore: store
        )
    }

    public static func makeRunLibrary(container: ModelContainer) -> RunLibrary {
        RunLibrary(modelContext: container.mainContext)
    }

    public static func makeCampaignLibrary(container: ModelContainer) -> CampaignLibrary {
        CampaignLibrary(modelContext: container.mainContext)
    }
}
