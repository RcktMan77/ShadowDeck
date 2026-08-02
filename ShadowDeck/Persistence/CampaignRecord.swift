//
//  CampaignRecord.swift
//  ShadowDeck
//
//  SwiftData row for GM campaigns. Full domain `Campaign` lives in JSON payload.
//

import Foundation
import SwiftData

@Model
public final class CampaignRecord {
    @Attribute(.unique) public var id: UUID

    public var name: String
    public var editionRaw: String
    public var isArchived: Bool
    public var modifiedAt: Date
    public var schemaVersion: Int
    public var createdAt: Date

    @Attribute(.externalStorage) public var payload: Data

    public init(
        id: UUID,
        name: String,
        editionRaw: String,
        isArchived: Bool,
        modifiedAt: Date,
        schemaVersion: Int,
        createdAt: Date,
        payload: Data
    ) {
        self.id = id
        self.name = name
        self.editionRaw = editionRaw
        self.isArchived = isArchived
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.payload = payload
    }

    public var edition: Edition {
        Edition(rawValue: editionRaw) ?? .sr5
    }
}
