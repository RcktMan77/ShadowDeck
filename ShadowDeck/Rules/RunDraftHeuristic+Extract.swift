//
//  RunDraftHeuristic+Extract.swift
//  ShadowDeck
//
//  Field extractors for a mission draft. Same type as RunDraftHeuristic.
//
import Foundation

extension RunDraftHeuristic {
    // MARK: - Field extractors

    static func extractMissionCode(from text: String) -> String? {
        // SRM 5A-01, SRM 05-05, SRM 5A–01 (en dash)
        let patterns = [
            #"SRM\s*\d+[A-Za-z]?\s*[-–—]?\s*\d+[A-Za-z]?"#,
            #"SRM\s+\d+[A-Za-z]?-\d+"#
        ]
        for p in patterns {
            if let r = text.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                var code = String(text[r])
                code = code
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "–", with: "-")
                    .replacingOccurrences(of: "—", with: "-")
                    .trimmingCharacters(in: .whitespaces)
                // Normalize "SRM 5A-01"
                if let m = code.range(
                    of: #"SRM\s*(\d+[A-Za-z]?)\s*-?\s*(\d+)"#,
                    options: [.regularExpression, .caseInsensitive]
                ) {
                    let raw = String(code[m])
                    let parts = raw
                        .uppercased()
                        .replacingOccurrences(of: "SRM", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .split { !$0.isLetter && !$0.isNumber }
                        .map(String.init)
                    if parts.count >= 2 {
                        return "SRM \(parts[0])-\(parts[1])"
                    }
                }
                return code
            }
        }
        return nil
    }

    static func extractTitle(cleaned: String, code: String?, fallback: String) -> String {
        // Prefer "SRM 5A-01: Chasin' the Wind"
        if let r = cleaned.range(
            of: #"SRM\s*\d+[A-Za-z]?[-–—]?\d+\s*:\s*[^\n]{3,80}"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            var line = String(cleaned[r])
            line = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            // Often continues with "is a Shadowrun Missions" — cut at that.
            if let cut = line.range(of: #"\s+is\s+a\s+Shadowrun"#, options: [.regularExpression, .caseInsensitive]) {
                line = String(line[..<cut.lowerBound])
            }
            if let cut = line.range(of: #"\s+is\s+intended"#, options: [.regularExpression, .caseInsensitive]) {
                line = String(line[..<cut.lowerBound])
            }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Scene 1 titles sometimes carry the adventure name in the header area.
        if let code {
            // "SRM 5A-01" alone → use fallback with code
            let base = fallback
                .replacingOccurrences(of: #"\.pdf$"#, with: "", options: .regularExpression)
            if base.localizedCaseInsensitiveContains(code.replacingOccurrences(of: "SRM ", with: ""))
                || base.count > 8 {
                return base
            }
            return "\(code): \(base)"
        }
        return fallback
    }

    static func extractClient(from cleaned: String, tell: String, behind: String) -> String {
        let pool = [tell, behind, cleaned].joined(separator: "\n")
        // "know me as Quantum Princess" / "Mr. Johnson" named
        if let r = pool.range(
            of: #"know me as\s+([A-Z][A-Za-z0-9'’\-]+(?:\s+[A-Z][A-Za-z0-9'’\-]+)?)"#,
            options: .regularExpression
        ) {
            let s = String(pool[r])
            if let asRange = s.range(of: "as ", options: .caseInsensitive) {
                return String(s[asRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        // "hired by X" / "job from X"
        let hirePatterns = [
            #"hired by\s+([A-Z][A-Za-z0-9'’\-]+(?:\s+[A-Z][A-Za-z0-9'’\-]+)?)"#,
            #"job from\s+([A-Z][A-Za-z0-9'’\-]+(?:\s+[A-Z][A-Za-z0-9'’\-]+)?)"#,
            #"contacted by\s+(?:a\s+frantic\s+)?([A-Z][A-Za-z0-9'’\-]+)"#,
            #"Ms\.\s*Johnson"#,
            #"Mr\.\s*Johnson"#,
            #"meet with\s+([A-Z][A-Za-z0-9'’\-]+)"#
        ]
        for p in hirePatterns {
            if let r = pool.range(of: p, options: .regularExpression) {
                let s = String(pool[r])
                if s.localizedCaseInsensitiveContains("johnson") {
                    // Prefer a proper name nearby if "Ms. Johnson is already there. She is ..."
                    return s.trimmingCharacters(in: .whitespaces)
                }
                if let last = s.split(separator: " ").last.map(String.init) {
                    // Avoid generic verbs
                    if !["the", "a", "an"].contains(last.lowercased()) {
                        // Extract capture more carefully
                        if s.lowercased().hasPrefix("hired by") {
                            return String(s.dropFirst("hired by".count)).trimmingCharacters(in: .whitespaces)
                        }
                        if s.lowercased().hasPrefix("job from") {
                            return String(s.dropFirst("job from".count)).trimmingCharacters(in: .whitespaces)
                        }
                        if s.lowercased().contains("contacted by") {
                            return last
                        }
                        if s.lowercased().hasPrefix("meet with") {
                            return String(s.dropFirst("meet with".count)).trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
                return s
            }
        }
        // Sid as Johnson pattern
        if pool.localizedCaseInsensitiveContains("sid is looking to make a name")
            || pool.range(of: #"\bSid\b.*\bJohnson\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "Sid"
        }
        return ""
    }

    static func extractLocation(from text: String) -> String {
        let lower = text.lowercased()
        var parts: [String] = []
        if lower.contains("containment zone") || lower.contains(" the cz") || lower.contains("in the cz") {
            parts.append("Chicago Containment Zone")
        } else if lower.contains("chicago") {
            parts.append("Chicago")
        }
        if lower.contains("seattle") { parts.append("Seattle") }
        if lower.contains("denver") { parts.append("Denver") }
        if lower.contains("neo-tokyo") || lower.contains("neo tokyo") { parts.append("Neo-Tokyo") }

        // Named meet site from Scene 1.
        if let r = text.range(
            of: #"(?:reserved at|meet(?:ing)? at|table reserved at)\s+([A-Z][^.\n]{3,60})"#,
            options: .regularExpression
        ) {
            var site = String(text[r])
            if let at = site.range(of: " at ", options: .caseInsensitive) {
                site = String(site[at.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Cut trailing clause
                if let comma = site.firstIndex(of: ".") {
                    site = String(site[..<comma])
                }
                if site.count > 3, site.count < 80 {
                    parts.append(site)
                }
            }
        }

        // De-dupe preserving order.
        var seen = Set<String>()
        let unique = parts.filter {
            let k = $0.lowercased()
            if seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
        return unique.joined(separator: " · ")
    }

    static func extractObjectives(
        scanBlocks: [String],
        synopsis: String,
        cleaned: String
    ) -> [String] {
        var objectives: [String] = []

        // Scan This blocks are short GM summaries of scene goals — best objective source.
        for block in scanBlocks.prefix(8) {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 24 else { continue }
            // First 1–2 sentences.
            let sentence = firstSentences(trimmed, max: 2, maxChars: 320)
            if sentence.count >= 20 {
                objectives.append(sentence)
            }
        }

        // "hire the runners to X" / "wants the runners to X"
        if let regex = try? NSRegularExpression(
            pattern: #"(?:hire[sd]?|wants?|need(?:s)?|ask(?:s|ing)?)\s+(?:the\s+)?runners\s+to\s+([^.]{10,180})"#,
            options: .caseInsensitive
        ) {
            let ns = cleaned as NSString
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
            for m in matches.prefix(6) {
                guard m.numberOfRanges >= 2 else { continue }
                var goal = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard goal.count >= 10 else { continue }
                if !goal.hasPrefix("To ") && !goal.hasPrefix("to ") {
                    goal = "To " + goal
                } else if goal.hasPrefix("to ") {
                    goal = "To " + goal.dropFirst(3)
                }
                objectives.append(String(goal.prefix(280)))
            }
        }

        // Bullet / numbered lists.
        for line in cleaned.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.range(of: #"^[•\-\*]\s+\S.{8,}"#, options: .regularExpression) != nil
                || t.range(of: #"^\d+[\.\)]\s+\S.{8,}"#, options: .regularExpression) != nil {
                var cleanedLine = t.replacingOccurrences(
                    of: #"^[•\-\*\d\.\)\s]+"#,
                    with: "",
                    options: .regularExpression
                )
                cleanedLine = cleanedLine.trimmingCharacters(in: .whitespaces)
                // Skip reward bullets
                let lower = cleanedLine.lowercased()
                if lower.contains("nuyen") && lower.contains("net hit") { continue }
                if lower.hasPrefix("karma") || lower.contains("street cred") { continue }
                if cleanedLine.count >= 12, cleanedLine.count <= 280 {
                    objectives.append(cleanedLine)
                }
            }
            if objectives.count >= 16 { break }
        }

        return dedupe(objectives).prefix(12).map { String($0) }
    }

    static func extractRisks(scanBlocks: [String], synopsis: String, behind: String) -> String {
        let pool = (scanBlocks + [synopsis, behind]).joined(separator: "\n\n")
        let keywords = [
            "danger", "risk", "threat", "gang", "go-gang", "security", "patrol",
            "bug", "spirit", "noise", "background count", "containment zone",
            "lone star", "knight errant", "ambush", "hostile", "combat",
            "blackmail", "deadline", "short time", "frantic"
        ]
        var hits: [String] = []
        for para in paragraphs(pool) {
            let lower = para.lowercased()
            guard para.count >= 40, para.count <= 600 else { continue }
            if keywords.contains(where: { lower.contains($0) }) {
                hits.append(para)
            }
            if hits.count >= 8 { break }
        }
        // Prefer scan-this sentences about encounters.
        return dedupe(hits).prefix(6).joined(separator: "\n\n")
    }

    static func extractOpposition(behind: String, synopsis: String, cleaned: String) -> String {
        let pool = [behind, synopsis].joined(separator: "\n\n")
        if pool.count > 80 {
            // Pull sentences with force/security/gang nouns.
            let keywords = [
                "guard", "security", "ganger", "gang", "go-gang", "fleshmonger",
                "spirit", "mage", "samurai", "drone", "knight errant", "lone star",
                "corpsec", "soldier", "thug", "boyz", "horde", "angel"
            ]
            var hits: [String] = []
            for sentence in sentences(pool) {
                let lower = sentence.lowercased()
                if sentence.count < 30 || sentence.count > 400 { continue }
                if keywords.contains(where: { lower.contains($0) }) {
                    hits.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if hits.count >= 8 { break }
            }
            if !hits.isEmpty {
                return dedupe(hits).joined(separator: " ")
            }
            return firstParagraphs(behind.isEmpty ? synopsis : behind, maxChars: 1_200)
        }
        return ""
    }

    struct ReputationExtract {
        var streetCred: Int?
        var notoriety: Int?
        var publicAwareness: Int?
        var notes: String
    }

    /// From Picking Up the Pieces: “+1 Street Cred if…”, etc.
    static func extractReputation(from cleaned: String, pickingUp: String) -> ReputationExtract {
        let pool = pickingUp.isEmpty ? cleaned : pickingUp + "\n" + cleaned
        var notes: [String] = []
        var streetCred: Int?
        var notoriety: Int?
        var publicAwareness: Int?

        // Collect bullet-style reputation lines.
        for line in pool.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            let lower = t.lowercased()
            guard lower.contains("street cred")
                || lower.contains("notoriety")
                || lower.contains("public awareness") else { continue }
            // Skip generic rules blurb.
            if lower.contains("p. 372") || lower.contains("gamemasters should consider") {
                continue
            }
            guard t.range(of: #"[\+\-]?\s*\d+"#, options: .regularExpression) != nil else { continue }

            var cleanedLine = t.replacingOccurrences(
                of: #"^[•\-\*\s]+"#,
                with: "",
                options: .regularExpression
            )
            cleanedLine = prose(cleanedLine)
            if cleanedLine.count < 8 || cleanedLine.count > 280 { continue }
            notes.append(cleanedLine)

            if let n = firstSignedInt(in: cleanedLine) {
                if lower.contains("street cred") {
                    streetCred = max(streetCred ?? n, n)
                } else if lower.contains("notoriety") {
                    notoriety = max(notoriety ?? n, n)
                } else if lower.contains("public awareness") {
                    publicAwareness = max(publicAwareness ?? n, n)
                }
            }
        }

        return ReputationExtract(
            streetCred: streetCred,
            notoriety: notoriety,
            publicAwareness: publicAwareness,
            notes: dedupe(notes).prefix(8).joined(separator: "\n")
        )
    }

    static func firstSignedInt(in text: String) -> Int? {
        guard let r = text.range(of: #"[\+\-]?\d+"#, options: .regularExpression) else { return nil }
        return Int(String(text[r]).replacingOccurrences(of: "+", with: ""))
    }

    static func extractPayout(from cleaned: String, pickingUp: String) -> (Int?, Int?) {
        var nuyen: Int?
        var karma: Int?

        // Prefer explicit adventure totals.
        if let r = cleaned.range(
            of: #"Nuyen Earned:\s*([\d,]+)\s*¥?"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let digits = String(cleaned[r]).filter(\.isNumber)
            if let v = Int(digits), v > 0 { nuyen = v }
        }
        if let r = cleaned.range(
            of: #"Karma Earned:\s*(\d+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let digits = String(cleaned[r]).filter(\.isNumber)
            if let v = Int(digits), v > 0, v < 40 { karma = v }
        }

        // Primary job offer: "4,000 nuyen each" / "offering 4,000 nuyen" / "¥12,000"
        if nuyen == nil {
            let offerPatterns = [
                #"offer(?:s|ing)?\s+(?:the\s+runners\s+)?([\d,]+)\s*nuyen\s+each"#,
                #"([\d,]+)\s*nuyen\s+each"#,
                #"offer(?:s|ing)?\s+([\d,]+)\s*nuyen"#,
                #"pay(?:s|ing)?\s+(?:you\s+)?(?:each\s+)?([\d,]+)\s*nuyen"#,
                #"¥\s*([\d,]+)"#,
                #"([\d,]+)\s*¥"#,
                #"([\d,]+)\s*nuyen"#
            ]
            for p in offerPatterns {
                if let r = cleaned.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                    let digits = String(cleaned[r]).filter(\.isNumber)
                    if let v = Int(digits), v >= 500, v <= 500_000 {
                        nuyen = v
                        break
                    }
                }
            }
        }

        // "maximum adventure award ... is 6" / "4 karma"
        if karma == nil {
            if let r = cleaned.range(
                of: #"maximum adventure award[^\d]{0,40}(\d+)"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let digits = String(cleaned[r]).filter(\.isNumber)
                if let v = Int(digits), v > 0, v < 40 { karma = v }
            }
        }
        if karma == nil {
            if let r = cleaned.range(
                of: #"\b(\d+)\s*karma\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let digits = String(cleaned[r]).filter(\.isNumber)
                if let v = Int(digits), v > 0, v < 40 { karma = v }
            }
        }

        // Scan picking-up block for first money bullet if still empty.
        if nuyen == nil, !pickingUp.isEmpty {
            if let r = pickingUp.range(
                of: #"([\d,]+)\s*nuyen\s+each"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let digits = String(pickingUp[r]).filter(\.isNumber)
                if let v = Int(digits), v >= 500 { nuyen = v }
            }
        }

        return (nuyen, karma)
    }

    // MARK: - Text helpers

    static func paragraphs(_ text: String) -> [String] {
        text
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    static func sentences(_ text: String) -> [String] {
        // Simple split; good enough for heuristic.
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
        var result: [String] = []
        var current = ""
        for ch in normalized {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count > 15 { result.append(t) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count > 15 { result.append(tail) }
        return result
    }

    static func firstSentences(_ text: String, max: Int, maxChars: Int) -> String {
        let parts = sentences(text).prefix(max)
        var out = ""
        for s in parts {
            if out.isEmpty {
                out = s
            } else if out.count + s.count + 1 <= maxChars {
                out += " " + s
            } else {
                break
            }
        }
        if out.isEmpty {
            return String(text.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    static func firstParagraphs(_ text: String, maxChars: Int) -> String {
        var out = ""
        for p in paragraphs(text) {
            if out.isEmpty {
                out = p
            } else if out.count + p.count + 2 <= maxChars {
                out += "\n\n" + p
            } else {
                break
            }
        }
        if out.count > maxChars {
            return String(out.prefix(maxChars))
        }
        return out
    }

    static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter {
            let key = $0.lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if seen.contains(key) { return false }
            // Near-duplicate: prefix match
            if seen.contains(where: { key.hasPrefix($0.prefix(40)) || $0.hasPrefix(key.prefix(40)) }) {
                return false
            }
            seen.insert(key)
            return true
        }
    }}
