//
//  ImportResult.swift
//  ShadowDeck
//
//  Outcome of a Chummer (or other) import attempt.
//

import Foundation

public enum ImportSourceFormat: String, Sendable, Hashable, Codable {
    case chummerJSON
    case chummerChum5
    case shadowdeckPackage
    case unknown
}

public struct ImportIssue: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var severity: ValidationSeverity
    public var code: String
    public var message: String

    public init(
        id: UUID = UUID(),
        severity: ValidationSeverity,
        code: String,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
    }
}

public struct ImportResult: Sendable {
    public var character: Character
    public var sourceFormat: ImportSourceFormat
    public var sourceFileName: String?
    public var issues: [ImportIssue]
    /// True when core identity/attributes imported but some sections were skipped or approximated.
    public var isPartial: Bool

    public init(
        character: Character,
        sourceFormat: ImportSourceFormat,
        sourceFileName: String? = nil,
        issues: [ImportIssue] = [],
        isPartial: Bool = false
    ) {
        self.character = character
        self.sourceFormat = sourceFormat
        self.sourceFileName = sourceFileName
        self.issues = issues
        self.isPartial = isPartial
    }

    public var warnings: [ImportIssue] {
        issues.filter { $0.severity == .warning || $0.severity == .info }
    }

    public var errors: [ImportIssue] {
        issues.filter { $0.severity == .error }
    }

    public var userFacingSummary: String {
        var parts: [String] = []
        parts.append("Imported \(character.displayTitle) (\(character.edition.rawValue)).")
        if isPartial {
            parts.append("Some data was incomplete or approximated.")
        }
        let warnCount = warnings.count
        if warnCount > 0 {
            parts.append("\(warnCount) warning(s).")
        }
        return parts.joined(separator: " ")
    }
}

public enum ImportError: Error, LocalizedError, Equatable {
    case unsupportedFormat(String)
    case unreadableFile(String)
    case parseFailed(String)
    case missingCharacterData
    case emptyDocument

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let detail):
            return "Unsupported file format: \(detail)"
        case .unreadableFile(let detail):
            return "Could not read file: \(detail)"
        case .parseFailed(let detail):
            return "Failed to parse character file: \(detail)"
        case .missingCharacterData:
            return "No character data found in the file."
        case .emptyDocument:
            return "The file is empty."
        }
    }
}

/// Accumulates non-fatal issues while mapping.
public struct ImportDiagnostics: Sendable {
    public var issues: [ImportIssue] = []
    public var partial = false

    public mutating func warn(_ code: String, _ message: String) {
        issues.append(ImportIssue(severity: .warning, code: code, message: message))
        partial = true
    }

    public mutating func info(_ code: String, _ message: String) {
        issues.append(ImportIssue(severity: .info, code: code, message: message))
    }

    public mutating func error(_ code: String, _ message: String) {
        issues.append(ImportIssue(severity: .error, code: code, message: message))
        partial = true
    }
}
