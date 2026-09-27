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
    /// Square edge, in pixels, of the JPEG stored for library rows and gallery cards.
    /// Matches the pre-stored thumbnail: 200×200 aspect-fill.
    public static let storedEdge = 200
    /// JPEG quality for that stored thumbnail. Matches the previous list thumbnail.
    public static let storedJPEGQuality: CGFloat = 0.82

    /// Edge length in points for library-row portraits (also used for gallery cards).
    public static let listEdge: CGFloat = 200

    /// True when a stored JPEG is already large enough for the gallery card.
    /// Smaller files (the 96px thumbnails) are rebuilt from the original portrait.
    nonisolated public static func isGallerySized(_ jpeg: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        let edge = Int(storedEdge)
        return width >= edge && height >= edge
    }

    /// Square aspect-fill JPEG for library rows and gallery cards. ImageIO only, so it can run off the main actor.
    nonisolated public static func makeStoredJPEG(from data: Data) -> Data? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let edge = Int(storedEdge)
        let pixelW = max(image.width, 1)
        let pixelH = max(image.height, 1)
        let scale = max(CGFloat(edge) / CGFloat(pixelW), CGFloat(edge) / CGFloat(pixelH))
        let drawSize = CGSize(width: CGFloat(pixelW) * scale, height: CGFloat(pixelH) * scale)
        let origin = CGPoint(
            x: (CGFloat(edge) - drawSize.width) / 2,
            y: (CGFloat(edge) - drawSize.height) / 2
        )
        guard let context = CGContext(
            data: nil,
            width: edge,
            height: edge,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
        context.draw(image, in: CGRect(origin: origin, size: drawSize))
        guard let rendered = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            dest,
            rendered,
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
