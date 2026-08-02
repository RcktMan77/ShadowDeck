//
//  RunTemplate.swift
//  ShadowDeck
//
//  Reusable job patterns for Run Tracker Phase 2B.
//  Title patterns support simple `{location}` substitution only (no expression language).
//

import Foundation

public struct RunTemplateObjective: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var text: String
    public var isPrimary: Bool

    public init(id: UUID = UUID(), text: String, isPrimary: Bool = true) {
        self.id = id
        self.text = text
        self.isPrimary = isPrimary
    }
}

/// Saved or built-in pattern used to mint a planning `Run`.
public struct RunTemplate: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// e.g. `"Extraction — {location}"`. Only `{location}` is substituted.
    public var titlePattern: String
    public var objectives: [RunTemplateObjective]
    public var oppositionPrompt: String
    public var expectedPayout: RunPayout
    public var tags: [String]
    public var editionHint: Edition?
    /// Built-in starters cannot be deleted.
    public var isBuiltin: Bool
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        titlePattern: String,
        objectives: [RunTemplateObjective] = [],
        oppositionPrompt: String = "",
        expectedPayout: RunPayout = .zero,
        tags: [String] = [],
        editionHint: Edition? = nil,
        isBuiltin: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.titlePattern = titlePattern
        self.objectives = objectives
        self.oppositionPrompt = oppositionPrompt
        self.expectedPayout = expectedPayout
        self.tags = tags
        self.editionHint = editionHint
        self.isBuiltin = isBuiltin
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public mutating func touch() {
        modifiedAt = Date()
    }

    /// Apply simple `{location}` replace (and trim). Empty location → `"TBD"`.
    public func resolvedTitle(location: String = "") -> String {
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = loc.isEmpty ? "TBD" : loc
        let raw = titlePattern.replacingOccurrences(of: "{location}", with: value)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }
}

// MARK: - Built-in starters

public extension RunTemplate {
    /// Extraction, data steal, protection, courier — read-only seeds.
    static let builtins: [RunTemplate] = [
        RunTemplate(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000001")!,
            name: "Extraction",
            titlePattern: "Extraction — {location}",
            objectives: [
                RunTemplateObjective(text: "Extract the target alive", isPrimary: true),
                RunTemplateObjective(text: "Avoid civilian casualties", isPrimary: false),
                RunTemplateObjective(text: "Reach the extraction point on schedule", isPrimary: false)
            ],
            oppositionPrompt: "Corporate security detail; possible magical support; cameras / SIN checks on approach.",
            expectedPayout: RunPayout(nuyen: 12_000, karma: 5),
            tags: ["Extraction"],
            isBuiltin: true
        ),
        RunTemplate(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000002")!,
            name: "Data steal",
            titlePattern: "Data steal — {location}",
            objectives: [
                RunTemplateObjective(text: "Retrieve the paydata from the host", isPrimary: true),
                RunTemplateObjective(text: "Leave no trace (or frame a rival)", isPrimary: false),
                RunTemplateObjective(text: "Exfiltrate before IC escalates", isPrimary: false)
            ],
            oppositionPrompt: "Host IC and spider coverage; physical security on the site; possible decker rival.",
            expectedPayout: RunPayout(nuyen: 15_000, karma: 6),
            tags: ["Datasteal", "Matrix"],
            isBuiltin: true
        ),
        RunTemplate(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000003")!,
            name: "Protection",
            titlePattern: "Protection — {location}",
            objectives: [
                RunTemplateObjective(text: "Keep the principal safe through the window", isPrimary: true),
                RunTemplateObjective(text: "Identify and neutralize the threat", isPrimary: false),
                RunTemplateObjective(text: "Maintain a low profile if possible", isPrimary: false)
            ],
            oppositionPrompt: "Unknown hit team; surveillance; possible inside leak.",
            expectedPayout: RunPayout(nuyen: 10_000, karma: 4),
            tags: ["Protection", "Bodyguard"],
            isBuiltin: true
        ),
        RunTemplate(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000004")!,
            name: "Courier",
            titlePattern: "Courier — {location}",
            objectives: [
                RunTemplateObjective(text: "Deliver the package intact", isPrimary: true),
                RunTemplateObjective(text: "Do not open or inspect the contents", isPrimary: false),
                RunTemplateObjective(text: "Arrive within the time window", isPrimary: false)
            ],
            oppositionPrompt: "Intercept attempts; roadblocks / drones; competing runners.",
            expectedPayout: RunPayout(nuyen: 8_000, karma: 3),
            tags: ["Courier", "Delivery"],
            isBuiltin: true
        )
    ]
}

// MARK: - Run factory from template

public extension Run {
    /// Mint a planning run from a template. Only `{location}` is substituted in the title pattern.
    static func makeDraft(
        from template: RunTemplate,
        location: String = "",
        campaignID: UUID? = nil,
        edition: Edition? = nil
    ) -> Run {
        let resolvedEdition = edition ?? template.editionHint ?? .sr5
        let title = template.resolvedTitle(location: location)
        var run = Run.makeDraft(title: title, edition: resolvedEdition, campaignID: campaignID)
        run.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        run.tags = template.tags
        run.opposition = template.oppositionPrompt
        run.expectedPayout = template.expectedPayout
        run.objectives = template.objectives.map {
            RunObjective(text: $0.text, isPrimary: $0.isPrimary, status: .pending)
        }
        return run
    }

    /// Capture the current run as a user template (not builtin).
    func asTemplate(name: String) -> RunTemplate {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern: String = {
            let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !loc.isEmpty, title.localizedCaseInsensitiveContains(loc) {
                return title.replacingOccurrences(of: loc, with: "{location}")
            }
            return title.isEmpty ? "{location}" : title
        }()
        return RunTemplate(
            name: trimmedName.isEmpty ? "Custom template" : trimmedName,
            titlePattern: pattern,
            objectives: objectives.map {
                RunTemplateObjective(text: $0.text, isPrimary: $0.isPrimary)
            },
            oppositionPrompt: Run.isBlankNote(opposition)
                ? ""
                : ChummerParsingHelpers.cleanRichText(opposition),
            expectedPayout: expectedPayout,
            tags: tags,
            editionHint: edition,
            isBuiltin: false
        )
    }
}
