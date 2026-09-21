//
//  PersistenceTests.swift
//  ShadowDeckTests
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import SwiftData
@testable import ShadowDeck

private final class CountingAvatarStore: AvatarStoreProtocol, @unchecked Sendable {
    let inner: AvatarStore
    var loadCount = 0

    init(inner: AvatarStore) { self.inner = inner }

    func store(
        characterID: UUID,
        data: Data,
        mimeType: String?,
        isAnimated: Bool
    ) throws -> ResolvedAvatar {
        try inner.store(characterID: characterID, data: data, mimeType: mimeType, isAnimated: isAnimated)
    }

    func load(characterID: UUID, record: AvatarRecordSnapshot) throws -> Data? {
        loadCount += 1
        return try inner.load(characterID: characterID, record: record)
    }

    func delete(characterID: UUID) throws {
        try inner.delete(characterID: characterID)
    }

    func fileURL(characterID: UUID, fileName: String) -> URL {
        inner.fileURL(characterID: characterID, fileName: fileName)
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    private var avatarRoot: URL!
    private var library: CharacterLibrary!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
        container = try PersistenceController.makeContainer(inMemory: true)
        library = try PersistenceController.makeLibrary(container: container, avatarRoot: avatarRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: avatarRoot)
        library = nil
        container = nil
        avatarRoot = nil
        try super.tearDownWithError()
    }

