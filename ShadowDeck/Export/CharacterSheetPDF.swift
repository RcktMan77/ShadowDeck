//
//  CharacterSheetPDF.swift
//  ShadowDeck
//
//  Rulebook-inspired multi-page character sheets with edition-specific theming,
//  portrait, attribute grids, skill tables, and campaign validation.
//

import AppKit
import CoreText
import Foundation

public enum CharacterSheetPDF {
    public static func render(report: CampaignSheetReport) throws -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let theme = SheetTheme.theme(for: report.character.edition)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw CharacterSheetPDFError.renderFailed
        }

        var media = page
        ctx.beginPage(mediaBox: &media)
        drawPageIdentity(ctx: ctx, page: page, report: report, theme: theme)
        ctx.endPage()

        ctx.beginPage(mediaBox: &media)
        drawPageLoadout(ctx: ctx, page: page, report: report, theme: theme)
        ctx.endPage()

        ctx.closePDF()
        return data as Data
    }

    public static func write(report: CampaignSheetReport, to url: URL) throws {
        try render(report: report).write(to: url, options: .atomic)
    }

    // MARK: - Page 1: Identity & combat readiness

    private static func drawPageIdentity(
        ctx: CGContext,
        page: CGRect,
        report: CampaignSheetReport,
        theme: SheetTheme
    ) {
        let c = report.character
        let eff = report.effects.effectiveAttributes

        drawPageChrome(ctx, page: page, theme: theme, title: theme.sheetTitle)

        // Banner
        let banner = CGRect(x: 28, y: page.maxY - 78, width: page.width - 56, height: 42)
        fillRoundRect(ctx, banner, radius: 6, color: theme.banner)
        drawText(
            ctx,
            theme.editionBadge + "  ·  CHARACTER RECORD",
            x: banner.minX + 14,
            y: banner.midY - 5,
            font: .boldSystemFont(ofSize: 11),
            color: theme.bannerText
        )

        // Portrait panel
        let port = CGRect(x: page.maxX - 28 - 118, y: page.maxY - 230, width: 118, height: 148)
        fillRoundRect(ctx, port.insetBy(dx: -4, dy: -4), radius: 8, color: theme.panelStroke.withAlphaComponent(0.35))
        drawPortrait(ctx, character: c, in: port, theme: theme)

        // Identity block
        var y = page.maxY - 100
        let idMaxX = port.minX - 16
        drawText(ctx, c.displayTitle, x: 36, y: y, font: .boldSystemFont(ofSize: 20), color: theme.ink)
        y -= 18
        let concept = c.concept.isEmpty ? "—" : c.concept
        drawText(ctx, concept, x: 36, y: y, font: .systemFont(ofSize: 11), color: theme.muted)
        y -= 16
        drawText(
            ctx,
            "\(c.metatype.displayName)  ·  \(c.awakened.displayName)  ·  \(c.generation.system.displayName)",
            x: 36,
            y: y,
            font: .systemFont(ofSize: 10),
            color: theme.accent
        )
        y -= 22

        // Vital chips
        let vitals: [(String, String)] = [
            ("NUYEN", "¥\(c.nuyen)"),
            ("KARMA", "\(c.karmaAvailable)/\(c.karmaTotal)"),
            ("ESSENCE", formatEssence(report.derived.currentEssence)),
            ("ARMOR", "\(report.derived.armor)"),
            ("INIT", "\(report.derived.initiativeBase)+\(report.derived.initiativeDice)D6"),
        ]
        var vx: CGFloat = 36
        for (label, value) in vitals {
            let w: CGFloat = 100
            let box = CGRect(x: vx, y: y - 28, width: w, height: 34)
            if box.maxX > idMaxX { break }
            fillRoundRect(ctx, box, radius: 5, color: theme.panel)
            strokeRoundRect(ctx, box, radius: 5, color: theme.panelStroke, width: 0.8)
            drawText(ctx, label, x: box.minX + 8, y: box.maxY - 13, font: .systemFont(ofSize: 7), color: theme.muted)
            drawText(ctx, value, x: box.minX + 8, y: box.minY + 8, font: .boldSystemFont(ofSize: 11), color: theme.ink)
            vx += w + 8
        }
        y -= 48

        // Attribute grid (rulebook style)
        y = min(y, port.minY - 20)
        drawSectionBar(ctx, page: page, y: &y, title: "ATTRIBUTES", theme: theme)
        y -= 6
        let attrs: [(String, Int, Int)] = [
            ("BODY", eff.body, c.attributes.body),
            ("AGILITY", eff.agility, c.attributes.agility),
            ("REACTION", eff.reaction, c.attributes.reaction),
            ("STRENGTH", eff.strength, c.attributes.strength),
            ("WILLPOWER", eff.willpower, c.attributes.willpower),
            ("LOGIC", eff.logic, c.attributes.logic),
            ("INTUITION", eff.intuition, c.attributes.intuition),
            ("CHARISMA", eff.charisma, c.attributes.charisma),
            ("EDGE", eff.edge, c.attributes.edge),
            ("MAGIC", eff.magic, c.attributes.magic),
            ("RESONANCE", eff.resonance, c.attributes.resonance),
        ]
        let cols = 4
        let cellW = (page.width - 72) / CGFloat(cols)
        let cellH: CGFloat = 36
        for (i, row) in attrs.enumerated() {
            let col = i % cols
            let r = i / cols
            let cx = 36 + CGFloat(col) * cellW
            let cy = y - CGFloat(r + 1) * (cellH + 6)
            let box = CGRect(x: cx, y: cy, width: cellW - 8, height: cellH)
            fillRoundRect(ctx, box, radius: 4, color: theme.panel)
            strokeRoundRect(ctx, box, radius: 4, color: theme.accent.withAlphaComponent(0.55), width: 1)
            drawText(ctx, row.0, x: box.minX + 6, y: box.maxY - 12, font: .systemFont(ofSize: 7), color: theme.muted)
            let val = row.1 == row.2 ? "\(row.1)" : "\(row.1)  (\(row.2))"
            drawText(ctx, val, x: box.minX + 6, y: box.minY + 8, font: .boldSystemFont(ofSize: 14), color: theme.ink)
        }
        y -= CGFloat((attrs.count + cols - 1) / cols) * (cellH + 6) + 10

        // Limits / condition / pools strip
        if report.derived.physicalLimit != nil {
            drawSectionBar(ctx, page: page, y: &y, title: "LIMITS", theme: theme)
            y -= 4
            drawKeyRow(ctx, y: &y, items: [
                ("Physical", "\(report.derived.physicalLimit ?? 0)"),
                ("Mental", "\(report.derived.mentalLimit ?? 0)"),
                ("Social", "\(report.derived.socialLimit ?? 0)"),
            ], theme: theme)
            y -= 8
        }

        drawSectionBar(ctx, page: page, y: &y, title: "CONDITION MONITORS", theme: theme)
        y -= 4
        let physBoxes = report.derived.condition.physicalBoxes
        let stunBoxes = report.derived.condition.stunBoxes
        drawText(
            ctx,
            "Physical  \(report.derived.condition.physicalFilled)/\(physBoxes) filled   ·   Stun  \(report.derived.condition.stunFilled)/\(stunBoxes) filled   ·   Overflow \(report.derived.condition.overflowBoxes)",
            x: 40,
            y: y,
            font: .systemFont(ofSize: 10),
            color: theme.ink
        )
        y -= 18

        drawSectionBar(ctx, page: page, y: &y, title: "KEY SKILLS (RANK · POOL)", theme: theme)
        y -= 4
        let skills = c.skills.filter { $0.rating > 0 }.sorted { $0.rating > $1.rating }
        if skills.isEmpty {
            drawText(ctx, "—", x: 40, y: y, font: .systemFont(ofSize: 10), color: theme.muted)
            y -= 14
        } else {
            // Two-column skill table
            let mid = skills.prefix(24)
            let left = Array(mid.prefix((mid.count + 1) / 2))
            let right = Array(mid.suffix(mid.count / 2))
            let startY = y
            var yl = startY
            for skill in left {
                let pool = report.derived.dicePools[skill.catalogKey].map { "\($0)" } ?? "—"
                let tag = skill.category == .active ? "" : " · \(skill.category.rawValue.prefix(4))"
                drawText(
                    ctx,
                    "\(skill.displayName)\(tag)",
                    x: 40,
                    y: yl,
                    font: .systemFont(ofSize: 9),
                    color: theme.ink
                )
                drawText(ctx, "\(skill.rating)  ·  \(pool)", x: 250, y: yl, font: .boldSystemFont(ofSize: 9), color: theme.accent)
                yl -= 12
            }
            var yr = startY
            for skill in right {
                let pool = report.derived.dicePools[skill.catalogKey].map { "\($0)" } ?? "—"
                let tag = skill.category == .active ? "" : " · \(skill.category.rawValue.prefix(4))"
                drawText(
                    ctx,
                    "\(skill.displayName)\(tag)",
                    x: 320,
                    y: yr,
                    font: .systemFont(ofSize: 9),
                    color: theme.ink
                )
                drawText(ctx, "\(skill.rating)  ·  \(pool)", x: 530, y: yr, font: .boldSystemFont(ofSize: 9), color: theme.accent)
                yr -= 12
            }
            y = min(yl, yr) - 8
        }

        drawSectionBar(ctx, page: page, y: &y, title: "VALIDATION", theme: theme)
        y -= 4
        if report.validation.isValid && report.validation.warnings.isEmpty {
            drawText(ctx, "No errors — campaign-ready under ShadowDeck rules + house rules.", x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.accent)
        } else {
            for issue in report.validation.errors.prefix(5) {
                drawText(ctx, "● \(issue.message)", x: 40, y: y, font: .systemFont(ofSize: 8), color: NSColor.systemOrange)
                y -= 11
            }
            for issue in report.validation.warnings.prefix(4) {
                drawText(ctx, "○ \(issue.message)", x: 40, y: y, font: .systemFont(ofSize: 8), color: theme.muted)
                y -= 11
            }
        }

        drawFooter(ctx, page: page, report: report, theme: theme, pageNumber: 1)
    }

    // MARK: - Page 2: Loadout

    private static func drawPageLoadout(
        ctx: CGContext,
        page: CGRect,
        report: CampaignSheetReport,
        theme: SheetTheme
    ) {
        let c = report.character
        drawPageChrome(ctx, page: page, theme: theme, title: theme.sheetTitle)
        var y = page.maxY - 56
        drawText(ctx, c.displayTitle, x: 36, y: y, font: .boldSystemFont(ofSize: 14), color: theme.ink)
        y -= 8
        drawText(ctx, "Loadout · Qualities · Contacts · Magic", x: 36, y: y - 10, font: .systemFont(ofSize: 9), color: theme.muted)
        y -= 28

        drawSectionBar(ctx, page: page, y: &y, title: "QUALITIES", theme: theme)
        y -= 4
        if c.qualities.isEmpty {
            drawText(ctx, "—", x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.muted)
            y -= 14
        } else {
            for q in c.qualities.prefix(14) {
                let sign = q.kind == .positive ? "+" : "−"
                drawText(ctx, "\(sign) \(q.name)  (\(q.karmaValue) karma)", x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.ink)
                y -= 12
            }
            y -= 6
        }

        drawSectionBar(ctx, page: page, y: &y, title: "AUGMENTATIONS", theme: theme)
        y -= 4
        if c.augmentations.isEmpty {
            drawText(ctx, "—", x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.muted)
            y -= 14
        } else {
            for a in c.augmentations.prefix(12) {
                drawText(
                    ctx,
                    "\(a.name)  ·  \(a.kind.rawValue)  ·  ESS \(formatEssence(a.essenceCost))",
                    x: 40,
                    y: y,
                    font: .systemFont(ofSize: 9),
                    color: theme.ink
                )
                y -= 12
            }
            y -= 6
        }

        drawSectionBar(ctx, page: page, y: &y, title: "GEAR  (✓ = equipped)", theme: theme)
        y -= 4
        if c.gear.isEmpty {
            drawText(ctx, "—", x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.muted)
            y -= 14
        } else {
            for g in c.gear.sorted(by: { $0.name < $1.name }).prefix(20) {
                let mark = g.equipped ? "✓" : "·"
                var extra = ""
                if let ar = g.armorRating { extra += "  Armor \(ar)" }
                if let d = g.damageCode, !d.isEmpty { extra += "  \(d)" }
                drawText(ctx, "\(mark)  \(g.name) ×\(g.quantity)\(extra)", x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.ink)
                y -= 12
                if y < 200 { break }
            }
            y -= 6
        }

        drawSectionBar(ctx, page: page, y: &y, title: "CONTACTS", theme: theme)
        y -= 4
        if c.contacts.isEmpty {
            drawText(ctx, "—", x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.muted)
            y -= 14
        } else {
            for contact in c.contacts.prefix(10) {
                drawText(
                    ctx,
                    "\(contact.name) — \(contact.role)  L\(contact.loyalty)/C\(contact.connection)",
                    x: 40,
                    y: y,
                    font: .systemFont(ofSize: 9),
                    color: theme.ink
                )
                y -= 12
            }
            y -= 6
        }

        drawSectionBar(ctx, page: page, y: &y, title: "MAGIC / RESONANCE", theme: theme)
        y -= 4
        var anyMagic = false
        if !c.adeptPowers.isEmpty {
            drawText(ctx, "Powers: " + c.adeptPowers.map { "\($0.name) Lv\($0.level)" }.joined(separator: ", "), x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.ink)
            y -= 12
            anyMagic = true
        }
        if !c.spells.isEmpty {
            drawText(ctx, "Spells: " + c.spells.map(\.name).joined(separator: ", "), x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.ink)
            y -= 12
            anyMagic = true
        }
        if !c.complexForms.isEmpty {
            drawText(ctx, "Complex forms: " + c.complexForms.map(\.name).joined(separator: ", "), x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.ink)
            y -= 12
            anyMagic = true
        }
        if !anyMagic {
            drawText(ctx, "—", x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.muted)
            y -= 14
        }

        y -= 8
        drawSectionBar(ctx, page: page, y: &y, title: "HOUSE RULES", theme: theme)
        y -= 4
        drawText(ctx, report.houseRulesSummary, x: 40, y: y, font: .systemFont(ofSize: 9), color: theme.ink)

        drawFooter(ctx, page: page, report: report, theme: theme, pageNumber: 2)
    }

    // MARK: - Theme

    private struct SheetTheme {
        var banner: NSColor
        var bannerText: NSColor
        var panel: NSColor
        var panelStroke: NSColor
        var accent: NSColor
        var ink: NSColor
        var muted: NSColor
        var pageBackground: NSColor
        var sheetTitle: String
        var editionBadge: String

        static func theme(for edition: Edition) -> SheetTheme {
            switch edition {
            case .sr4:
                return SheetTheme(
                    banner: NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.18, alpha: 1),
                    bannerText: NSColor(calibratedRed: 0.75, green: 0.95, blue: 0.8, alpha: 1),
                    panel: NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.93, alpha: 1),
                    panelStroke: NSColor(calibratedRed: 0.25, green: 0.45, blue: 0.3, alpha: 1),
                    accent: NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.28, alpha: 1),
                    ink: NSColor(calibratedWhite: 0.12, alpha: 1),
                    muted: NSColor(calibratedWhite: 0.35, alpha: 1),
                    pageBackground: NSColor(calibratedRed: 0.97, green: 0.98, blue: 0.96, alpha: 1),
                    sheetTitle: "SHADOWDECK  ·  SR4",
                    editionBadge: "SHADOWRUN 4TH EDITION"
                )
            case .sr5:
                return SheetTheme(
                    banner: NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.28, alpha: 1),
                    bannerText: NSColor(calibratedRed: 0.45, green: 0.9, blue: 1.0, alpha: 1),
                    panel: NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
                    panelStroke: NSColor(calibratedRed: 0.2, green: 0.45, blue: 0.7, alpha: 1),
                    accent: NSColor(calibratedRed: 0.0, green: 0.55, blue: 0.75, alpha: 1),
                    ink: NSColor(calibratedWhite: 0.1, alpha: 1),
                    muted: NSColor(calibratedWhite: 0.38, alpha: 1),
                    pageBackground: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1),
                    sheetTitle: "SHADOWDECK  ·  SR5",
                    editionBadge: "SHADOWRUN 5TH EDITION"
                )
            case .sr6:
                return SheetTheme(
                    banner: NSColor(calibratedRed: 0.18, green: 0.06, blue: 0.22, alpha: 1),
                    bannerText: NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.9, alpha: 1),
                    panel: NSColor(calibratedRed: 0.97, green: 0.93, blue: 0.98, alpha: 1),
                    panelStroke: NSColor(calibratedRed: 0.55, green: 0.2, blue: 0.65, alpha: 1),
                    accent: NSColor(calibratedRed: 0.7, green: 0.15, blue: 0.65, alpha: 1),
                    ink: NSColor(calibratedWhite: 0.1, alpha: 1),
                    muted: NSColor(calibratedWhite: 0.38, alpha: 1),
                    pageBackground: NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.99, alpha: 1),
                    sheetTitle: "SHADOWDECK  ·  SIXTH WORLD",
                    editionBadge: "SHADOWRUN SIXTH WORLD"
                )
            }
        }
    }

    // MARK: - Drawing helpers

    private static func drawPageChrome(_ ctx: CGContext, page: CGRect, theme: SheetTheme, title: String) {
        ctx.setFillColor(theme.pageBackground.cgColor)
        ctx.fill(page)
        // Side accent bar
        ctx.setFillColor(theme.accent.withAlphaComponent(0.85).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: page.height))
        // Top thin line
        ctx.setStrokeColor(theme.accent.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 16, y: page.maxY - 18))
        ctx.addLine(to: CGPoint(x: page.maxX - 16, y: page.maxY - 18))
        ctx.strokePath()
        drawText(ctx, title, x: 36, y: page.maxY - 34, font: .boldSystemFont(ofSize: 8), color: theme.muted)
    }

    private static func drawSectionBar(_ ctx: CGContext, page: CGRect, y: inout CGFloat, title: String, theme: SheetTheme) {
        let bar = CGRect(x: 28, y: y - 16, width: page.width - 56, height: 18)
        fillRoundRect(ctx, bar, radius: 3, color: theme.banner.withAlphaComponent(0.92))
        drawText(ctx, title, x: bar.minX + 10, y: bar.minY + 5, font: .boldSystemFont(ofSize: 9), color: theme.bannerText)
        y = bar.minY - 8
    }

    private static func drawKeyRow(_ ctx: CGContext, y: inout CGFloat, items: [(String, String)], theme: SheetTheme) {
        var x: CGFloat = 40
        for (k, v) in items {
            drawText(ctx, "\(k): \(v)", x: x, y: y, font: .systemFont(ofSize: 10), color: theme.ink)
            x += 140
        }
        y -= 16
    }

    private static func drawFooter(
        _ ctx: CGContext,
        page: CGRect,
        report: CampaignSheetReport,
        theme: SheetTheme,
        pageNumber: Int
    ) {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let stamp = "ShadowDeck \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · \(df.string(from: report.generatedAt)) · p.\(pageNumber) · Unofficial fan tool · House rules: \(report.houseRulesSummary)"
        drawText(ctx, stamp, x: 28, y: 22, font: .systemFont(ofSize: 7), color: theme.muted)
        ctx.setStrokeColor(theme.accent.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 28, y: 36))
        ctx.addLine(to: CGPoint(x: page.maxX - 28, y: 36))
        ctx.strokePath()
    }

    private static func drawPortrait(_ ctx: CGContext, character: Character, in rect: CGRect, theme: SheetTheme) {
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        let image: NSImage? = {
            if let data = character.avatar.inlineData, let img = NSImage(data: data) { return img }
            // Default metatype art
            let name = "metatype_\(character.metatype.rawValue)"
            if let url = Bundle.main.url(forResource: name, withExtension: "jpg")
                ?? Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "ChargenArt")
            {
                return NSImage(contentsOf: url)
            }
            return nil
        }()

        if let image {
            // PDF CGContext is bottom-left origin. Draw via NSGraphicsContext so
            // NSImage orientation matches on-screen (manual y-flip inverted portraits).
            let pixelSize = imagePixelSize(image)
            let iw = max(pixelSize.width, 1)
            let ih = max(pixelSize.height, 1)
            let scale = max(rect.width / iw, rect.height / ih)
            let dw = iw * scale
            let dh = ih * scale
            let dest = CGRect(
                x: rect.minX + (rect.width - dw) / 2,
                y: rect.minY + (rect.height - dh) / 2,
                width: dw,
                height: dh
            )
            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsCtx
            nsCtx.imageInterpolation = .high
            image.draw(
                in: NSRect(x: dest.minX, y: dest.minY, width: dest.width, height: dest.height),
                from: NSRect(origin: .zero, size: NSSize(width: iw, height: ih)),
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            NSGraphicsContext.restoreGraphicsState()
        } else {
            ctx.setFillColor(theme.panel.cgColor)
            ctx.fill(rect)
        }
        ctx.restoreGState()

        ctx.setStrokeColor(theme.accent.cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func imagePixelSize(_ image: NSImage) -> CGSize {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    private static func fillRoundRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, color: NSColor) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private static func strokeRoundRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, color: NSColor, width: CGFloat) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func drawText(
        _ ctx: CGContext,
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        font: NSFont,
        color: NSColor
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let ns = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(ns)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }

    private static func formatEssence(_ value: Decimal) -> String {
        let n = NSDecimalNumber(decimal: value)
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? "\(value)"
    }
}

public enum CharacterSheetPDFError: Error, LocalizedError {
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .renderFailed: "Could not create PDF context for the character sheet."
        }
    }
}
