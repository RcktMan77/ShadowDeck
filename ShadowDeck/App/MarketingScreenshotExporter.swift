//
//  MarketingScreenshotExporter.swift
//  ShadowDeck
//
//  Captures marquee UI screenshots from *inside* the app process so we don't
//  depend on Screen Recording TCC (which redacts other apps from external
//  screencapture). Trigger with:
//
//    SHADOWDECK_CAPTURE_SCREENSHOTS=1 \
//    SHADOWDECK_SCREENSHOT_DIR=/path/to/Docs/Screenshots \
//    open ShadowDeck.app
//

import AppKit
import Foundation

enum MarketingScreenshotExporter {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SHADOWDECK_CAPTURE_SCREENSHOTS"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--capture-screenshots")
    }

    /// Writable location inside the app sandbox (Application Support).
    /// The capture shell script copies from here into `Docs/Screenshots`.
    static var outputDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("ShadowDeck", isDirectory: true)
            .appendingPathComponent("MarketingScreenshots", isDirectory: true)
    }

    /// Posted as the sequence advances so ContentView / splash can change state.
    static let phaseNotification = Notification.Name("com.shadowdeck.marketingScreenshotPhase")

    enum Phase: String {
        case splash
        case library
        case generationRole
        case characterSheet
        case finished
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

        // Let the first frame (splash) settle.
        try? await Task.sleep(nanoseconds: 900_000_000)
        await capture(named: "01-splash", to: dir)

        post(.library)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        await capture(named: "02-library", to: dir)

        post(.generationRole)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await capture(named: "03-generation-role", to: dir)

        post(.characterSheet)
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        await capture(named: "04-character-sheet", to: dir)

        post(.finished)
        fputs("Marketing screenshots complete.\n", stderr)
        try? await Task.sleep(nanoseconds: 300_000_000)
        NSApp.terminate(nil)
    }

    @MainActor
    private static func post(_ phase: Phase) {
        NotificationCenter.default.post(name: phaseNotification, object: phase.rawValue)
    }

    @MainActor
    private static func capture(named name: String, to directory: URL) async {
        // Extra layout pass.
        try? await Task.sleep(nanoseconds: 200_000_000)
        NSApp.windows.forEach { $0.layoutIfNeeded() }

        guard let image = snapshotLargestWindow() else {
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
    private static func snapshotLargestWindow() -> NSImage? {
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

        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        return snapshotViaLayer(view: view, window: window)
    }

    @MainActor
    private static func snapshotViaLayer(view: NSView, window: NSWindow) -> NSImage? {
        // Prefer AppKit's display cache — correct orientation for SwiftUI hosting views.
        let bounds = view.bounds
        if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            view.cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            return image
        }

        // Fallback: layer render with Y-flip into bitmap coordinates.
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
        // Bitmap context origin is bottom-left; flip so layer (top-left) draws upright.
        cg.translateBy(x: 0, y: CGFloat(pixelH))
        cg.scaleBy(x: scale, y: -scale)
        layer.render(in: cg)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