    func testCRUDRoundTrip() throws {
        let original = SampleCharacters.sr5CombatMage()
        try library.save(original)

        XCTAssertEqual(try library.count(), 1)
        let summaries = try library.listSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].id, original.id)
        XCTAssertEqual(summaries[0].editionRaw, Edition.sr5.rawValue)

        var loaded = try library.require(original.id)
        XCTAssertEqual(loaded.name, original.name)
        XCTAssertEqual(loaded.attributes.magic, original.attributes.magic)
        XCTAssertEqual(loaded.spells.count, original.spells.count)
        XCTAssertEqual(loaded.generation.system, .priority)

        loaded.nuyen = 12_345
        loaded.concept = "Updated combat mage"
        try library.save(loaded)

        let again = try library.require(original.id)
        XCTAssertEqual(again.nuyen, 12_345)
        XCTAssertEqual(again.concept, "Updated combat mage")

        try library.delete(id: original.id)
        XCTAssertEqual(try library.count(), 0)
        XCTAssertNil(try library.fetch(id: original.id))
    }

    func testMultipleEditionsPersist() throws {
        for sample in SampleCharacters.makeAll() {
            try library.save(sample)
        }
        XCTAssertEqual(try library.count(), 3)
        let editions = Set(try library.listSummaries().compactMap(\.edition))
        XCTAssertEqual(editions, Set(Edition.allCases))
    }

    func testListSummariesUsesStoredThumbnailWithoutLoadingAvatar() throws {
        let inner = AvatarStore(rootDirectory: avatarRoot)
        let counting = CountingAvatarStore(inner: inner)
        library = CharacterLibrary(modelContext: container.mainContext, avatarStore: counting)

        var character = SampleCharacters.sr4StreetSamurai()
        let jpeg = Self.solidJPEG()
        character.avatar.mimeType = "image/jpeg"
        character.avatar.isAnimated = false
        try library.save(character, avatarData: jpeg)

        let loadsAfterSave = counting.loadCount
        let first = try library.listSummaries()
        let second = try library.listSummaries()
        XCTAssertEqual(counting.loadCount, loadsAfterSave)
        XCTAssertEqual(first.first?.thumbnailData, second.first?.thumbnailData)
        XCTAssertNotNil(first.first?.thumbnailData)
        XCTAssertNotEqual(first.first?.thumbnailData, jpeg)
    }

    private static func solidJPEG() -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = ctx.makeImage() else {
            return Data()
        }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let painted = ctx.makeImage() ?? image
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(dest, painted, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testSmallAvatarStoredInline() throws {
        var character = SampleCharacters.sr4StreetSamurai()
        let bytes = Data(repeating: 0xAB, count: 4_096) // 4 KB < 256 KB
        character.avatar.mimeType = "image/png"
        character.avatar.isAnimated = false

        try library.save(character, avatarData: bytes)

        let loaded = try library.require(character.id)
        XCTAssertEqual(loaded.avatar.inlineData, bytes)
        XCTAssertEqual(loaded.avatar.mimeType, "image/png")

        // Inspect record storage kind
        let record = try fetchRecord(id: character.id)
        XCTAssertEqual(record.avatarKind, .inline)
        XCTAssertEqual(record.avatarInlineData, bytes)
        XCTAssertNil(record.avatarFileName)
        XCTAssertEqual(record.avatarByteCount, bytes.count)
    }

    func testLargeAvatarStoredAsFile() throws {
        var character = SampleCharacters.sr6FaceHacker()
        let bytes = Data(repeating: 0xCD, count: AvatarStoragePolicy.maxInlineByteCount + 1_024)
        character.avatar.mimeType = "image/jpeg"
        character.avatar.isAnimated = false

        try library.save(character, avatarData: bytes)

        let loaded = try library.require(character.id)
        XCTAssertEqual(loaded.avatar.inlineData, bytes)

        let record = try fetchRecord(id: character.id)
        XCTAssertEqual(record.avatarKind, .file)
        XCTAssertNil(record.avatarInlineData)
        XCTAssertEqual(record.avatarFileName, "portrait.jpg")
        XCTAssertEqual(record.avatarByteCount, bytes.count)

        let fileURL = avatarRoot
            .appendingPathComponent(character.id.uuidString)
            .appendingPathComponent("portrait.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    }

    func testAnimatedAvatarAlwaysFile() throws {
        var character = SampleCharacters.sr5CombatMage()
        let bytes = Data(repeating: 0xEF, count: 512) // small but animated
        character.avatar.mimeType = "image/gif"
        character.avatar.isAnimated = true

        try library.save(character, avatarData: bytes)

        let record = try fetchRecord(id: character.id)
        XCTAssertEqual(record.avatarKind, .file)
        XCTAssertTrue(record.avatarIsAnimated)
        XCTAssertNil(record.avatarInlineData)
        XCTAssertEqual(try library.require(character.id).avatar.inlineData, bytes)
    }

    func testDeleteRemovesAvatarFiles() throws {
        var character = SampleCharacters.sr4StreetSamurai()
        let bytes = Data(repeating: 0x11, count: AvatarStoragePolicy.maxInlineByteCount + 10)
        try library.save(character, avatarData: bytes)

        let dir = avatarRoot.appendingPathComponent(character.id.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        try library.delete(id: character.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testShadowDeckPackageRoundTripWithAvatar() throws {
        var character = SampleCharacters.sr5CombatMage()
        let bytes = Data(repeating: 0x42, count: 8_192)
        character.avatar.mimeType = "image/png"
        try library.save(character, avatarData: bytes)

        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(character.id.uuidString).shadowdeck")
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try library.exportPackage(id: character.id, to: packageURL)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: packageURL.appendingPathComponent("character.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: packageURL.appendingPathComponent("manifest.json").path
        ))

        // Fresh library simulates another machine / reinstall.
        let avatarRoot2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Tests-Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: avatarRoot2) }

        let container2 = try PersistenceController.makeContainer(inMemory: true)
        let library2 = try PersistenceController.makeLibrary(container: container2, avatarRoot: avatarRoot2)

        let imported = try library2.importPackage(from: packageURL)
        XCTAssertEqual(imported.id, character.id)
        XCTAssertEqual(imported.name, character.name)
        XCTAssertEqual(imported.edition, .sr5)
        XCTAssertEqual(imported.avatar.inlineData, bytes)
        XCTAssertEqual(try library2.count(), 1)
    }

    func testPackageDirectIOWithoutLibrary() throws {
        var character = SampleCharacters.sr4StreetSamurai()
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        character.avatar.inlineData = bytes
        character.avatar.mimeType = "image/png"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-\(UUID().uuidString).shadowdeck")
        defer { try? FileManager.default.removeItem(at: url) }

        try ShadowDeckPackage.export(character: character, avatarData: bytes, to: url)
        let imported = try ShadowDeckPackage.importPackage(from: url)
        XCTAssertEqual(imported.attributes.body, character.attributes.body)
        XCTAssertEqual(imported.avatar.inlineData, bytes)
    }

    func testAvatarPolicyThresholds() {
        let small = Data(repeating: 1, count: 100)
        let large = Data(repeating: 1, count: AvatarStoragePolicy.maxInlineByteCount + 1)
        XCTAssertEqual(AvatarStoragePolicy.kind(for: small, isAnimated: false), .inline)
        XCTAssertEqual(AvatarStoragePolicy.kind(for: large, isAnimated: false), .file)
        XCTAssertEqual(AvatarStoragePolicy.kind(for: small, isAnimated: true), .file)
        XCTAssertEqual(AvatarStoragePolicy.kind(for: Data(), isAnimated: false), .none)
    }

    func testPerformanceDozensOfCharacters() throws {
        // Acceptable for dozens of characters: save 40 samples with mutations.
        measure {
            do {
                let tempRoot = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ShadowDeck-Perf-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempRoot) }

                let perfContainer = try PersistenceController.makeContainer(inMemory: true)
                let perfLibrary = try PersistenceController.makeLibrary(
                    container: perfContainer,
                    avatarRoot: tempRoot
                )

                for i in 0..<40 {
                    var c = SampleCharacters.sr5CombatMage()
                    c.id = UUID()
                    c.name = "Runner \(i)"
                    c.streetName = "Handle\(i)"
                    try perfLibrary.save(c)
                }
                XCTAssertEqual(try perfLibrary.count(), 40)
                _ = try perfLibrary.listSummaries()
            } catch {
                XCTFail("Performance setup failed: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func fetchRecord(id: UUID) throws -> CharacterRecord {
        let context = container.mainContext
        var descriptor = FetchDescriptor<CharacterRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            XCTFail("Record missing")
            throw CharacterLibraryError.notFound(id)
        }
        return record
    }
}
