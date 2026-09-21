//
//  AvatarThumbnail.swift
//  ShadowDeck
//
//  Small square JPEGs for library list rows (aspect-fill).
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AvatarThumbnail {
    /// Long edge, in pixels, of the JPEG stored on the library row.
    public static let storedLongEdge = 96
    /// JPEG quality for that stored row thumbnail.
    public static let storedJPEGQuality: CGFloat = 0.6

    /// Edge length in points for library-row portraits (also used for gallery cards).
    public static let listEdge: CGFloat = 200

    /// Aspect-preserving JPEG for list rows. ImageIO only, so it can run off the main actor.
    public nonisolated static func makeStoredJPEG(from data: Data) -> Data? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: storedLongEdge,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            dest,
            image,
            [kCGImageDestinationLossyCompressionQuality: storedJPEGQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

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
