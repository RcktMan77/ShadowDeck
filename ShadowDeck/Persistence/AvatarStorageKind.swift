//
//  AvatarStorageKind.swift
//  ShadowDeck
//
//  Hybrid avatar policy: small static portraits live inline (SwiftData blob);
//  large and/or animated portraits live on disk under Application Support.
//

import Foundation

public enum AvatarStorageKind: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    /// Bytes stored on the CharacterRecord (SwiftData).
    case inline
    /// Bytes stored as a file; record holds a relative path / file name.
    case file
}

public enum AvatarStoragePolicy: Sendable {
    /// Portraits at or under this size may be stored inline (unless animated).
    public static let maxInlineByteCount = 256 * 1_024

    /// Decide storage for incoming avatar bytes.
    public static func kind(for data: Data, isAnimated: Bool) -> AvatarStorageKind {
        if data.isEmpty { return .none }
        if isAnimated { return .file }
        if data.count > maxInlineByteCount { return .file }
        return .inline
    }

    public static func fileExtension(forMimeType mimeType: String?) -> String {
        switch mimeType?.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/tiff": return "tiff"
        default: return "img"
        }
    }

    public static func mimeType(forFileExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}
