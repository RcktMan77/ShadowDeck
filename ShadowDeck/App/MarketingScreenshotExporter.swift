//
//  MarketingScreenshotExporter.swift
//  ShadowDeck
//
//  Captures README marquees (stills + short silent GIFs) from *inside* the app
//  so we don't depend on Screen Recording TCC. Trigger with:
//
//    SHADOWDECK_CAPTURE_SCREENSHOTS=1 open ShadowDeck.app
//    # or
//    ShadowDeck.app/Contents/MacOS/ShadowDeck --capture-screenshots
//
//  Always uses an in-memory sample library (see LibraryEnvironment.marketingCapture).
//

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MarketingScreenshotExporter {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SHADOWDECK_CAPTURE_SCREENSHOTS"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--capture-screenshots")
    }

    /// Writable location inside the app sandbox (Application Support).
    static var outputDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("ShadowDeck", isDirectory: true)
            .appendingPathComponent("MarketingScreenshots", isDirectory: true)
    }

    /// Posted as the sequence advances so ContentView can change state.
    /// `object` is `Phase.rawValue`. Optional `userInfo["step"]` is an Int for GIF storyboards.
    static let phaseNotification = Notification.Name("com.shadowdeck.marketingScreenshotPhase")

    enum Phase: String {
        case splash
        case library
        case generationRole
        case characterSheet
        case runLibrary
        /// Storyboard: open/update sample run detail (userInfo step 0…n).
        case runGif
        /// Storyboard: Advance tab plan → apply (userInfo step 0…n).
        case advanceGif
        case finished
    }

    /// Playback delay between GIF frames (shorter = smoother with more frames).
    private static let gifFrameDelay: Double = 0.22
    /// Hold last frame a bit longer so the result is readable.
    private static let gifLastFrameDelay: Double = 0.95
    /// Live captures per storyboard step (mid-scroll + settle).
    private static let samplesPerStep = 4
    /// Synthetic cross-dissolve frames inserted between each live capture.
    private static let crossfadeIntermediates = 2
    /// Long-edge cap for GIF frames (keeps files README-friendly).
    private static let gifMaxLongEdge: CGFloat = 720

    private enum CropMode {
        /// Full window (run library list).
        case full
        /// Drop sidebar; keep main detail column.
        case detail
    }

    @MainActor
    static func runSequence() async {
        let dir = outputDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fputs("Screenshot dir failed: \(error)\n", stderr)
            NSApp.terminate(nil)
            return
        }

        fputs("Marketing screenshots → \(dir.path)\n", stderr)

        // —— Stills (no separate Run Library still — covered by mission GIF) ——
        try? await Task.sleep(nanoseconds: 900_000_000)
        await captureStill(named: "01-splash", to: dir)

        post(.library)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        await captureStill(named: "02-library", to: dir)

        post(.generationRole)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await captureStill(named: "03-generation-role", to: dir)

        post(.characterSheet)
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        await captureStill(named: "04-character-sheet", to: dir)

        // —— GIFs ——
        await captureRunFlowGIF(to: dir)
        await captureAdvanceFlowGIF(to: dir)

        post(.finished)
        fputs("Marketing screenshots complete.\n", stderr)
        try? await Task.sleep(nanoseconds: 300_000_000)
        NSApp.terminate(nil)
    }

    // MARK: - GIF storyboards

    /// Library → create job → fill → team → active log → objectives → complete → library.
    @MainActor
    private static func captureRunFlowGIF(to dir: URL) async {
        // Steps 0 and last are library list; middle steps are detail.
        let stepCount = 12
        var frames: [NSImage] = []
        for step in 0..<stepCount {
            post(.runGif, step: step)
            let crop: CropMode = (step == 0 || step == stepCount - 1) ? .full : .detail
            await appendSettlingFrames(to: &frames, crop: crop, firstStep: step == 0)
        }
        writeGIF(frames: frames, named: "07-run-mission-flow", to: dir)
    }

    /// Advance: scroll skills, highlight Add on each raise, Apply Plan, show result.
    @MainActor
    private static func captureAdvanceFlowGIF(to dir: URL) async {
        let stepCount = 8
        var frames: [NSImage] = []
        for step in 0..<stepCount {
            post(.advanceGif, step: step)
            await appendSettlingFrames(to: &frames, crop: .detail, firstStep: step == 0)
        }
        writeGIF(frames: frames, named: "08-advancement-planner", to: dir)
    }

    /// Capture several frames while UI scrolls/settles for smoother playback.
    @MainActor
    private static func appendSettlingFrames(
        to frames: inout [NSImage],
        crop: CropMode,
        firstStep: Bool
    ) async {
        // Brief pause for scroll animation to start, then dense sampling.
        let firstWait: UInt64 = firstStep ? 380_000_000 : 160_000_000
        try? await Task.sleep(nanoseconds: firstWait)
        for sample in 0..<samplesPerStep {
            if sample > 0 {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
            if let full = await snapshotLargestWindow() {
                let processed: NSImage?
                switch crop {
                case .full:
                    processed = downscale(full, maxLongEdge: gifMaxLongEdge)
                case .detail:
                    processed = cropDetailPanel(full).flatMap { downscale($0, maxLongEdge: gifMaxLongEdge) }
                }
                if let frame = processed {
                    frames.append(frame)
                } else {
                    frames.append(downscale(full, maxLongEdge: gifMaxLongEdge) ?? full)
                }
            } else {
                fputs("  ✗ GIF frame: no snapshot\n", stderr)
            }
        }
    }

    /// Insert cross-dissolves between live frames so hard cuts read as fades.
    private static func expandWithCrossfades(_ keyframes: [NSImage]) -> [NSImage] {
        guard keyframes.count >= 2, crossfadeIntermediates > 0 else { return keyframes }
        var out: [NSImage] = []
        out.reserveCapacity(keyframes.count * (crossfadeIntermediates + 1))
        for i in 0..<keyframes.count {
            out.append(keyframes[i])
            guard i + 1 < keyframes.count else { break }
            let a = keyframes[i]
            let b = keyframes[i + 1]
            for k in 1...crossfadeIntermediates {
                let t = CGFloat(k) / CGFloat(crossfadeIntermediates + 1)
                if let blended = crossDissolve(from: a, to: b, t: t) {
                    out.append(blended)
                }
            }
        }
        return out
    }

    /// Linear blend: result ≈ from·(1−t) + to·t (opaque bitmaps).
    private static func crossDissolve(from: NSImage, to: NSImage, t: CGFloat) -> NSImage? {
        let size = NSSize(
            width: min(from.size.width, to.size.width),
            height: min(from.size.height, to.size.height)
        )
        guard size.width > 1, size.height > 1 else { return nil }
        let rect = NSRect(origin: .zero, size: size)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        from.draw(in: rect, from: NSRect(origin: .zero, size: from.size), operation: .copy, fraction: 1)
        to.draw(in: rect, from: NSRect(origin: .zero, size: to.size), operation: .sourceOver, fraction: t)
        out.unlockFocus()
        return out
    }

    // MARK: - Capture helpers

    @MainActor
    private static func post(_ phase: Phase, step: Int? = nil) {
        var info: [AnyHashable: Any] = [:]
        if let step { info["step"] = step }
        NotificationCenter.default.post(
            name: phaseNotification,
            object: phase.rawValue,
            userInfo: info.isEmpty ? nil : info
        )
    }

    @MainActor
    private static func captureStill(named name: String, to directory: URL) async {
        try? await Task.sleep(nanoseconds: 200_000_000)
        NSApp.windows.forEach { $0.layoutIfNeeded() }

        guard let image = await snapshotLargestWindow() else {
            fputs("  ✗ \(name): no window snapshot\n", stderr)
            return
        }

        let pngURL = directory.appendingPathComponent("\(name).png")
        let jpgURL = directory.appendingPathComponent("\(name).jpg")

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            fputs("  ✗ \(name): bitmap conversion failed\n", stderr)
            return
        }

        if let png = rep.representation(using: .png, properties: [:]) {
            do {
                try png.write(to: pngURL)
                fputs("  ✓ \(pngURL.lastPathComponent) (\(png.count / 1024) KB)\n", stderr)
            } catch {
                fputs("  ✗ \(name) png: \(error)\n", stderr)
            }
        }

        if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.84]) {
            do {
                try jpg.write(to: jpgURL)
                fputs("  ✓ \(jpgURL.lastPathComponent) (\(jpg.count / 1024) KB)\n", stderr)
            } catch {
                fputs("  ✗ \(name) jpg: \(error)\n", stderr)
            }
        }
    }

    @MainActor
    private static func snapshotLargestWindow() async -> NSImage? {
        let candidates = NSApp.windows.filter { window in
            window.isVisible
                && !window.isMiniaturized
                && window.frame.width >= 600
                && window.frame.height >= 400
                && window.contentView != nil
        }
        guard let window = candidates.max(by: {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        }), let view = window.contentView else {
            return nil
        }

        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)

        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        return snapshotViaLayer(view: view, window: window)
    }

    @MainActor
    private static func snapshotViaLayer(view: NSView, window: NSWindow) -> NSImage? {
        let bounds = view.bounds
        if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            view.cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            return image
        }

        view.wantsLayer = true
        guard let layer = view.layer else { return nil }
        let scale = window.backingScaleFactor
        let pixelW = Int((bounds.width * scale).rounded(.up))
        let pixelH = Int((bounds.height * scale).rounded(.up))
        guard pixelW > 0, pixelH > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = bounds.size

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.translateBy(x: 0, y: CGFloat(pixelH))
        cg.scaleBy(x: scale, y: -scale)
        layer.render(in: cg)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// Drop sidebar (~22% width) so action in the detail column is obvious.
    private static func cropDetailPanel(_ image: NSImage) -> NSImage? {
        let size = image.size
        guard size.width > 100, size.height > 100 else { return image }
        let outSize = NSSize(width: size.width * 0.78, height: size.height * 0.96)
        let out = NSImage(size: outSize)
        out.lockFocus()
        let src = NSRect(
            x: size.width * 0.22,
            y: 0,
            width: size.width * 0.78,
            height: size.height * 0.96
        )
        image.draw(
            in: NSRect(origin: .zero, size: outSize),
            from: src,
            operation: .copy,
            fraction: 1
        )
        out.unlockFocus()
        return out
    }

    private static func downscale(_ image: NSImage, maxLongEdge: CGFloat) -> NSImage? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }
        let scale = maxLongEdge / longEdge
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let out = NSImage(size: newSize)
        out.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        out.unlockFocus()
        return out
    }

    private static func writeGIF(frames: [NSImage], named name: String, to directory: URL) {
        guard !frames.isEmpty else {
            fputs("  ✗ \(name).gif: no frames\n", stderr)
            return
        }
        // Cross-dissolve between live captures so scene changes don't hard-cut.
        let expanded = expandWithCrossfades(frames)
        let url = directory.appendingPathComponent("\(name).gif")
        let count = expanded.count
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            count,
            nil
        ) else {
            fputs("  ✗ \(name).gif: destination failed\n", stderr)
            return
        }

        let fileProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ] as [CFString: Any],
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        for (index, frame) in expanded.enumerated() {
            guard let cg = cgImage(from: frame) else { continue }
            let delay = index == expanded.count - 1 ? gifLastFrameDelay : gifFrameDelay
            let frameProps: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ] as [CFString: Any],
            ]
            CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
        }

        if CGImageDestinationFinalize(dest) {
            let kb = (try? Data(contentsOf: url).count).map { $0 / 1024 } ?? 0
            fputs(
                "  ✓ \(name).gif (\(kb) KB, \(expanded.count) frames; \(frames.count) live + crossfades)\n",
                stderr
            )
        } else {
            fputs("  ✗ \(name).gif: finalize failed\n", stderr)
        }
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
