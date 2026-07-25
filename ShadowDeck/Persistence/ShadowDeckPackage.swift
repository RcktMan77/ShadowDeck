//
//  ShadowDeckPackage.swift
//  ShadowDeck
//
//  Native portable format: a directory package with extension `.shadowdeck`.
//  Finder presents it as a single object; contents are efficient plain files.
//
//    Runner.shadowdeck/
//      manifest.json
//      character.json
//      avatar/portrait.<ext>   (optional)
//

import Foundation
import UniformTypeIdentifiers

public enum ShadowDeckPackageError: Error, LocalizedError, Equatable {
    case notAPackage
    case missingCharacterJSON
    case invalidManifest
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAPackage:
            return "The selected item is not a ShadowDeck character package."
        case .missingCharacterJSON:
            return "The package is missing character.json."
        case .invalidManifest:
            return "The package manifest is invalid."
        case .writeFailed(let detail):
            return "Failed to write package: \(detail)"
        case .readFailed(let detail):
            return "Failed to read package: \(detail)"
        }
    }
}

public enum ShadowDeckPackage {
    public static var utType: UTType {
        UTType(filenameExtension: ShadowDeckFormat.fileExtension)
            ?? .package
    }

    /// Writes a directory package at `url` (should end in `.shadowdeck`).
    /// Replaces any existing item at the URL.
    public static func export(
        character: Character,
        avatarData: Data?,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let fm = fileManager
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        var exportCharacter = character
        // Keep metadata; put binary under avatar/ instead of bloating JSON.
        let resolvedAvatarData = avatarData ?? character.avatar.inlineData
        exportCharacter.avatar.inlineData = nil
        if let resolvedAvatarData, !resolvedAvatarData.isEmpty {
            let ext = AvatarStoragePolicy.fileExtension(forMimeType: character.avatar.mimeType)
            let avatarDir = url.appendingPathComponent(ShadowDeckFormat.avatarDirectoryName, isDirectory: true)
            try fm.createDirectory(at: avatarDir, withIntermediateDirectories: true)
            let fileName = "portrait.\(ext)"
            let avatarURL = avatarDir.appendingPathComponent(fileName)
            try resolvedAvatarData.write(to: avatarURL, options: .atomic)
            exportCharacter.avatar.fileName = fileName
            exportCharacter.avatar.mimeType = character.avatar.mimeType
                ?? AvatarStoragePolicy.mimeType(forFileExtension: ext)
        }

        let document = PortableCharacterDocument(character: exportCharacter)
        let characterData = try PortableCharacterCoding.encode(document)
        let characterURL = url.appendingPathComponent(ShadowDeckFormat.characterJSONFileName)
        try characterData.write(to: characterURL, options: .atomic)

        var manifest = PortableManifest(from: exportCharacter)
        manifest.hasAvatar = resolvedAvatarData != nil && !(resolvedAvatarData?.isEmpty ?? true)
        let manifestData = try PortableCharacterCoding.encoder().encode(manifest)
        let manifestURL = url.appendingPathComponent(ShadowDeckFormat.manifestFileName)
        try manifestData.write(to: manifestURL, options: .atomic)
    }

    /// Reads a directory package and returns the domain character with avatar bytes inline when present.
    public static func importPackage(
        from url: URL,
        fileManager: FileManager = .default
    ) throws -> Character {
        let fm = fileManager
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ShadowDeckPackageError.notAPackage
        }

        let characterURL = url.appendingPathComponent(ShadowDeckFormat.characterJSONFileName)
        guard fm.fileExists(atPath: characterURL.path) else {
            throw ShadowDeckPackageError.missingCharacterJSON
        }

        let data: Data
        do {
            data = try Data(contentsOf: characterURL)
        } catch {
            throw ShadowDeckPackageError.readFailed(error.localizedDescription)
        }

        let document = try PortableCharacterCoding.decode(from: data)
        var character = document.character

        // Prefer avatar/ folder if present.
        let avatarDir = url.appendingPathComponent(ShadowDeckFormat.avatarDirectoryName, isDirectory: true)
        if let avatarFile = try? fm.contentsOfDirectory(at: avatarDir, includingPropertiesForKeys: nil)
            .first(where: { !$0.lastPathComponent.hasPrefix(".") })
        {
            let bytes = try Data(contentsOf: avatarFile)
            character.avatar.inlineData = bytes
            character.avatar.fileName = avatarFile.lastPathComponent
            if character.avatar.mimeType == nil {
                character.avatar.mimeType = AvatarStoragePolicy.mimeType(
                    forFileExtension: avatarFile.pathExtension
                )
            }
        }

        return character
    }
}
