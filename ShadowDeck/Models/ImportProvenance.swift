//
//  ImportProvenance.swift
//  ShadowDeck
//
//  Optional original Chummer payload retained for faithful re-export.
//

import Foundation

public struct ImportProvenance: Codable, Sendable, Hashable {
    public var sourceFormat: String
    public var originalFileName: String?
    public var importedAt: Date
    /// Raw `.chum5` / JSON bytes from the original import (may be large).
    public var originalPayload: Data?

    public init(
        sourceFormat: String,
        originalFileName: String? = nil,
        importedAt: Date = Date(),
        originalPayload: Data? = nil
    ) {
        self.sourceFormat = sourceFormat
        self.originalFileName = originalFileName
        self.importedAt = importedAt
        self.originalPayload = originalPayload
    }

    public var hasOriginalChummerXML: Bool {
        guard sourceFormat == "chum5" || sourceFormat == "chummerXML" || sourceFormat.lowercased().contains("chum") else {
            return originalPayload != nil && (originalFileName?.lowercased().hasSuffix("chum5") == true)
        }
        return originalPayload != nil
    }
}
