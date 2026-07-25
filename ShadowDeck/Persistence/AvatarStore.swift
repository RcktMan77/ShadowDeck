//
//  AvatarStore.swift
//  ShadowDeck
//
//  Hybrid avatar file layout:
//    <Application Support>/ShadowDeck/Avatars/<characterID>/portrait.<ext>
//

import Foundation

public struct ResolvedAvatar: Sendable, Hashable {
    public var kind: AvatarStorageKind
    public var data: Data?
    public var fileName: String?
    public var mimeType: String?
    public var isAnimated: Bool
    public var byteCount: Int

    public init(
        kind: AvatarStorageKind,
        data: Data? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        isAnimated: Bool = false,
        byteCount: Int = 0
    ) {
        self.kind = kind
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
        self.isAnimated = isAnimated
        self.byteCount = byteCount
    }

    public var hasImage: Bool { kind != .none && byteCount > 0 }
}

public protocol AvatarStoreProtocol: Sendable {
    func store(
        characterID: UUID,
        data: Data,
        mimeType: String?,
        isAnimated: Bool
    ) throws -> ResolvedAvatar

    func load(characterID: UUID, record: AvatarRecordSnapshot) throws -> Data?

    func delete(characterID: UUID) throws

    func fileURL(characterID: UUID, fileName: String) -> URL
}

/// Snapshot of avatar fields on a persisted record (avoids coupling to SwiftData in pure logic).
public struct AvatarRecordSnapshot: Sendable, Hashable {
    public var kind: AvatarStorageKind
    public var fileName: String?
    public var mimeType: String?
    public var isAnimated: Bool
    public var inlineData: Data?
    public var byteCount: Int

    public init(
        kind: AvatarStorageKind,
        fileName: String? = nil,
        mimeType: String? = nil,
        isAnimated: Bool = false,
        inlineData: Data? = nil,
        byteCount: Int = 0
    ) {
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.isAnimated = isAnimated
        self.inlineData = inlineData
        self.byteCount = byteCount
    }
}

public final class AvatarStore: AvatarStoreProtocol, @unchecked Sendable {
    private let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    /// Default store under Application Support/ShadowDeck/Avatars.
    public static func applicationSupportStore(
        fileManager: FileManager = .default
    ) throws -> AvatarStore {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport
            .appendingPathComponent("ShadowDeck", isDirectory: true)
            .appendingPathComponent("Avatars", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return AvatarStore(rootDirectory: root, fileManager: fileManager)
    }

    public func characterDirectory(for characterID: UUID) -> URL {
        rootDirectory.appendingPathComponent(characterID.uuidString, isDirectory: true)
    }

    public func fileURL(characterID: UUID, fileName: String) -> URL {
        characterDirectory(for: characterID).appendingPathComponent(fileName, isDirectory: false)
    }

    public func store(
        characterID: UUID,
        data: Data,
        mimeType: String?,
        isAnimated: Bool
    ) throws -> ResolvedAvatar {
        // Clear previous material first.
        try delete(characterID: characterID)

        let kind = AvatarStoragePolicy.kind(for: data, isAnimated: isAnimated)
        switch kind {
        case .none:
            return ResolvedAvatar(kind: .none)
        case .inline:
            return ResolvedAvatar(
                kind: .inline,
                data: data,
                fileName: nil,
                mimeType: mimeType,
                isAnimated: false,
                byteCount: data.count
            )
        case .file:
            let ext = AvatarStoragePolicy.fileExtension(forMimeType: mimeType)
            let fileName = "portrait.\(ext)"
            let dir = characterDirectory(for: characterID)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return ResolvedAvatar(
                kind: .file,
                data: nil,
                fileName: fileName,
                mimeType: mimeType ?? AvatarStoragePolicy.mimeType(forFileExtension: ext),
                isAnimated: isAnimated,
                byteCount: data.count
            )
        }
    }

    public func load(characterID: UUID, record: AvatarRecordSnapshot) throws -> Data? {
        switch record.kind {
        case .none:
            return nil
        case .inline:
            return record.inlineData
        case .file:
            guard let fileName = record.fileName else { return nil }
            let url = fileURL(characterID: characterID, fileName: fileName)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        }
    }

    public func delete(characterID: UUID) throws {
        let dir = characterDirectory(for: characterID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }
}
