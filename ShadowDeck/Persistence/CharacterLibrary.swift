//
//  CharacterLibrary.swift
//  ShadowDeck
//
//  App-managed character library: CRUD, hybrid avatars, package import/export.
//

import Foundation
import SwiftData

public enum CharacterLibraryError: Error, LocalizedError, Equatable {
    case notFound(UUID)
    case decodingFailed(String)
    case encodingFailed(String)
    case avatarFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Character \(id.uuidString) was not found in the library."
        case .decodingFailed(let detail):
            return "Could not decode character: \(detail)"
        case .encodingFailed(let detail):
            return "Could not encode character: \(detail)"
        case .avatarFailed(let detail):
            return "Avatar storage failed: \(detail)"
        }
    }
}

@MainActor
public final class CharacterLibrary {
    private let modelContext: ModelContext
    private let avatarStore: any AvatarStoreProtocol

    public init(modelContext: ModelContext, avatarStore: any AvatarStoreProtocol) {
        self.modelContext = modelContext
        self.avatarStore = avatarStore
    }

    // MARK: - List / fetch

    public func listSummaries() throws -> [CharacterSummary] {
        // Sort in-process to avoid Swift 6 Sendable warnings on SortDescriptor KeyPaths.
        let records = try modelContext.fetch(FetchDescriptor<CharacterRecord>())
            .sorted { $0.modifiedAt > $1.modifiedAt }
        var didBackfill = false
        let summaries: [CharacterSummary] = records.map { record in
            // Backfill short library taglines for rows saved before ConceptTagline existed
            // (empty denormalized concept but full story in the payload).
            if record.concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let character = try? CharacterMapper.decodePayload(record.payload)
            {
                let label = ConceptTagline.libraryLabel(
                    concept: character.concept,
                    background: character.background,
                    awakened: character.awakened
                )
                if !label.isEmpty {
                    record.concept = label
                    didBackfill = true
                }
            }

            var summary = record.summary
            // Thumbnail generation must never take down the library list.
            // Prefer avatar store (file/inline), then raw inline snapshot bytes.
            let full: Data? = {
                if let loaded = try? avatarStore.load(characterID: record.id, record: record.avatarSnapshot),
                   !loaded.isEmpty
                {
                    return loaded
                }
                if let inline = record.avatarSnapshot.inlineData, !inline.isEmpty {
                    return inline
                }
                return nil
            }()
            if let full {
                if let thumb = AvatarThumbnail.make(from: full) {
                    summary.thumbnailData = thumb
                } else {
                    // Fallback: use original bytes if thumbnail encode fails.
                    summary.thumbnailData = full.count < 256_000 ? full : nil
                }
                summary.hasAvatar = summary.thumbnailData != nil
            }
            return summary
        }
        if didBackfill {
            try? modelContext.save()
        }
        return summaries
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<CharacterRecord>())
    }

    public func fetch(id: UUID) throws -> Character? {
        guard let record = try fetchRecord(id: id) else { return nil }
        return try character(from: record)
    }

    public func require(_ id: UUID) throws -> Character {
        guard let character = try fetch(id: id) else {
            throw CharacterLibraryError.notFound(id)
        }
        return character
    }

    // MARK: - Save / delete

    /// Upserts a character. Pass `avatarData` to replace portrait bytes; omit to keep existing avatar
    /// unless `character.avatar.inlineData` is set (used as the new portrait).
    public func save(_ character: Character, avatarData: Data? = nil) throws {
        var working = character
        working.touch()

        let incomingAvatar = avatarData ?? working.avatar.inlineData
        let record = try fetchRecord(id: working.id) ?? CharacterRecord(
            id: working.id,
            name: working.name,
            streetName: working.streetName,
            concept: working.concept,
            editionRaw: working.edition.rawValue,
            metatypeRaw: working.metatype.rawValue,
            schemaVersion: working.schemaVersion,
            createdAt: working.createdAt,
            modifiedAt: working.modifiedAt,
            payload: Data()
        )

        let isNew = record.modelContext == nil
        if isNew {
            modelContext.insert(record)
        }

        if let incomingAvatar {
            do {
                let resolved = try avatarStore.store(
                    characterID: working.id,
                    data: incomingAvatar,
                    mimeType: working.avatar.mimeType,
                    isAnimated: working.avatar.isAnimated
                )
                applyResolvedAvatar(resolved, to: record)
                working.avatar.fileName = resolved.fileName
                working.avatar.mimeType = resolved.mimeType
                working.avatar.isAnimated = resolved.isAnimated
                // Domain model may retain bytes for immediate UI; payload will strip them.
                working.avatar.inlineData = resolved.kind == .inline ? resolved.data : incomingAvatar
            } catch {
                throw CharacterLibraryError.avatarFailed(error.localizedDescription)
            }
        } else if record.avatarKind == .none {
            // Ensure clean avatar state.
            record.avatarKind = .none
            record.avatarFileName = nil
            record.avatarMimeType = nil
            record.avatarIsAnimated = false
            record.avatarInlineData = nil
            record.avatarByteCount = 0
        }

        CharacterMapper.updateRecordMetadata(record, from: working)

        do {
            record.payload = try CharacterMapper.encodePayload(working)
        } catch {
            throw CharacterLibraryError.encodingFailed(error.localizedDescription)
        }

        try modelContext.save()
    }

    public func delete(id: UUID) throws {
        guard let record = try fetchRecord(id: id) else {
            throw CharacterLibraryError.notFound(id)
        }
        try avatarStore.delete(characterID: id)
        modelContext.delete(record)
        try modelContext.save()
    }

    public func deleteAll() throws {
        let descriptor = FetchDescriptor<CharacterRecord>()
        let records = try modelContext.fetch(descriptor)
        for record in records {
            try avatarStore.delete(characterID: record.id)
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    // MARK: - Package I/O

    public func exportPackage(id: UUID, to url: URL) throws {
        let character = try require(id)
        let record = try fetchRecord(id: id)
        let avatarData = try record.flatMap {
            try avatarStore.load(characterID: id, record: $0.avatarSnapshot)
        }
        try ShadowDeckPackage.export(character: character, avatarData: avatarData, to: url)
    }

    public func exportPackage(_ character: Character, to url: URL) throws {
        let avatarData = character.avatar.inlineData
            ?? (try? avatarStore.load(
                characterID: character.id,
                record: AvatarRecordSnapshot(
                    kind: character.avatar.inlineData != nil ? .inline : (character.avatar.fileName != nil ? .file : .none),
                    fileName: character.avatar.fileName,
                    mimeType: character.avatar.mimeType,
                    isAnimated: character.avatar.isAnimated,
                    inlineData: character.avatar.inlineData,
                    byteCount: character.avatar.inlineData?.count ?? 0
                )
            ))
        try ShadowDeckPackage.export(character: character, avatarData: avatarData, to: url)
    }

    @discardableResult
    public func importPackage(from url: URL) throws -> Character {
        let character = try ShadowDeckPackage.importPackage(from: url)
        try save(character, avatarData: character.avatar.inlineData)
        return try require(character.id)
    }

    // MARK: - Internals

    private func fetchRecord(id: UUID) throws -> CharacterRecord? {
        // Filter in-process to avoid Swift 6 Sendable warnings on #Predicate KeyPaths.
        try modelContext.fetch(FetchDescriptor<CharacterRecord>()).first { $0.id == id }
    }

    private func character(from record: CharacterRecord) throws -> Character {
        let decoded: Character
        do {
            decoded = try CharacterMapper.decodePayload(record.payload)
        } catch {
            throw CharacterLibraryError.decodingFailed(error.localizedDescription)
        }
        var character = decoded
        character.id = record.id
        let data = try avatarStore.load(characterID: record.id, record: record.avatarSnapshot)
        CharacterMapper.applyAvatar(to: &character, snapshot: record.avatarSnapshot, loadedData: data)
        return character
    }

    private func applyResolvedAvatar(_ resolved: ResolvedAvatar, to record: CharacterRecord) {
        record.avatarKind = resolved.kind
        record.avatarFileName = resolved.fileName
        record.avatarMimeType = resolved.mimeType
        record.avatarIsAnimated = resolved.isAnimated
        record.avatarByteCount = resolved.byteCount
        switch resolved.kind {
        case .inline:
            record.avatarInlineData = resolved.data
        case .file, .none:
            record.avatarInlineData = nil
        }
    }
}
