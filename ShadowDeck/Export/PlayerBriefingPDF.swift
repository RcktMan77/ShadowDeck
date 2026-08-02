//
//  PlayerBriefingPDF.swift
//  ShadowDeck
//
//  Simple US Letter PDF for player-safe run briefings (Phase 2E).
//  Renders the same Markdown string as Copy Markdown — no GM-only fields.
//

import AppKit
import CoreText
import Foundation

public enum PlayerBriefingPDF {
    public enum ExportError: Error, LocalizedError {
        case renderFailed

        public var errorDescription: String? {
            switch self {
            case .renderFailed: "Could not create the briefing PDF."
            }
        }
    }

    /// Render briefing Markdown as a simple multi-page PDF.
    public static func render(markdown: String, runTitle: String = "") throws -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw ExportError.renderFailed
        }

        let margin: CGFloat = 48
        let contentWidth = page.width - margin * 2
        let topY = page.height - margin
        let bottomY = margin

        let titleFont = NSFont.boldSystemFont(ofSize: 16)
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let headerFont = NSFont.boldSystemFont(ofSize: 12)
        let ink = NSColor.black
        let muted = NSColor.secondaryLabelColor

        let lines = markdown.components(separatedBy: "\n")
        var pageIndex = 0
        var y = topY

        func beginPage() {
            var media = page
            ctx.beginPage(mediaBox: &media)
            pageIndex += 1
            y = topY
            // Footer
            drawLine(
                ctx,
                "ShadowDeck player briefing — page \(pageIndex)",
                x: margin,
                y: 28,
                font: .systemFont(ofSize: 9),
                color: muted,
                width: contentWidth
            )
        }

        func ensureSpace(_ needed: CGFloat) {
            if y - needed < bottomY {
                ctx.endPage()
                beginPage()
            }
        }

        beginPage()

        // Optional cover title if markdown doesn't start with #
        let banner = runTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !banner.isEmpty, lines.first?.hasPrefix("#") != true {
            ensureSpace(28)
            y = drawLine(ctx, banner, x: margin, y: y, font: titleFont, color: ink, width: contentWidth)
            y -= 12
        }

        for raw in lines {
            let line = raw
            if line.isEmpty {
                y -= 8
                continue
            }

            if line.hasPrefix("# ") {
                let text = String(line.dropFirst(2))
                ensureSpace(32)
                y = drawLine(ctx, text, x: margin, y: y, font: titleFont, color: ink, width: contentWidth)
                y -= 10
            } else if line.hasPrefix("## ") {
                let text = String(line.dropFirst(3))
                ensureSpace(28)
                y -= 6
                y = drawLine(ctx, text, x: margin, y: y, font: headerFont, color: ink, width: contentWidth)
                y -= 6
            } else if line.hasPrefix("### ") {
                let text = String(line.dropFirst(4))
                ensureSpace(24)
                y = drawLine(ctx, text, x: margin, y: y, font: headerFont, color: ink, width: contentWidth)
                y -= 4
            } else if line.hasPrefix("---") {
                ensureSpace(16)
                y -= 6
                ctx.setStrokeColor(NSColor.separatorColor.cgColor)
                ctx.setLineWidth(0.5)
                ctx.move(to: CGPoint(x: margin, y: y))
                ctx.addLine(to: CGPoint(x: page.width - margin, y: y))
                ctx.strokePath()
                y -= 10
            } else {
                // Strip light Markdown emphasis for print.
                let plain = line
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "_", with: "")
                let font: NSFont = plain.hasPrefix("- ") ? bodyFont : bodyFont
                let text = plain
                let height = measureHeight(text, font: font, width: contentWidth)
                ensureSpace(height + 4)
                y = drawLine(ctx, text, x: margin, y: y, font: font, color: ink, width: contentWidth)
                y -= 4
            }
        }

        ctx.endPage()
        ctx.closePDF()
        return data as Data
    }

    public static func write(markdown: String, runTitle: String = "", to url: URL) throws {
        try render(markdown: markdown, runTitle: runTitle).write(to: url, options: .atomic)
    }

    // MARK: - Drawing

    @discardableResult
    private static func drawLine(
        _ ctx: CGContext,
        _ string: String,
        x: CGFloat,
        y: CGFloat,
        font: NSFont,
        color: NSColor,
        width: CGFloat
    ) -> CGFloat {
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let ns = NSAttributedString(string: string, attributes: attr)
        let framesetter = CTFramesetterCreateWithAttributedString(ns)
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: ns.length),
            nil,
            constraint,
            nil
        )
        let height = max(ceil(fit.height), font.pointSize + 2)
        let rect = CGRect(x: x, y: y - height, width: width, height: height)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: ns.length),
            path,
            nil
        )
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
        return y - height
    }

    private static func measureHeight(_ string: String, font: NSFont, width: CGFloat) -> CGFloat {
        let attr: [NSAttributedString.Key: Any] = [.font: font]
        let ns = NSAttributedString(string: string, attributes: attr)
        let framesetter = CTFramesetterCreateWithAttributedString(ns)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: ns.length),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        return max(ceil(fit.height), font.pointSize + 2)
    }
}
