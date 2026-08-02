//
//  CampaignMapper.swift
//  ShadowDeck
//
//  Maps between domain Campaign and SwiftData CampaignRecord payloads.
//

import Foundation

public enum CampaignMapper {
    public static func encodePayload(_ campaign: Campaign) throws -> Data {
        try PortableCharacterCoding.encoder().encode(campaign)
    }

    public static func decodePayload(_ data: Data) throws -> Campaign {
        try PortableCharacterCoding.decoder().decode(Campaign.self, from: data)
    }

    public static func updateRecordMetadata(_ record: CampaignRecord, from campaign: Campaign) {
        record.id = campaign.id
        record.name = campaign.name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.editionRaw = campaign.edition.rawValue
        record.isArchived = campaign.isArchived
        record.modifiedAt = campaign.modifiedAt
        record.schemaVersion = campaign.schemaVersion
        record.createdAt = campaign.createdAt
    }

    public static func summary(
        from campaign: Campaign,
        runCount: Int = 0,
        activeRunCount: Int = 0,
        lastActivityAt: Date? = nil
    ) -> CampaignSummary {
        CampaignSummary(
            id: campaign.id,
            name: campaign.name,
            edition: campaign.edition,
            isArchived: campaign.isArchived,
            modifiedAt: campaign.modifiedAt,
            createdAt: campaign.createdAt,
            runCount: runCount,
            activeRunCount: activeRunCount,
            lastActivityAt: lastActivityAt
        )
    }
}
