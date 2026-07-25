//
//  CharacterMapper.swift
//  ShadowDeck
//
//  Maps between domain Character and SwiftData CharacterRecord payloads.
//

import Foundation

public enum CharacterMapper {
    public static func encodePayload(_ character: Character) throws -> Data {
        var copy = character
        // Payload never embeds large binary; avatar bytes live on the record / disk.
        copy.avatar.inlineData = nil
        return try PortableCharacterCoding.encoder().encode(copy)
    }

    public static func decodePayload(_ data: Data) throws -> Character {
        try PortableCharacterCoding.decoder().decode(Character.self, from: data)
    }

    /// Apply hybrid avatar resolution onto a domain character loaded from a record.
    public static func applyAvatar(
        to character: inout Character,
        snapshot: AvatarRecordSnapshot,
        loadedData: Data?
    ) {
        character.avatar.fileName = snapshot.fileName
        character.avatar.mimeType = snapshot.mimeType
        character.avatar.isAnimated = snapshot.isAnimated
        switch snapshot.kind {
        case .none:
            character.avatar.inlineData = nil
        case .inline, .file:
            // Present bytes on the domain model for UI/export convenience.
            character.avatar.inlineData = loadedData
        }
    }

    public static func updateRecordMetadata(_ record: CharacterRecord, from character: Character) {
        record.id = character.id
        record.name = character.name
        record.streetName = character.streetName
        record.concept = character.concept
        record.editionRaw = character.edition.rawValue
        record.metatypeRaw = character.metatype.rawValue
        record.schemaVersion = character.schemaVersion
        record.createdAt = character.createdAt
        record.modifiedAt = character.modifiedAt
    }
}
