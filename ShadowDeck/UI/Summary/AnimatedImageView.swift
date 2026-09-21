//
//  AnimatedImageView.swift
//  ShadowDeck
//
//  SwiftUI Image(nsImage:) only shows a GIF’s first frame. This view decodes
//  multi-frame GIF (or APNG) data via ImageIO and plays frames on a loop.
//

import AppKit
import CoreGraphics
import ImageIO
import SwiftUI

/// Renders image `Data` with animation when the payload has multiple frames.
struct AnimatedImageView: View {
    let data: Data
    var contentMode: ContentMode = .fill

    @State private var frames: [GIFFrame] = []
    @State private var frameIndex: Int = 0

    var body: some View {
        Group {
            if !frames.isEmpty {
                Image(nsImage: frames[frameIndex].image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let still = NSImage(data: data) {
                Image(nsImage: still)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: dataIdentity) {
            let payload = data
            let decoded = await Task.detached(priority: .userInitiated) {
                GIFDecoder.decode(payload)
            }.value
            frames = decoded
            frameIndex = 0
            guard decoded.count > 1 else { return }
            await play(decoded)
        }
    }

    /// Stable-enough identity so we re-decode when portrait bytes change.
    private var dataIdentity: String {
        let head = data.prefix(24).map { String(format: "%02x", $0) }.joined()
        let tail = data.suffix(8).map { String(format: "%02x", $0) }.joined()
        return "\(data.count):\(head):\(tail)"
    }

    private func play(_ frames: [GIFFrame]) async {
        guard frames.count > 1 else { return }
        var index = 0
        while !Task.isCancelled {
            frameIndex = index
            let delay = frames[index].delay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            index = (index + 1) % frames.count
        }
    }
}

// MARK: - Decoding

struct GIFFrame: Sendable {
    let image: NSImage
    /// Seconds to display this frame.
    let delay: TimeInterval
}

enum GIFDecoder {
    /// A long portrait loops its first frames at a reduced size. This is a visible limit.
    static let maxFrames = 48
    static let maxLongEdge = 512

    /// Decode multi-frame image data (GIF / APNG). Returns one frame for stills.
    /// Runs off the main actor. Frames past `maxFrames` are dropped. The long edge is capped.
    nonisolated static func decode(_ data: Data) -> [GIFFrame] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return []
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return [] }

        let limit = min(count, maxFrames)
        var frames: [GIFFrame] = []
        frames.reserveCapacity(limit)
        for index in 0..<limit {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            let scaled = downscale(cgImage, maxLongEdge: maxLongEdge)
            let size = NSSize(width: scaled.width, height: scaled.height)
            let nsImage = NSImage(cgImage: scaled, size: size)
            frames.append(GIFFrame(image: nsImage, delay: delay(for: source, index: index)))
        }
        return frames
    }

    private nonisolated static func downscale(_ image: CGImage, maxLongEdge: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let longEdge = max(width, height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return image }
        let scale = Double(maxLongEdge) / Double(longEdge)
        let targetW = max(1, Int((Double(width) * scale).rounded()))
        let targetH = max(1, Int((Double(height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return context.makeImage() ?? image
    }

    /// True when data is a multi-frame GIF/APNG suitable for animation.
    static func isAnimatedImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 1
    }

    private static func delay(for source: CGImageSource, index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }

        // Prefer GIF, then PNG (APNG) delay dictionaries.
        let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any]

        let unclamped =
            (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
        let clamped =
            (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? (png?[kCGImagePropertyAPNGDelayTime] as? Double)

        // Browsers treat very small GIF delays as ~10ms minimum; use 20ms floor.
        let raw = unclamped ?? clamped ?? 0.1
        return max(raw, 0.02)
    }
}
