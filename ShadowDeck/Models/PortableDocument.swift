//
//  PortableDocument.swift
//  ShadowDeck
//
//  Single-file portable character format presented to users as one object.
//
//  On disk (Phase 2+): a directory package with extension `.shadowdeck`:
//    manifest.json  — format version, edition, ids
//    character.json — full Character payload (this schema)
//    avatar/        — optional portrait bytes
//
//  Wire format for character.json is JSON (human-debuggable, Codable-native).
//  The package is Mac-native (like .rtfd): one object in Finder, efficient files inside.
//

import Foundation

public enum ShadowDeckFormat {
    /// User-visible file extension for a single character package.
    public static let fileExtension = "shadowdeck"
    public static let utTypeIdentifier = "com.shadowdeck.character"
    public static let currentFormatVersion = 1
    public static let characterJSONFileName = "character.json"
    public static let manifestFileName = "manifest.json"
    public static let avatarDirectoryName = "avatar"
}

/// Top-level portable document — what import/export round-trips.
public struct PortableCharacterDocument: Codable, Sendable, Hashable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var character: Character

    public init(
        formatVersion: Int = ShadowDeckFormat.currentFormatVersion,
        exportedAt: Date = Date(),
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
        character: Character
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.character = character
    }
}

public struct PortableManifest: Codable, Sendable, Hashable {
    public var formatVersion: Int
    public var characterID: UUID
    public var characterName: String
    public var edition: Edition
    public var schemaVersion: Int
    public var hasAvatar: Bool

    public init(from character: Character, formatVersion: Int = ShadowDeckFormat.currentFormatVersion) {
        self.formatVersion = formatVersion
        self.characterID = character.id
        self.characterName = character.displayTitle
        self.edition = character.edition
        self.schemaVersion = character.schemaVersion
        self.hasAvatar = character.avatar.hasImage
    }
}

/// Encode/decode helpers for the JSON payload inside a `.shadowdeck` package.
public enum PortableCharacterCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ document: PortableCharacterDocument) throws -> Data {
        try encoder().encode(document)
    }

    public static func decode(from data: Data) throws -> PortableCharacterDocument {
        try decoder().decode(PortableCharacterDocument.self, from: data)
    }

    public static func encodeCharacter(_ character: Character) throws -> Data {
        try encode(PortableCharacterDocument(character: character))
    }
}
