//
//  Quality.swift
//  ShadowDeck
//

import Foundation

public enum QualityKind: String, Codable, Sendable, CaseIterable, Hashable {
    case positive
    case negative
}

public struct QualityInstance: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var catalogKey: String
    public var name: String
    public var kind: QualityKind
    /// Karma cost (positive qualities cost karma; negative grant karma). Sign is semantic by kind.
    public var karmaValue: Int
    public var rating: Int?
    public var notes: String

    public init(
        id: UUID = UUID(),
        catalogKey: String,
        name: String,
        kind: QualityKind,
        karmaValue: Int,
        rating: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.kind = kind
        self.karmaValue = karmaValue
        self.rating = rating
        self.notes = notes
    }
}
