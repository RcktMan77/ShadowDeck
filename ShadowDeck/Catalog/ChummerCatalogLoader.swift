//
//  ChummerCatalogLoader.swift
//  ShadowDeck
//
//  Bundled catalogs: `sr4_catalog.json` (SR4A PDF extract) and `sr5_catalog.json`
//  (Chummer5a GPL). Optional developer override to load live Chummer `data/` XML.
//  See Resources/Catalog/NOTICE.txt.
//

import Foundation

public enum ChummerCatalogLoader {
    /// Resource stem for an edition’s bundled catalog (without `.json`).
    public static func bundledResourceName(for edition: Edition) -> String {
        switch edition {
        case .sr4: "sr4_catalog"
        case .sr5: "sr5_catalog"
        case .sr6: "sr6_catalog"
        }
    }

    public static func resolvedExternalDataDirectory(
        override: String? = CatalogSettings.chummerDataPath
    ) -> URL? {
        guard let override, !override.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Load catalog for the app. Prefers the **bundled** JSON for `edition`
    /// unless the user enables an external Chummer data folder override (SR5 XML).
    public static func load(edition: Edition = .sr5) -> CatalogLoadResult {
        // External Chummer XML is SR5-oriented; only use when requesting SR5/SR6.
        if edition != .sr4,
           CatalogSettings.preferExternalCatalog,
           let dir = resolvedExternalDataDirectory() {
            let external = loadFromChummerXML(directory: dir)
            if !external.entries.isEmpty {
                return external
            }
        }
        return loadBundledJSON(edition: edition)
    }

    // MARK: - Bundled JSON

    private static func loadBundledJSON(edition: Edition) -> CatalogLoadResult {
        let primary = bundledResourceName(for: edition)
        let fallback = edition == .sr4 ? "sr5_catalog" : primary
        let names = primary == fallback ? [primary] : [primary, fallback]

        var lastError: String?
        for name in names {
            if let result = tryLoadBundled(resourceName: name) {
                if name != primary {
                    var r = result
                    r.errors.append(
                        "Preferred catalog \(primary).json missing; loaded \(name).json."
                    )
                    return r
                }
                return result
            }
            lastError = "Bundled catalog (\(name).json) not found or failed to decode."
        }

        return CatalogLoadResult(
            entries: [],
            sourceDirectory: nil,
            loadedFiles: [],
            errors: [lastError ?? "Bundled catalog not found in app resources."]
        )
    }

    private static func tryLoadBundled(resourceName: String) -> CatalogLoadResult? {
        // Bundle only — never probe source-tree paths (repo on Desktop triggers TCC).
        let candidates: [URL?] = [
            Bundle.main.url(forResource: resourceName, withExtension: "json", subdirectory: "Catalog"),
            Bundle.main.url(forResource: resourceName, withExtension: "json")
        ]

        guard let url = candidates.compactMap({ $0 }).first else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(BundledCatalogFile.self, from: data)
            let entries = decoded.entries.map { $0.asCatalogEntry() }
            return CatalogLoadResult(
                entries: entries,
                sourceDirectory: url.deletingLastPathComponent(),
                loadedFiles: ["Bundled \(resourceName).json (\(entries.count) entries)"],
                errors: []
            )
        } catch {
            return CatalogLoadResult(
                entries: [],
                sourceDirectory: url.deletingLastPathComponent(),
                loadedFiles: [],
                errors: ["Failed to load \(resourceName).json: \(error.localizedDescription)"]
            )
        }
    }

    // MARK: - External XML (optional developer path)

