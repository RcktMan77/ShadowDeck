//
//  CampaignLibrary.swift
//  ShadowDeck
//
//  App-managed campaign library: CRUD over SwiftData JSON payloads.
//  Deleting a campaign never deletes runs — callers clear `Run.campaignID`.
//

import Foundation
import SwiftData

public enum CampaignLibraryError: Error, LocalizedError, Equatable {
    case notFound(UUID)
    case decodingFailed(String)
    case encodingFailed(String)
    case emptyName

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Campaign \(id.uuidString) was not found in the library."
        case .decodingFailed(let detail):
            return "Could not decode campaign: \(detail)"
        case .encodingFailed(let detail):
            return "Could not encode campaign: \(detail)"
        case .emptyName:
            return "A campaign needs a non-empty name."
        }
    }
}

@MainActor
public final class CampaignLibrary {
    private let modelContext: ModelContext
    private var deletedIDs: Set<UUID> = []
    public private(set) var changeToken: UInt64 = 0

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - List / fetch

    /// - Parameter includeArchived: when false (default), archived campaigns are omitted.
    public func listSummaries(includeArchived: Bool = false) throws -> [CampaignSummary] {
        modelContext.processPendingChanges()
        let records = try modelContext.fetch(FetchDescriptor<CampaignRecord>())
            .filter { !$0.isDeleted }
            .filter { includeArchived || !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt {
                    return lhs.modifiedAt > rhs.modifiedAt
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        return try records.map { record in
            let campaign = try campaign(from: record)
            return CampaignMapper.summary(from: campaign)
        }
    }

    public func count(includeArchived: Bool = false) throws -> Int {
        modelContext.processPendingChanges()
        return try modelContext.fetch(FetchDescriptor<CampaignRecord>())
            .filter { !$0.isDeleted }
            .filter { includeArchived || !$0.isArchived }
            .count
    }

    public func fetch(id: UUID) throws -> Campaign? {
        if deletedIDs.contains(id) { return nil }
        guard let record = try fetchRecord(id: id) else { return nil }
        return try campaign(from: record)
    }

    public func require(_ id: UUID) throws -> Campaign {
        guard let campaign = try fetch(id: id) else {
            throw CampaignLibraryError.notFound(id)
        }
        return campaign
    }

    // MARK: - Save / delete

    public func save(_ campaign: Campaign) throws {
        if deletedIDs.contains(campaign.id) { return }

        var working = campaign
        working.name = working.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.name.isEmpty else {
            throw CampaignLibraryError.emptyName
        }
        working.touch()

        let payload: Data
        do {
            payload = try CampaignMapper.encodePayload(working)
        } catch {
            throw CampaignLibraryError.encodingFailed(error.localizedDescription)
        }

        let existing = try fetchRecord(id: working.id)
        if let existing, existing.isDeleted { return }

        let record = existing ?? CampaignRecord(
            id: working.id,
            name: working.name,
            editionRaw: working.edition.rawValue,
            isArchived: working.isArchived,
            modifiedAt: working.modifiedAt,
            schemaVersion: working.schemaVersion,
            createdAt: working.createdAt,
            payload: payload
        )

        if record.modelContext == nil {
            modelContext.insert(record)
        }

        CampaignMapper.updateRecordMetadata(record, from: working)
        record.payload = payload

        try modelContext.save()
        modelContext.processPendingChanges()
        changeToken &+= 1
    }

    /// Deletes the campaign row only. Callers must clear `campaignID` on affected runs.
    public func delete(id: UUID) throws {
        deletedIDs.insert(id)
        let matches = try modelContext.fetch(FetchDescriptor<CampaignRecord>())
            .filter { $0.id == id && !$0.isDeleted }
        guard !matches.isEmpty else {
            changeToken &+= 1
            return
        }
        for record in matches {
            modelContext.delete(record)
        }
        try modelContext.save()
        modelContext.processPendingChanges()
        changeToken &+= 1
    }

    // MARK: - Private

    private func fetchRecord(id: UUID) throws -> CampaignRecord? {
        modelContext.processPendingChanges()
        return try modelContext.fetch(FetchDescriptor<CampaignRecord>())
            .first { $0.id == id && !$0.isDeleted }
    }

    private func campaign(from record: CampaignRecord) throws -> Campaign {
        do {
            return try CampaignMapper.decodePayload(record.payload)
        } catch {
            throw CampaignLibraryError.decodingFailed(error.localizedDescription)
        }
    }
}
