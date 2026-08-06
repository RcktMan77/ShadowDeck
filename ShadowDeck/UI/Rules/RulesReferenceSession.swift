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
        calcContext: RulesCalcContext? = nil,
        mode: RulesReferenceMode = .reference
    ) {
        controller.applyOpenContext(
            query: query,
            edition: edition,
            calcContext: calcContext,
            mode: mode
        )
    }

    /// Open directly on the PDF shelf (main-window shortcut).
    func preparePDFLibraryShelf() {
        prepare(mode: .library)
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

/// Synthetic multi-page PDFs for README captures (covers from bundled original art;
/// labels say “sample”; no real rule text or publisher assets).
@MainActor
enum MarketingPDFLibrarySeeder {
    private struct Spec {
        var title: String
        var bookKey: String?
        var tags: [String]
        var section: PDFShelfSection
        var coverResource: String
        var pages: Int
    }

    /// Three core samples (one per edition) + two mission samples for the shelf marquee.
    private static let specs: [Spec] = [
        Spec(
            title: "SR4A Core (sample)",
            bookKey: PageRef.BookKey.sr4a,
            tags: ["SR4"],
            section: .coreRulebook,
            coverResource: "cover_sr4_core",
            pages: 5
        ),
        Spec(
            title: "SR5 Core Rulebook (sample)",
            bookKey: PageRef.BookKey.sr5CRB,
            tags: ["SR5"],
            section: .coreRulebook,
            coverResource: "cover_sr5_core",
            pages: 6
        ),
        Spec(
            title: "SR6 Core (sample)",
            bookKey: PageRef.BookKey.sr6Core,
            tags: ["SR6"],
            section: .coreRulebook,
            coverResource: "cover_sr6_core",
            pages: 5
        ),
        Spec(
            title: "Mission: Downtown Datasteal (sample)",
            bookKey: "srm-datasteal",
            tags: ["SR5"],
            section: .mission,
            coverResource: "cover_mission_datasteal",
            pages: 4
        ),
        Spec(
            title: "Mission: Sprawl Courier (sample)",
            bookKey: "srm-sprawl",
            tags: ["SR5"],
            section: .mission,
            coverResource: "cover_mission_sprawl",
            pages: 4
        )
    ]

    static func makeStore() throws -> PDFLibraryStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Marketing-PDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var store = PDFLibraryStore(items: [], rootDirectory: root)

        for spec in specs {
            let fileBase = (spec.bookKey ?? UUID().uuidString)
                .replacingOccurrences(of: "/", with: "-")
            let url = root.appendingPathComponent("\(fileBase).pdf")
            let cover = loadCoverImage(named: spec.coverResource)
            try writeSamplePDF(
                title: spec.title,
                coverArt: cover,
                pageCount: spec.pages,
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

    private static func loadCoverImage(named name: String) -> NSImage? {
        let bundle = Bundle.main
        // Bundle only — no source-tree #filePath (Desktop TCC when the repo lives under Desktop).
        let candidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Brand/MarketingPDFCovers"),
            bundle.url(forResource: name, withExtension: "jpg", subdirectory: "MarketingPDFCovers"),
            bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Brand"),
            bundle.url(forResource: name, withExtension: "jpg")
        ]
        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    private static func writeSamplePDF(
        title: String,
        coverArt: NSImage?,
        pageCount: Int,
        to url: URL
    ) throws {
        let doc = PDFDocument()
        let pageSize = NSSize(width: 612, height: 792) // US Letter points
        for index in 0..<pageCount {
            let image = renderPage(
                title: title,
                page: index + 1,
                total: pageCount,
                coverArt: coverArt,
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
        coverArt: NSImage?,
        size: NSSize
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let bounds = NSRect(origin: .zero, size: size)

        if let coverArt {
            // Cover-fill the page (crop sides if needed) so shelf thumbs match the art.
            let artSize = coverArt.size
            let scale = max(size.width / max(artSize.width, 1), size.height / max(artSize.height, 1))
            let drawSize = NSSize(width: artSize.width * scale, height: artSize.height * scale)
            let origin = NSPoint(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2
            )
            let fraction: CGFloat = page == 1 ? 1 : 0.42
            coverArt.draw(
                in: NSRect(origin: origin, size: drawSize),
                from: NSRect(origin: .zero, size: artSize),
                operation: .copy,
                fraction: fraction
            )
            if page > 1 {
                NSColor.black.withAlphaComponent(0.55).setFill()
                bounds.fill(using: .sourceOver)
            }
        } else {
            NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
            bounds.fill()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        if page == 1 {
            // Title band over the art’s reserved lower third (cover art leaves dark space).
            let band = NSRect(x: 0, y: 0, width: size.width, height: size.height * 0.22)
            NSColor.black.withAlphaComponent(0.55).setFill()
            band.fill(using: .sourceOver)

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.72),
                .paragraphStyle: paragraph
            ]
            (title as NSString).draw(
                in: NSRect(x: 28, y: size.height * 0.10, width: size.width - 56, height: 36),
                withAttributes: titleAttrs
            )
            ("Marketing sample · not a real rulebook" as NSString).draw(
                in: NSRect(x: 28, y: size.height * 0.05, width: size.width - 56, height: 20),
                withAttributes: subAttrs
            )
        } else {
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraph
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.65),
                .paragraphStyle: paragraph
            ]
            (title as NSString).draw(
                in: NSRect(x: 40, y: size.height * 0.52, width: size.width - 80, height: 40),
                withAttributes: titleAttrs
            )
            ("Sample page \(page) of \(total) · ShadowDeck capture only" as NSString).draw(
                in: NSRect(x: 40, y: size.height * 0.45, width: size.width - 80, height: 24),
                withAttributes: subAttrs
            )
        }

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
        mode: RulesReferenceMode = .reference,
        openWindow: OpenWindowAction
    ) {
        let ctx = character.map { RulesCalcContext.from(character: $0) }
        RulesReferenceSession.shared.prepare(
            query: query,
            edition: edition ?? ctx?.edition,
            calcContext: ctx,
            mode: mode
        )
        openWindow(id: windowID)
    }

    /// Open Rules Reference from anywhere without an `OpenWindowAction`.
    /// ContentView listens for `AppCommand.openRulesReference`.
    @MainActor
    static func request(
        query: String? = nil,
        edition: Edition? = nil,
        character: Character? = nil,
        mode: RulesReferenceMode = .reference
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
        if mode != .reference {
            info["mode"] = mode.rawValue
        }
        NotificationCenter.default.post(
            name: AppCommand.openRulesReference,
            object: nil,
            userInfo: info.isEmpty ? nil : info
        )
    }

    /// Shortcut: open Rules Reference already on the PDF shelf.
    @MainActor
    static func requestPDFLibrary() {
        request(mode: .library)
    }
}
