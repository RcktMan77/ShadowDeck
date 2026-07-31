//
//  RunLibrary.swift
//  ShadowDeck
//
//  App-managed run / mission library: CRUD over SwiftData JSON payloads.
//

import Foundation
import SwiftData

public enum RunLibraryError: Error, LocalizedError, Equatable {
    case notFound(UUID)
    case decodingFailed(String)
    case encodingFailed(String)
    case emptyTitle

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Run \(id.uuidString) was not found in the library."
        case .decodingFailed(let detail):
            return "Could not decode run: \(detail)"
        case .encodingFailed(let detail):
            return "Could not encode run: \(detail)"
        case .emptyTitle:
            return "A run needs a non-empty title."
        }
    }
}

@MainActor
public final class RunLibrary {
    private let modelContext: ModelContext
    /// IDs deleted this process lifetime — blocks deferred UI auto-saves from re-inserting them.
    private var deletedIDs: Set<UUID> = []
    /// Bumped after every successful save/delete so observers can refresh badges/lists.
    public private(set) var changeToken: UInt64 = 0

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - List / fetch

    public func listSummaries() throws -> [RunSummary] {
        modelContext.processPendingChanges()
        let records = try modelContext.fetch(FetchDescriptor<RunRecord>())
            .filter { !$0.isDeleted }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        return records.map { record in
            // Prefer tags from full payload when available (cheap enough for small libraries).
            if let run = try? run(from: record) {
                return RunMapper.summary(from: run)
            }
            return record.summary
        }
    }

    public func count() throws -> Int {
        modelContext.processPendingChanges()
        return try modelContext.fetch(FetchDescriptor<RunRecord>())
            .filter { !$0.isDeleted }
            .count
    }

    public func fetch(id: UUID) throws -> Run? {
        if deletedIDs.contains(id) { return nil }
        guard let record = try fetchRecord(id: id) else { return nil }
        return try run(from: record)
    }

    public func require(_ id: UUID) throws -> Run {
        guard let run = try fetch(id: id) else {
            throw RunLibraryError.notFound(id)
        }
        return run
    }

    // MARK: - Save / delete

    public func save(_ run: Run) throws {
        // Deferred NotesEditor / onDisappear commits after Delete must not resurrect rows.
        if deletedIDs.contains(run.id) {
            return
        }

        var working = run
        working.title = working.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.title.isEmpty else {
            throw RunLibraryError.emptyTitle
        }
        working.touch()

        let payload: Data
        do {
            payload = try RunMapper.encodePayload(working)
        } catch {
            throw RunLibraryError.encodingFailed(error.localizedDescription)
        }

        let existing = try fetchRecord(id: working.id)
        // Never revive a SwiftData object that is already marked deleted in this context.
        if let existing, existing.isDeleted {
            return
        }

        let record = existing ?? RunRecord(
            id: working.id,
            title: working.title,
            statusRaw: working.status.rawValue,
            plannedDate: working.plannedDate,
            modifiedAt: working.modifiedAt,
            schemaVersion: working.schemaVersion,
            createdAt: working.createdAt,
            participantIDsJSON: Data(),
            payload: payload
        )

        if record.modelContext == nil {
            modelContext.insert(record)
        }

        do {
            try RunMapper.updateRecordMetadata(record, from: working)
        } catch {
            throw RunLibraryError.encodingFailed(error.localizedDescription)
        }
        record.payload = payload

        try modelContext.save()
        modelContext.processPendingChanges()
        changeToken &+= 1
    }

    public func delete(id: UUID) throws {
        // Block any in-flight UI save for this id before/after the store delete.
        deletedIDs.insert(id)

        // Delete every matching row (defensive if duplicates ever appear).
        let matches = try modelContext.fetch(FetchDescriptor<RunRecord>())
            .filter { $0.id == id && !$0.isDeleted }
        guard !matches.isEmpty else {
            // Already gone — still bump token so UI refreshes.
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

    private func fetchRecord(id: UUID) throws -> RunRecord? {
        // Filter in-process to avoid Sendable KeyPath warnings on predicates in some toolchains.
        try modelContext.fetch(FetchDescriptor<RunRecord>())
            .first { $0.id == id && !$0.isDeleted }
    }

    private func run(from record: RunRecord) throws -> Run {
        do {
            return try RunMapper.decodePayload(record.payload)
        } catch {
            throw RunLibraryError.decodingFailed(error.localizedDescription)
        }
    }
}
