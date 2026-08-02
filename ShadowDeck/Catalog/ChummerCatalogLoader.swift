//
//  ChummerCatalogLoader.swift
//  ShadowDeck
//
//  Primary: load bundled `sr5_catalog.json` shipped with the app (derived from
//  Chummer5a GPL data — see Resources/Catalog/NOTICE.txt).
//  Optional: developer override to load live Chummer `data/` XML.
//

import Foundation

public enum ChummerCatalogLoader {
    public static func resolvedExternalDataDirectory(
        override: String? = CatalogSettings.chummerDataPath
    ) -> URL? {
        guard let override, !override.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Load catalog for the app. Prefers the **bundled** JSON unless the user
    /// explicitly enables an external Chummer data folder override.
    public static func load() -> CatalogLoadResult {
        if CatalogSettings.preferExternalCatalog,
           let dir = resolvedExternalDataDirectory()
        {
            let external = loadFromChummerXML(directory: dir)
            if !external.entries.isEmpty {
                return external
            }
        }
        return loadBundledJSON()
    }

    // MARK: - Bundled JSON

    private static func loadBundledJSON() -> CatalogLoadResult {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "sr5_catalog", withExtension: "json", subdirectory: "Catalog"),
            Bundle.main.url(forResource: "sr5_catalog", withExtension: "json"),
            // Source-tree fallback (unit tests / unbundled runs)
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Catalog/
                .deletingLastPathComponent() // ShadowDeck/
                .appendingPathComponent("Resources/Catalog/sr5_catalog.json"),
        ]

