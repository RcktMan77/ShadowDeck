//
//  CharacterImporter.swift
//  ShadowDeck
//
//  Facade: detect format, parse, map, optionally save to library.
//

import Foundation
import UniformTypeIdentifiers

public enum CharacterImporter {
    public static let supportedExtensions: Set<String> = [
        "json",
        "chum5",
        ShadowDeckFormat.fileExtension,
    ]

    public static var contentTypes: [UTType] {
        var types: [UTType] = [.json]
        if let chum = UTType(filenameExtension: "chum5") {
            types.append(chum)
        }
        if let pack = UTType(filenameExtension: ShadowDeckFormat.fileExtension) {
            types.append(pack)
        }
        // Generic data fallback for odd UTI registration.
        types.append(.data)
        return types
    }

    public static func detectFormat(fileExtension: String, data: Data) -> ImportSourceFormat {
        let ext = fileExtension.lowercased()
        if ext == ShadowDeckFormat.fileExtension { return .shadowdeckPackage }
        if ext == "chum5" { return .chummerChum5 }
        if ext == "json" { return .chummerJSON }

        // Sniff content.
        if let prefix = String(data: data.prefix(200), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            let head = prefix.replacingOccurrences(of: "\u{FEFF}", with: "")
            if head.hasPrefix("<?xml") || head.hasPrefix("<character") {
                return .chummerChum5
            }
            if head.hasPrefix("{") || head.hasPrefix("[") {
                return .chummerJSON
            }
        }
        return .unknown
    }

    public static func importFile(at url: URL) throws -> ImportResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            return try importShadowDeckPackage(at: url)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadableFile(error.localizedDescription)
        }
        if data.isEmpty { throw ImportError.emptyDocument }

        let format = detectFormat(fileExtension: url.pathExtension, data: data)
        return try importData(data, format: format, fileName: url.lastPathComponent)
    }

    public static func importData(
        _ data: Data,
        format: ImportSourceFormat,
        fileName: String? = nil
    ) throws -> ImportResult {
        switch format {
        case .chummerJSON:
            return try importChummerJSON(data, fileName: fileName)
        case .chummerChum5:
            return try importChummerXML(data, fileName: fileName)
        case .shadowdeckPackage:
            throw ImportError.unsupportedFormat("Use importFile for .shadowdeck packages.")
        case .unknown:
            // Try JSON then XML.
            if let result = try? importChummerJSON(data, fileName: fileName) {
                return result
            }
            if let result = try? importChummerXML(data, fileName: fileName) {
                return result
            }
            throw ImportError.unsupportedFormat(fileName ?? "unknown")
        }
    }

    public static func importChummerJSON(_ data: Data, fileName: String? = nil) throws -> ImportResult {
        // JSONSerialization handles BOM poorly; strip if needed.
        let cleaned = stripBOM(data)
        let normalized = try ChummerJSONParser.parse(data: cleaned)
        return finalize(normalized, format: .chummerJSON, fileName: fileName)
    }

    public static func importChummerXML(_ data: Data, fileName: String? = nil) throws -> ImportResult {
        let normalized = try ChummerXMLParser.parse(data: stripBOM(data))
        return finalize(normalized, format: .chummerChum5, fileName: fileName)
    }

    private static func importShadowDeckPackage(at url: URL) throws -> ImportResult {
        let character = try ShadowDeckPackage.importPackage(from: url)
        return ImportResult(
            character: character,
            sourceFormat: .shadowdeckPackage,
            sourceFileName: url.lastPathComponent,
            issues: [
                ImportIssue(
                    severity: .info,
                    code: "package.native",
                    message: "Imported native ShadowDeck package."
                ),
            ],
            isPartial: false
        )
    }

    private static func finalize(
        _ normalized: ChummerNormalizedCharacter,
        format: ImportSourceFormat,
        fileName: String?
    ) -> ImportResult {
        var diagnostics = ImportDiagnostics()
        diagnostics.info(
            "import.source",
            "Parsed \(format == .chummerJSON ? "Chummer JSON" : "Chummer .chum5")\(fileName.map { " (\($0))" } ?? "")."
        )
        let character = ChummerMapper.mapToCharacter(normalized, diagnostics: &diagnostics)
        return ImportResult(
            character: character,
            sourceFormat: format,
            sourceFileName: fileName,
            issues: diagnostics.issues,
            isPartial: diagnostics.partial
        )
    }

    private static func stripBOM(_ data: Data) -> Data {
        // UTF-8 BOM: EF BB BF
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return data.dropFirst(3)
        }
        return data
    }
}

// MARK: - Library integration

@MainActor
public extension CharacterLibrary {
    /// Import a file and save it into the library. Returns the import result (with library id preserved).
    @discardableResult
    func importAndSave(from url: URL) throws -> ImportResult {
        var result = try CharacterImporter.importFile(at: url)
        try save(result.character, avatarData: result.character.avatar.inlineData)
        if let reloaded = try fetch(id: result.character.id) {
            result.character = reloaded
        }
        return result
    }
}