    private static func loadFromChummerXML(directory dir: URL) -> CatalogLoadResult {
        var entries: [CatalogEntry] = []
        var loaded: [String] = []
        var errors: [String] = []

        func loadFile(_ name: String, _ parse: (XMLElement) -> [CatalogEntry]) {
            let url = dir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                let data = try Data(contentsOf: url)
                let doc = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
                guard let root = doc.rootElement() else {
                    errors.append("\(name): empty root")
                    return
                }
                let parsed = parse(root)
                entries.append(contentsOf: parsed)
                loaded.append("\(name) (\(parsed.count))")
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }

        loadFile("weapons.xml") { root in
            parseNamedItems(root, element: "weapon", kind: .weapon) { el, base in
                var entry = base
                entry.damage = child(el, "damage")
                entry.modifiers = BonusParser.parse(el)
                return entry
            }
        }
        loadFile("armor.xml") { root in
            parseNamedItems(root, element: "armor", kind: .armor) { el, base in
                var entry = base
                if let a = Int(child(el, "armor")) { entry.armorRating = a }
                entry.modifiers = BonusParser.parse(el)
                return entry
            }
        }
        loadFile("gear.xml") { root in
            parseNamedItems(root, element: "gear", kind: .gear) { el, base in
                var entry = base
                entry.modifiers = BonusParser.parse(el)
                return entry
            }
        }
        loadFile("cyberware.xml") { root in
            parseNamedItems(root, element: "cyberware", kind: .cyberware) { el, base in
                var entry = base
                let ess = child(el, "ess")
                entry.essenceText = ess.isEmpty ? nil : ess
                entry.modifiers = BonusParser.parse(el)
                return entry
            }
        }
        loadFile("bioware.xml") { root in
            parseNamedItems(root, element: "bioware", kind: .bioware) { el, base in
                var entry = base
                let ess = child(el, "ess")
                entry.essenceText = ess.isEmpty ? nil : ess
                entry.modifiers = BonusParser.parse(el)
                return entry
            }
        }
        loadFile("qualities.xml") { root in
            parseNamedItems(root, element: "quality", kind: .quality) { el, base in
                var entry = base
                entry.karma = Int(child(el, "karma"))
                entry.modifiers = BonusParser.parse(el)
                return entry
            }
        }
        loadFile("powers.xml") { root in
            parseNamedItems(root, element: "power", kind: .adeptPower) { el, base in
                var entry = base
                let pts = child(el, "points")
                if !pts.isEmpty { entry.notes = "PP \(pts)" }
                let action = child(el, "action")
                entry.category = action.isEmpty ? "Adept Power" : action
                entry.modifiers = BonusParser.parse(el)
                return entry
            }
        }
        loadFile("contacts.xml") { root in
            let nodes = root.elements(forName: "contacts").first?.elements(forName: "contact")
                ?? root.elements(forName: "contact")
            return nodes.compactMap { el -> CatalogEntry? in
                let name = el.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { return nil }
                return CatalogEntry(
                    id: "contactrole:\(name)",
                    kind: .contactRole,
                    name: name,
                    category: "Role"
                )
            }
        }

        entries.sort {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return CatalogLoadResult(
            entries: entries,
            sourceDirectory: dir,
            loadedFiles: loaded.map { "External \($0)" },
            errors: errors
        )
    }

    private static func parseNamedItems(
        _ root: XMLElement,
        element: String,
        kind: CatalogKind,
        enrich: ((XMLElement, CatalogEntry) -> CatalogEntry)? = nil
    ) -> [CatalogEntry] {
        var nodes = root.elements(forName: element)
        if nodes.isEmpty {
            for childNode in root.children ?? [] {
                guard let el = childNode as? XMLElement else { continue }
                nodes.append(contentsOf: el.elements(forName: element))
            }
        }

        return nodes.compactMap { el -> CatalogEntry? in
            let name = child(el, "name")
            guard !name.isEmpty else { return nil }
            let id = child(el, "id")
            let category = child(el, "category")
            let costText = child(el, "cost")
            var entry = CatalogEntry(
                id: id.isEmpty ? "\(kind.rawValue):\(name)" : id,
                kind: kind,
                name: name,
                category: category,
                costText: costText,
                costNuyen: parseFixedNuyen(costText),
                availability: child(el, "avail"),
                source: child(el, "source"),
                page: child(el, "page")
            )
            if let enrich {
                entry = enrich(el, entry)
            }
            return entry
        }
    }

    private static func child(_ el: XMLElement, _ name: String) -> String {
        el.elements(forName: name).first?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static func parseFixedNuyen(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.contains("*") || t.contains("+") || t.contains("-") || t.contains("/")
            || t.rangeOfCharacter(from: .letters) != nil {
            if t.allSatisfy({ $0.isNumber || $0 == "," }) {
                return Int(t.replacingOccurrences(of: ",", with: ""))
            }
            return nil
        }
        return Int(t.replacingOccurrences(of: ",", with: ""))
    }
}

// MARK: - Bundled JSON DTO

private struct BundledCatalogFile: Decodable {
    var entries: [BundledEntry]
}

private struct BundledEntry: Decodable {
    var id: String
    var kind: String
    var name: String
    var category: String?
    var costText: String?
    var costNuyen: Int?
    var availability: String?
    var source: String?
    var page: String?
    var essenceText: String?
    var karma: Int?
    var damage: String?
    var armorRating: Int?
    var notes: String?
    var modifiers: [BundledModifier]?

    func asCatalogEntry() -> CatalogEntry {
        CatalogEntry(
            id: id,
            kind: CatalogKind(rawValue: kind) ?? .gear,
            name: name,
            category: category ?? "",
            costText: costText ?? "",
            costNuyen: costNuyen,
            availability: availability ?? "",
            source: source ?? "",
            page: page ?? "",
            essenceText: essenceText,
            karma: karma,
            damage: damage,
            armorRating: armorRating,
            notes: notes ?? "",
            modifiers: (modifiers ?? []).compactMap(\.asStatModifier)
        )
    }
}

private struct BundledModifier: Decodable {
    var target: String
    var amount: Int
    var usesRating: Bool?
    var ratingOffset: Int?
    var ratingTable: [Int]?
    var skillKey: String?
    var condition: String?

    var asStatModifier: StatModifier? {
        guard let target = ModifierTarget(rawValue: target) else { return nil }
        return StatModifier(
            target: target,
            amount: amount,
            usesRating: usesRating ?? false,
            ratingOffset: ratingOffset ?? 0,
            ratingTable: ratingTable,
            skillKey: skillKey,
            condition: condition
        )
    }
}

// MARK: - Chummer bonus XML → StatModifier

enum BonusParser {
    /// Extract play-sheet modifiers from a Chummer item element's `<bonus>` child.
    static func parse(_ el: XMLElement) -> [StatModifier] {
        guard let bonus = el.elements(forName: "bonus").first else { return [] }
        var out: [StatModifier] = []

        for sa in bonus.elements(forName: "specificattribute") {
            let name = text(sa, "name")
            guard let target = ModifierTarget.fromChummerAttribute(name) else { continue }
            if let parsed = parseAmount(text(sa, "val")) {
                out.append(parsed.asModifier(target: target))
            }
        }

        for ss in bonus.elements(forName: "specificskill") {
            let skill = text(ss, "name")
            guard !skill.isEmpty else { continue }
            if let parsed = parseAmount(text(ss, "bonus")) {
                out.append(parsed.asModifier(target: .skill, skillKey: skill))
            }
        }

        for armorEl in bonus.elements(forName: "armor") {
            let raw = armorEl.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let parsed = parseAmount(raw) {
                out.append(parsed.asModifier(target: .armor))
            }
        }

        // SR5 initiative passes ≈ initiative dice.
        for pass in bonus.elements(forName: "initiativepass") {
            let raw = pass.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let parsed = parseAmount(raw) {
                out.append(parsed.asModifier(target: .initiativeDice))
            }
        }

        for initEl in bonus.elements(forName: "initiative") {
            let raw = initEl.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let parsed = parseAmount(raw) {
                out.append(parsed.asModifier(target: .initiative))
            }
        }

        for lim in bonus.elements(forName: "limitmodifier") {
            let limit = text(lim, "limit").lowercased()
            let target: ModifierTarget?
            switch limit {
            case "physical": target = .physicalLimit
            case "mental": target = .mentalLimit
            case "social": target = .socialLimit
            default: target = nil
            }
            guard let target else { continue }
            if let parsed = parseAmount(text(lim, "value")) {
                let cond = text(lim, "condition")
                out.append(
                    parsed.asModifier(
                        target: target,
                        condition: cond.isEmpty ? nil : cond
                    )
                )
            }
        }

        return out
    }

    private static func text(_ el: XMLElement, _ name: String) -> String {
        el.elements(forName: name).first?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Parsed Chummer amount: either fixed, rating-scaled, or FixedValues table.
    struct ParsedAmount: Sendable {
        var amount: Int
        var usesRating: Bool
        var ratingOffset: Int
        var ratingTable: [Int]?

        static func fixed(_ n: Int) -> Self {
            Self(amount: n, usesRating: false, ratingOffset: 0, ratingTable: nil)
        }

        static func rating(coefficient: Int = 1, offset: Int = 0) -> Self {
            Self(amount: coefficient, usesRating: true, ratingOffset: offset, ratingTable: nil)
        }

        static func table(_ values: [Int]) -> Self {
            Self(amount: values.first ?? 0, usesRating: false, ratingOffset: 0, ratingTable: values)
        }

        func asModifier(
            target: ModifierTarget,
            skillKey: String? = nil,
            condition: String? = nil
        ) -> StatModifier {
            StatModifier(
                target: target,
                amount: amount,
                usesRating: usesRating,
                ratingOffset: ratingOffset,
                ratingTable: ratingTable,
                skillKey: skillKey,
                condition: condition
            )
        }
    }

    /// Parse Chummer val/bonus strings:
    /// `"Rating"`, `"2"`, `"-1"`, `"Rating-1"`, `"-Rating"`, `"Rating*2"`, `"FixedValues(3,6,9)"`.
    static func parseAmount(_ raw: String) -> ParsedAmount? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        // FixedValues(a,b,c) — rating-indexed table (1-based).
        if let table = parseFixedValues(t) {
            return .table(table)
        }

        // Skip other complex XPath-ish expressions.
        if t.contains("{") || t.localizedCaseInsensitiveContains("number(") {
            return nil
        }

        if t.compare("Rating", options: .caseInsensitive) == .orderedSame {
            return .rating(coefficient: 1)
        }
        if t.compare("-Rating", options: .caseInsensitive) == .orderedSame {
            return .rating(coefficient: -1)
        }

        // Rating*N / Rating * N
        if let match = t.range(
            of: #"^Rating\s*\*\s*(-?\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let digits = String(t[match])
                .replacingOccurrences(of: "Rating", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let n = Int(digits) { return .rating(coefficient: n) }
        }

        // Rating+N / Rating-N
        if let match = t.range(
            of: #"^Rating\s*([+-]\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let digits = String(t[match])
                .replacingOccurrences(of: "Rating", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            if let n = Int(digits) { return .rating(coefficient: 1, offset: n) }
        }

        if let n = Int(t) {
            return .fixed(n)
        }
        return nil
    }

    /// `FixedValues(3,6,9)` → [3,6,9]
    static func parseFixedValues(_ raw: String) -> [Int]? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = t.range(of: "FixedValues(", options: .caseInsensitive),
              let close = t.range(of: ")", options: [], range: open.upperBound..<t.endIndex)
        else { return nil }
        let inner = t[open.upperBound..<close.lowerBound]
        let parts = inner.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let nums = parts.compactMap { Int($0) }
        guard nums.count == parts.count, !nums.isEmpty else { return nil }
        return nums
    }
}

// MARK: - Settings

public enum CatalogSettings {
    /// Optional external Chummer `data/` path (developers only).
    public static var chummerDataPath: String? {
        get {
            let s = AppPreferences.string(.chummerDataPath)
            return (s?.isEmpty == false) ? s : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                AppPreferences.set(newValue, for: .chummerDataPath)
            } else {
                AppPreferences.remove(.chummerDataPath)
            }
        }
    }

    /// When true and an external path is set, load XML from disk instead of the bundle.
    public static var preferExternalCatalog: Bool {
        get { AppPreferences.bool(.preferExternalChummerCatalog) }
        set { AppPreferences.set(newValue, for: .preferExternalChummerCatalog) }
    }
}

/// Process-wide shared catalog entries, keyed by edition.
/// Thread-safe; filled on first access per edition or via `CatalogStore.reload()`.
enum CatalogCache {
    private static let lock = NSLock()
    /// Guarded by `lock`; marked unsafe for Swift 6 global-state rules.
    nonisolated(unsafe) private static var cache: [Edition: CatalogLoadResult] = [:]

    static func loadResult(edition: Edition = .sr5) -> CatalogLoadResult {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[edition] { return hit }
        let loaded = ChummerCatalogLoader.load(edition: edition)
        cache[edition] = loaded
        return loaded
    }

    static func entries(edition: Edition = .sr5) -> [CatalogEntry] {
        loadResult(edition: edition).entries
    }

    /// Replace cache for one edition after an explicit reload.
    static func replace(edition: Edition, with result: CatalogLoadResult) {
        lock.lock()
        defer { lock.unlock() }
        cache[edition] = result
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

/// Per-edition catalog load summary for Settings (SR4 → SR6).
public struct CatalogEditionSummary: Sendable, Identifiable, Equatable {
    public var id: Edition { edition }
    public var edition: Edition
    public var entryCount: Int
    /// Human-readable lines such as `Bundled sr5_catalog.json (4197 entries)`.
    public var loadedFiles: [String]
    public var errors: [String]

    public init(edition: Edition, result: CatalogLoadResult) {
        self.edition = edition
        self.entryCount = result.entries.count
        self.loadedFiles = result.loadedFiles
        self.errors = result.errors
    }
}

/// Process-wide cached catalog for SwiftUI (lazy — no decode at app launch).
@MainActor
public final class CatalogStore: ObservableObject {
    public static let shared = CatalogStore()

    @Published public private(set) var edition: Edition = .sr5
    @Published public private(set) var result: CatalogLoadResult = .init(
        entries: [],
        sourceDirectory: nil,
        loadedFiles: [],
        errors: []
    )
    @Published public private(set) var isLoaded = false
    /// Bundled (or override) stats for every edition, ascending SR4 → SR6.
    @Published public private(set) var editionSummaries: [CatalogEditionSummary] = []

    /// Sum of entry counts across all editions currently summarized.
    public var totalEntriesAcrossEditions: Int {
        editionSummaries.reduce(0) { $0 + $1.entryCount }
    }

    private init() {
        // Intentionally empty: decode on first browser/settings access, not at launch.
    }

    /// Load catalog if needed for the current edition (idempotent).
    public func ensureLoaded(for edition: Edition = .sr5) {
        if isLoaded, self.edition == edition, !editionSummaries.isEmpty { return }
        reload(for: edition)
    }

    public func reload(for edition: Edition = .sr5) {
        // Always refresh all edition bundles so Settings can show SR4/SR5/SR6 totals.
        refreshAllEditionSummaries()
        let loaded = CatalogCache.loadResult(edition: edition)
        self.edition = edition
        result = loaded
        isLoaded = true
    }

    /// Settings / default reload keeps the active edition and refreshes all bundles.
    public func reload() {
        reload(for: edition)
    }

    /// Load every edition into the cache and rebuild ordered summaries (SR4, SR5, SR6).
    public func refreshAllEditionSummaries() {
        var rows: [CatalogEditionSummary] = []
        for ed in Edition.allCases {
            let loaded = ChummerCatalogLoader.load(edition: ed)
            CatalogCache.replace(edition: ed, with: loaded)
            rows.append(CatalogEditionSummary(edition: ed, result: loaded))
        }
        editionSummaries = rows
    }

    public func entries(
        kinds: Set<CatalogKind>,
        query: String,
        edition: Edition? = nil,
        matching: ((CatalogEntry) -> Bool)? = nil
    ) -> [CatalogEntry] {
        let ed = edition ?? self.edition
        ensureLoaded(for: ed)
        var scoped = result.entries.filter { kinds.contains($0.kind) }
        if let matching {
            scoped = scoped.filter(matching)
        }
        return CatalogSearch.filter(scoped, query: query)
    }

    /// Case-insensitive exact name match (first hit). Used when attaching catalog mods on import.
    public func entry(named name: String, edition: Edition? = nil) -> CatalogEntry? {
        let ed = edition ?? self.edition
        ensureLoaded(for: ed)
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return result.entries.first { $0.name.lowercased() == key }
    }

    public func modifiers(named name: String, edition: Edition? = nil) -> [StatModifier] {
        entry(named: name, edition: edition)?.modifiers ?? []
    }
}

/// Non-UI catalog lookup for import / rules (shares `CatalogCache` with `CatalogStore`).
public enum CatalogLookup {
    public static func allEntries(edition: Edition = .sr5) -> [CatalogEntry] {
        CatalogCache.entries(edition: edition)
    }

    public static func entry(named name: String, edition: Edition = .sr5) -> CatalogEntry? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return allEntries(edition: edition).first { $0.name.lowercased() == key }
    }

    public static func modifiers(named name: String, edition: Edition = .sr5) -> [StatModifier] {
        // Fresh UUIDs so each instance is independently identifiable.
        (entry(named: name, edition: edition)?.modifiers ?? []).map {
            StatModifier(
                target: $0.target,
                amount: $0.amount,
                usesRating: $0.usesRating,
                ratingOffset: $0.ratingOffset,
                ratingTable: $0.ratingTable,
                skillKey: $0.skillKey,
                condition: $0.condition
            )
        }
    }

    /// Clear cached entries (e.g. after regenerating the bundled catalog in tests).
    public static func resetCache() {
        CatalogCache.reset()
    }
}
