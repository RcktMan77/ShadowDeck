//
//  RunRecord.swift
//  ShadowDeck
//
//  SwiftData library row for GM runs. Full domain `Run` is stored as JSON payload;
//  list/filter fields are denormalized.
//

import Foundation
import SwiftData

@Model
public final class RunRecord {
    @Attribute(.unique) public var id: UUID

    public var title: String
    public var statusRaw: String
    public var plannedDate: Date?
    public var modifiedAt: Date
    public var schemaVersion: Int
    public var createdAt: Date

    /// JSON-encoded `[UUID]` for participant filter without loading payload.
    public var participantIDsJSON: Data

    /// Full `Run` JSON.
    @Attribute(.externalStorage) public var payload: Data

    public init(
        id: UUID,
        title: String,
        statusRaw: String,
        plannedDate: Date?,
        modifiedAt: Date,
        schemaVersion: Int,
        createdAt: Date,
        participantIDsJSON: Data,
        payload: Data
    ) {
        self.id = id
        self.title = title
        self.statusRaw = statusRaw
        self.plannedDate = plannedDate
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.participantIDsJSON = participantIDsJSON
        self.payload = payload
    }

    public var status: RunStatus {
        RunStatus(rawValue: statusRaw) ?? .planning
    }

    public var participantIDs: [UUID] {
        (try? JSONDecoder().decode([UUID].self, from: participantIDsJSON)) ?? []
    }

    public var summary: RunSummary {
        RunSummary(
            id: id,
            title: title,
            status: status,
            edition: .sr5, // payload may refine when fully decoded
            tags: [], // tags live in payload; list can refresh from fetch when needed
            plannedDate: plannedDate,
            startedAt: nil,
            completedAt: nil,
            modifiedAt: modifiedAt,
            participantCharacterIDs: participantIDs
        )
    }
}

/// Lightweight list DTO for the Runs sidebar list.
public struct RunSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var status: RunStatus
    public var edition: Edition
    public var tags: [String]
    public var plannedDate: Date?
    public var startedAt: Date?
    public var completedAt: Date?
    public var modifiedAt: Date
    public var participantCharacterIDs: [UUID]

    public var participantCount: Int { participantCharacterIDs.count }

    public init(
        id: UUID,
        title: String,
        status: RunStatus,
        edition: Edition = .sr5,
        tags: [String] = [],
        plannedDate: Date?,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        modifiedAt: Date,
        participantCharacterIDs: [UUID]
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.edition = edition
        self.tags = tags
        self.plannedDate = plannedDate
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.modifiedAt = modifiedAt
        self.participantCharacterIDs = participantCharacterIDs
    }
}
