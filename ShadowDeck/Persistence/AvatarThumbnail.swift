//
//  AvatarThumbnail.swift
//  ShadowDeck
//
//  Small square JPEGs for library list rows (aspect-fill).
//

import AppKit
import Foundation

public enum AvatarThumbnail {
    /// Edge length in points for library-row portraits (also used for gallery cards).
    public static let listEdge: CGFloat = 200

    /// Returns a compact JPEG suitable for list display, or nil if the source cannot be decoded.
    public static func make(from data: Data, edge: CGFloat = listEdge) -> Data? {
        guard !data.isEmpty, edge > 0 else { return nil }
        guard let source = NSImage(data: data), source.isValid else { return nil }

        // Prefer pixel dimensions from bitmap reps (NSImage.size can be wrong for some formats).
        var pixelW = source.size.width
        var pixelH = source.size.height
        if let rep = source.representations.first {
            if rep.pixelsWide > 0 { pixelW = CGFloat(rep.pixelsWide) }
            if rep.pixelsHigh > 0 { pixelH = CGFloat(rep.pixelsHigh) }
        }
        guard pixelW > 0, pixelH > 0 else { return nil }

        let target = NSSize(width: edge, height: edge)
        let scale = max(target.width / pixelW, target.height / pixelH)
        let drawSize = NSSize(width: pixelW * scale, height: pixelH * scale)
        let origin = NSPoint(
            x: (target.width - drawSize.width) / 2,
            y: (target.height - drawSize.height) / 2
        )

        // Modern rendering path (lockFocus is unreliable / deprecated on recent macOS).
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(edge),
            pixelsHigh: Int(edge),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: target).fill()
            source.draw(
                in: NSRect(origin: origin, size: drawSize),
                from: NSRect(origin: .zero, size: NSSize(width: pixelW, height: pixelH)),
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
