//
//  AnimatedImageView.swift
//  ShadowDeck
//
//  SwiftUI Image(nsImage:) only shows a GIF’s first frame. This view decodes
//  multi-frame GIF (or APNG) data via ImageIO and plays frames on a loop.
//

import AppKit
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
            let decoded = GIFDecoder.decode(data)
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
    /// Decode multi-frame image data (GIF / APNG). Returns one frame for stills.
    static func decode(_ data: Data) -> [GIFFrame] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return []
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return [] }

        var frames: [GIFFrame] = []
        frames.reserveCapacity(count)
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            let nsImage = NSImage(cgImage: cgImage, size: size)
            frames.append(GIFFrame(image: nsImage, delay: delay(for: source, index: index)))
        }
        return frames
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
