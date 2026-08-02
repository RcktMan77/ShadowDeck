//
//  RunTemplateStore.swift
//  ShadowDeck
//
//  Built-in + user-saved run templates (JSON under Application Support).
//

import Foundation

public enum RunTemplateStoreError: Error, LocalizedError, Equatable {
    case notFound(UUID)
    case emptyName
    case builtinImmutable
    case ioFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Template \(id.uuidString) was not found."
        case .emptyName:
            return "A template needs a non-empty name."
        case .builtinImmutable:
            return "Built-in templates cannot be modified or deleted."
        case .ioFailed(let detail):
            return "Template store error: \(detail)"
        }
    }
}

/// User templates file shape.
private struct UserTemplateFile: Codable {
    var templates: [RunTemplate]
}

@MainActor
public final class RunTemplateStore {
    private let fileURL: URL
    private var userTemplates: [RunTemplate] = []
    public private(set) var changeToken: UInt64 = 0

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = root.appendingPathComponent("ShadowDeck", isDirectory: true)
                .appendingPathComponent("RunTemplates", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("user-templates.json")
        }
        loadFromDisk()
    }

    /// Built-ins first (stable order), then user templates by name.
    public func allTemplates() -> [RunTemplate] {
        let users = userTemplates.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return RunTemplate.builtins + users
    }

    public func template(id: UUID) -> RunTemplate? {
        allTemplates().first { $0.id == id }
    }

    public func saveUserTemplate(_ template: RunTemplate) throws {
        var working = template
        working.name = working.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.name.isEmpty else { throw RunTemplateStoreError.emptyName }
        working.isBuiltin = false
        working.touch()

        if let idx = userTemplates.firstIndex(where: { $0.id == working.id }) {
            userTemplates[idx] = working
        } else {
            userTemplates.append(working)
        }
        try persist()
        changeToken &+= 1
    }

    public func deleteUserTemplate(id: UUID) throws {
        if RunTemplate.builtins.contains(where: { $0.id == id }) {
            throw RunTemplateStoreError.builtinImmutable
        }
        guard userTemplates.contains(where: { $0.id == id }) else {
            throw RunTemplateStoreError.notFound(id)
        }
        userTemplates.removeAll { $0.id == id }
        try persist()
        changeToken &+= 1
    }

    // MARK: - Disk

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            userTemplates = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(UserTemplateFile.self, from: data)
            userTemplates = decoded.templates.filter { !$0.isBuiltin }
        } catch {
            userTemplates = []
        }
    }

    private func persist() throws {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let payload = UserTemplateFile(templates: userTemplates)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw RunTemplateStoreError.ioFailed(error.localizedDescription)
        }
    }
}
