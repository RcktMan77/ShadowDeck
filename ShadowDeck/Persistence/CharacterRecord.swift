//
//  CharacterRecord.swift
//  ShadowDeck
//
//  SwiftData library row. Full domain Character is stored as a JSON payload for
//  schema flexibility; list fields are denormalized for fast browsing.
//  Avatar uses hybrid storage (inline blob vs file reference).
//

import Foundation
import SwiftData

@Model
public final class CharacterRecord {
    @Attribute(.unique) public var id: UUID

    // Denormalized list / search fields
    public var name: String
    public var streetName: String
    public var concept: String
    public var editionRaw: String
    public var metatypeRaw: String
    public var schemaVersion: Int
    public var createdAt: Date
    public var modifiedAt: Date

    /// Full `Character` JSON (avatar.inlineData cleared; avatar metadata only).
    @Attribute(.externalStorage) public var payload: Data

    // Hybrid avatar
    public var avatarStorageRaw: String
    public var avatarFileName: String?
    public var avatarMimeType: String?
    public var avatarIsAnimated: Bool
    /// Small portraits only; large/animated use files.
    @Attribute(.externalStorage) public var avatarInlineData: Data?
    public var avatarByteCount: Int

    public init(
        id: UUID,
        name: String,
        streetName: String,
        concept: String,
        editionRaw: String,
        metatypeRaw: String,
        schemaVersion: Int,
        createdAt: Date,
        modifiedAt: Date,
        payload: Data,
        avatarStorageRaw: String = AvatarStorageKind.none.rawValue,
        avatarFileName: String? = nil,
        avatarMimeType: String? = nil,
        avatarIsAnimated: Bool = false,
        avatarInlineData: Data? = nil,
        avatarByteCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.streetName = streetName
        self.concept = concept
        self.editionRaw = editionRaw
        self.metatypeRaw = metatypeRaw
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.payload = payload
        self.avatarStorageRaw = avatarStorageRaw
        self.avatarFileName = avatarFileName
        self.avatarMimeType = avatarMimeType
        self.avatarIsAnimated = avatarIsAnimated
        self.avatarInlineData = avatarInlineData
        self.avatarByteCount = avatarByteCount
    }

    public var avatarKind: AvatarStorageKind {
        get { AvatarStorageKind(rawValue: avatarStorageRaw) ?? .none }
        set { avatarStorageRaw = newValue.rawValue }
    }

    public var avatarSnapshot: AvatarRecordSnapshot {
        AvatarRecordSnapshot(
            kind: avatarKind,
            fileName: avatarFileName,
            mimeType: avatarMimeType,
            isAnimated: avatarIsAnimated,
            inlineData: avatarInlineData,
            byteCount: avatarByteCount
        )
    }

    public var summary: CharacterSummary {
        CharacterSummary(
            id: id,
            name: name,
            streetName: streetName,
            concept: concept,
            editionRaw: editionRaw,
            metatypeRaw: metatypeRaw,
            modifiedAt: modifiedAt,
            hasAvatar: avatarKind != .none && avatarByteCount > 0,
            thumbnailData: nil
        )
    }
}

/// Lightweight row for library lists (no full payload decode).
public struct CharacterSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var streetName: String
    public var concept: String
    public var editionRaw: String
    public var metatypeRaw: String
    public var modifiedAt: Date
    public var hasAvatar: Bool
    /// Small JPEG (or original) for list-row portraits; not used for equality of identity.
    public var thumbnailData: Data?

    public init(
        id: UUID,
        name: String,
        streetName: String,
        concept: String,
        editionRaw: String,
        metatypeRaw: String,
        modifiedAt: Date,
        hasAvatar: Bool,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.streetName = streetName
        self.concept = concept
        self.editionRaw = editionRaw
        self.metatypeRaw = metatypeRaw
        self.modifiedAt = modifiedAt
        self.hasAvatar = hasAvatar
        self.thumbnailData = thumbnailData
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.streetName == rhs.streetName
            && lhs.concept == rhs.concept
            && lhs.editionRaw == rhs.editionRaw
            && lhs.metatypeRaw == rhs.metatypeRaw
            && lhs.modifiedAt == rhs.modifiedAt
            && lhs.hasAvatar == rhs.hasAvatar
            && lhs.thumbnailData == rhs.thumbnailData
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(streetName)
        hasher.combine(concept)
        hasher.combine(editionRaw)
        hasher.combine(metatypeRaw)
        hasher.combine(modifiedAt)
        hasher.combine(hasAvatar)
        hasher.combine(thumbnailData)
    }

    public var edition: Edition? { Edition(rawValue: editionRaw) }
    public var metatype: MetatypeID? { MetatypeID(rawValue: metatypeRaw) }

    public var displayTitle: String {
        if streetName.isEmpty { return name }
        if name.isEmpty { return streetName }
        return "\(name) “\(streetName)”"
    }
}
