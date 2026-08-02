//
//  RulesReferenceSession.swift
//  ShadowDeck
//
//  Shared session for the single Rules Reference window.
//

import AppKit
import Foundation
import PDFKit
import SwiftUI

/// One reusable Rules Reference controller for the dedicated window.
@MainActor
final class RulesReferenceSession: ObservableObject {
    static let shared = RulesReferenceSession()

    let controller = RulesReferenceController()
    private var didInstallMarketingPDFLibrary = false

    private init() {}

    /// Apply optional search/edition/character context before the window is shown or focused.
    func prepare(
        query: String? = nil,
        edition: Edition? = nil,
        calcContext: RulesCalcContext? = nil
    ) {
        controller.applyOpenContext(query: query, edition: edition, calcContext: calcContext)
    }

    // MARK: - Marketing marquees

    /// Ephemeral sample PDFs only — never the user's Application Support shelf.
    func installMarketingPDFLibraryIfNeeded() {
        guard MarketingScreenshotExporter.isEnabled, !didInstallMarketingPDFLibrary else { return }
        do {
            let store = try MarketingPDFLibrarySeeder.makeStore()
            controller.replacePDFLibrary(store)
            didInstallMarketingPDFLibrary = true
        } catch {
            fputs("Marketing PDF shelf seed failed: \(error)\n", stderr)
        }
    }

    /// Reference mode: dice topic + SR5 filter (page chips resolve against sample shelf).
    func prepareMarketingReferenceShowcase() {
        installMarketingPDFLibraryIfNeeded()
        prepare(query: "dice", edition: .sr5)
    }

    /// Library mode: gallery shelf of sample books (reader closed).
    func prepareMarketingLibraryShowcase() {
        installMarketingPDFLibraryIfNeeded()
        controller.applyMarketingLibraryShelf()
    }
}

// MARK: - Marketing sample PDFs

/// Synthetic multi-page PDFs for README captures (labels say “sample”; no real rule text).
@MainActor
enum MarketingPDFLibrarySeeder {
    static func makeStore() throws -> PDFLibraryStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Marketing-PDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var store = PDFLibraryStore(items: [], rootDirectory: root)

        let specs: [(title: String, bookKey: String?, tags: [String], section: PDFShelfSection, pages: Int, hue: CGFloat)] = [
            ("SR5 Core Rulebook (sample)", PageRef.BookKey.sr5CRB, ["SR5"], .coreRulebook, 6, 0.55),
            ("Run & Gun (sample)", "run-gun", ["SR5"], .sourcebook, 4, 0.08),
            ("Mission: Downtown Datasteal (sample)", "srm-sample", ["SR5"], .mission, 3, 0.72)
        ]

        for spec in specs {
            let url = root.appendingPathComponent("\(spec.bookKey ?? UUID().uuidString).pdf")
            try writeSamplePDF(
                title: spec.title,
                pageCount: spec.pages,
                hue: spec.hue,
                to: url
            )
            _ = try store.addPDF(
                from: url,
                title: spec.title,
                bookKey: spec.bookKey,
                editionTags: spec.tags,
                shelfSection: spec.section
            )
        }
        return store
    }

    private static func writeSamplePDF(title: String, pageCount: Int, hue: CGFloat, to url: URL) throws {
        let doc = PDFDocument()
        let pageSize = NSSize(width: 612, height: 792) // US Letter points
        for index in 0..<pageCount {
            let image = renderPage(
                title: title,
                page: index + 1,
                total: pageCount,
                hue: hue,
                size: pageSize
            )
            guard let pdfPage = PDFPage(image: image) else {
                throw PDFLibraryStoreError.copyFailed("Could not build sample PDF page.")
            }
            doc.insert(pdfPage, at: index)
        }
        guard doc.write(to: url) else {
            throw PDFLibraryStoreError.copyFailed("Could not write sample PDF.")
        }
    }

    private static func renderPage(
        title: String,
        page: Int,
        total: Int,
        hue: CGFloat,
        size: NSSize
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let bounds = NSRect(origin: .zero, size: size)

        let top = NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.28, alpha: 1)
        let bottom = NSColor(calibratedHue: hue, saturation: 0.35, brightness: 0.12, alpha: 1)
        let gradient = NSGradient(starting: top, ending: bottom)
        gradient?.draw(in: bounds, angle: -90)

        let accent = NSColor(calibratedHue: hue, saturation: 0.7, brightness: 0.85, alpha: 1)
        accent.withAlphaComponent(0.9).setStroke()
        let inset = bounds.insetBy(dx: 36, dy: 36)
        let border = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
        border.lineWidth = 2
        border.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: page == 1 ? 28 : 20, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            .paragraphStyle: paragraph
        ]
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph
        ]

        let titleRect = NSRect(x: 48, y: size.height * 0.52, width: size.width - 96, height: 80)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        let subtitle = page == 1
            ? "Marketing sample · not a real rulebook"
            : "Sample page \(page) of \(total)"
        let subRect = NSRect(x: 48, y: size.height * 0.42, width: size.width - 96, height: 40)
        (subtitle as NSString).draw(in: subRect, withAttributes: subtitleAttrs)

        let footer = "ShadowDeck README capture · local only"
        let footRect = NSRect(x: 48, y: 48, width: size.width - 96, height: 24)
        (footer as NSString).draw(in: footRect, withAttributes: footerAttrs)

        image.unlockFocus()
        return image
    }
}

// MARK: - Open helper

enum RulesReferenceOpener {
    /// Window scene id registered on `ShadowDeckApp`.
    static let windowID = "rules-reference"

    @MainActor
    static func open(
        query: String? = nil,
        edition: Edition? = nil,
        character: Character? = nil,
        openWindow: OpenWindowAction
    ) {
        let ctx = character.map { RulesCalcContext.from(character: $0) }
        RulesReferenceSession.shared.prepare(
            query: query,
            edition: edition ?? ctx?.edition,
            calcContext: ctx
        )
        openWindow(id: windowID)
    }

    /// Open Rules Reference from anywhere without an `OpenWindowAction`.
    /// ContentView listens for `AppCommand.openRulesReference`.
    @MainActor
    static func request(
        query: String? = nil,
        edition: Edition? = nil,
        character: Character? = nil
    ) {
        var info: [AnyHashable: Any] = [:]
        if let query {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { info["query"] = trimmed }
        }
        if let character {
            info["calcContext"] = RulesCalcContext.from(character: character)
            info["edition"] = character.edition
        } else if let edition {
            info["edition"] = edition
        }
        NotificationCenter.default.post(
            name: AppCommand.openRulesReference,
            object: nil,
            userInfo: info.isEmpty ? nil : info
        )
    }
}