        guard let url = candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            return CatalogLoadResult(
                entries: [],
                sourceDirectory: nil,
                loadedFiles: [],
                errors: ["Bundled catalog (sr5_catalog.json) not found in app resources."]
            )
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(BundledCatalogFile.self, from: data)
            let entries = decoded.entries.map { $0.asCatalogEntry() }
            return CatalogLoadResult(
                entries: entries,
                sourceDirectory: url.deletingLastPathComponent(),
                loadedFiles: ["Bundled sr5_catalog.json (\(entries.count) entries)"],
                errors: []
            )
        } catch {
            return CatalogLoadResult(
                entries: [],
                sourceDirectory: url.deletingLastPathComponent(),
                loadedFiles: [],
                errors: ["Failed to load bundled catalog: \(error.localizedDescription)"]
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
                var e = base
                e.damage = child(el, "damage")
                e.modifiers = BonusParser.parse(el)
                return e
            }
        }
        loadFile("armor.xml") { root in
            parseNamedItems(root, element: "armor", kind: .armor) { el, base in
                var e = base
                if let a = Int(child(el, "armor")) { e.armorRating = a }
                e.modifiers = BonusParser.parse(el)
                return e
            }
        }
        loadFile("gear.xml") { root in
            parseNamedItems(root, element: "gear", kind: .gear) { el, base in
                var e = base
                e.modifiers = BonusParser.parse(el)
                return e
            }
        }
        loadFile("cyberware.xml") { root in
            parseNamedItems(root, element: "cyberware", kind: .cyberware) { el, base in
                var e = base
                let ess = child(el, "ess")
                e.essenceText = ess.isEmpty ? nil : ess
                e.modifiers = BonusParser.parse(el)
                return e
            }
        }
        loadFile("bioware.xml") { root in
            parseNamedItems(root, element: "bioware", kind: .bioware) { el, base in
                var e = base
                let ess = child(el, "ess")
                e.essenceText = ess.isEmpty ? nil : ess
                e.modifiers = BonusParser.parse(el)
                return e
            }
        }
        loadFile("qualities.xml") { root in
            parseNamedItems(root, element: "quality", kind: .quality) { el, base in
                var e = base
                e.karma = Int(child(el, "karma"))
                e.modifiers = BonusParser.parse(el)
                return e
            }
        }
        loadFile("powers.xml") { root in
            parseNamedItems(root, element: "power", kind: .adeptPower) { el, base in
                var e = base
                let pts = child(el, "points")
                if !pts.isEmpty { e.notes = "PP \(pts)" }
                let action = child(el, "action")
                e.category = action.isEmpty ? "Adept Power" : action
                e.modifiers = BonusParser.parse(el)
                return e
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
            || t.rangeOfCharacter(from: .letters) != nil
        {
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

        static func fixed(_ n: Int) -> ParsedAmount {
            ParsedAmount(amount: n, usesRating: false, ratingOffset: 0, ratingTable: nil)
        }

        static func rating(coefficient: Int = 1, offset: Int = 0) -> ParsedAmount {
            ParsedAmount(amount: coefficient, usesRating: true, ratingOffset: offset, ratingTable: nil)
        }

        static func table(_ values: [Int]) -> ParsedAmount {
            ParsedAmount(amount: values.first ?? 0, usesRating: false, ratingOffset: 0, ratingTable: values)
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
        if let m = t.range(
            of: #"^Rating\s*\*\s*(-?\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let digits = String(t[m])
                .replacingOccurrences(of: "Rating", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let n = Int(digits) { return .rating(coefficient: n) }
        }

        // Rating+N / Rating-N
        if let m = t.range(
            of: #"^Rating\s*([+-]\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let digits = String(t[m])
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

/// Process-wide shared catalog entries (single load path for UI + import).
/// Thread-safe; filled once on first access or via `CatalogStore.reload()`.
enum CatalogCache {
    private static let lock = NSLock()
    /// Guarded by `lock`; marked unsafe for Swift 6 global-state rules.
    nonisolated(unsafe) private static var cachedEntries: [CatalogEntry]?
    nonisolated(unsafe) private static var cachedResult: CatalogLoadResult?

    static func loadResult() -> CatalogLoadResult {
        lock.lock()
        defer { lock.unlock() }
        if let cachedResult { return cachedResult }
        let loaded = ChummerCatalogLoader.load()
        cachedResult = loaded
        cachedEntries = loaded.entries
        return loaded
    }

    static func entries() -> [CatalogEntry] {
        loadResult().entries
    }

    /// Replace cache after an explicit reload (Settings → refresh catalog).
    static func replace(with result: CatalogLoadResult) {
        lock.lock()
        defer { lock.unlock() }
        cachedResult = result
        cachedEntries = result.entries
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        cachedEntries = nil
        cachedResult = nil
    }
}

/// Process-wide cached catalog for SwiftUI (lazy — no decode at app launch).
@MainActor
public final class CatalogStore: ObservableObject {
    public static let shared = CatalogStore()

    @Published public private(set) var result: CatalogLoadResult = .init(
        entries: [],
        sourceDirectory: nil,
        loadedFiles: [],
        errors: []
    )
    @Published public private(set) var isLoaded = false

    private init() {
        // Intentionally empty: decode on first browser/settings access, not at launch.
    }

    /// Load catalog if needed (idempotent). Call from Catalog browser / Settings appear.
    public func ensureLoaded() {
        guard !isLoaded else { return }
        reload()
    }

    public func reload() {
        let loaded = ChummerCatalogLoader.load()
        CatalogCache.replace(with: loaded)
        result = loaded
        isLoaded = true
    }

    public func entries(kinds: Set<CatalogKind>, query: String) -> [CatalogEntry] {
        ensureLoaded()
        let scoped = result.entries.filter { kinds.contains($0.kind) }
        return CatalogSearch.filter(scoped, query: query)
    }

    /// Case-insensitive exact name match (first hit). Used when attaching catalog mods on import.
    public func entry(named name: String) -> CatalogEntry? {
        ensureLoaded()
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return result.entries.first { $0.name.lowercased() == key }
    }

    public func modifiers(named name: String) -> [StatModifier] {
        entry(named: name)?.modifiers ?? []
    }
}

/// Non-UI catalog lookup for import / rules (shares `CatalogCache` with `CatalogStore`).
public enum CatalogLookup {
    public static func allEntries() -> [CatalogEntry] {
        CatalogCache.entries()
    }

    public static func entry(named name: String) -> CatalogEntry? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return allEntries().first { $0.name.lowercased() == key }
    }

    public static func modifiers(named name: String) -> [StatModifier] {
        // Fresh UUIDs so each instance is independently identifiable.
        (entry(named: name)?.modifiers ?? []).map {
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
