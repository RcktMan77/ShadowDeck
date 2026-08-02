//
//  RunMapper.swift
//  ShadowDeck
//
//  Maps between domain Run and SwiftData RunRecord payloads.
//

import Foundation

public enum RunMapper {
    public static func encodePayload(_ run: Run) throws -> Data {
        try PortableCharacterCoding.encoder().encode(run)
    }

    public static func decodePayload(_ data: Data) throws -> Run {
        try PortableCharacterCoding.decoder().decode(Run.self, from: data)
    }

    public static func encodeParticipantIDs(_ ids: [UUID]) throws -> Data {
        try JSONEncoder().encode(ids)
    }

    public static func updateRecordMetadata(_ record: RunRecord, from run: Run) throws {
        record.id = run.id
        record.title = run.title.trimmingCharacters(in: .whitespacesAndNewlines)
        record.statusRaw = run.status.rawValue
        record.plannedDate = run.plannedDate
        record.modifiedAt = run.modifiedAt
        record.schemaVersion = run.schemaVersion
        record.createdAt = run.createdAt
        record.participantIDsJSON = try encodeParticipantIDs(run.participantCharacterIDs)
        record.campaignIDString = run.campaignID?.uuidString
    }

    public static func summary(from run: Run) -> RunSummary {
        RunSummary(
            id: run.id,
            title: run.title,
            status: run.status,
            edition: run.edition,
            tags: run.tags,
            plannedDate: run.plannedDate,
            startedAt: run.startedAt,
            completedAt: run.completedAt,
            modifiedAt: run.modifiedAt,
            participantCharacterIDs: run.participantCharacterIDs,
            campaignID: run.campaignID
        )
    }
}
