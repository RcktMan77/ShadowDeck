//
//  LaunchSplashView.swift
//  ShadowDeck
//
//  Phase 9A — branded cold-start splash with cyberpunk title + loading quips.
//

import AppKit
import CoreText
import SwiftUI

struct LaunchSplashView: View {
    var onDismiss: () -> Void

    @State private var opacity: Double = 0
    @State private var titleScale: CGFloat = 0.96
    @State private var didDismiss = false
    @State private var quipIndex = 0
    @State private var quipOpacity: Double = 0
    @State private var quipTask: Task<Void, Never>?

    /// Tongue-in-cheek “deck boot” lines — not tied to real loading work.
    private static let quips: [String] = [
        "Jacking into local hosts…",
        "Calibrating the smartlink…",
        "Greasing a fixer with leftover karma…",
        "Warming the cyberdeck coils…",
        "Decrypting your SIN (again)…",
        "Telling the bouncer you’re on the list…"
    ]

    /// ~1.7s per quip × 4 quips + intro/outro ≈ readable without overstaying.
    private static let quipsToShow = 4
    private static let secondsPerQuip: Double = 1.7
    private static let introDelay: Double = 0.55

    var body: some View {
        // Opaque black for the full lifetime so intro fades never reveal the deck underneath.
        ZStack {
            Color.black

            ZStack {
                if let image = BrandArtLoader.splashImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(0.9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.08, blue: 0.16),
                            Color(red: 0.12, green: 0.04, blue: 0.18),
                            Color.black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                // Vignette over the art only (keeps corners solid black).
                LinearGradient(
                    colors: [
                        .black.opacity(0.55),
                        .black.opacity(0.08),
                        .black.opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                    Canvas { ctx, size in
                        let t = context.date.timeIntervalSinceReferenceDate
                        for i in 0..<36 {
                            let seed = Double(i) * 17.13
                            let x = (seed * 37).truncatingRemainder(dividingBy: size.width)
                            let speed = 80 + Double(i % 7) * 18
                            let y = (t * speed + seed * 40).truncatingRemainder(dividingBy: size.height + 40) - 20
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: y))
                            path.addLine(to: CGPoint(x: x - 2, y: y + 14))
                            ctx.stroke(
                                path,
                                with: .color(.white.opacity(0.07 + Double(i % 3) * 0.03)),
                                lineWidth: 1
                            )
                        }
                    }
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer()

                    Text("ShadowDeck")
                        .font(BrandFonts.title(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.95, blue: 1.0),
                                    Color(red: 0.85, green: 0.35, blue: 0.95)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .cyan.opacity(0.55), radius: 14)
                        .shadow(color: .purple.opacity(0.35), radius: 8)
                        .scaleEffect(titleScale)
                        .tracking(3)

                    Text("Character · Campaign · Deck")
                        .font(BrandFonts.subtitle(size: 16))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(2.5)
                        .padding(.top, 10)

                    Text("Unofficial Shadowrun fan tool for macOS")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 6)

                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Static chrome — never participates in quip opacity animation.
                            Text("CYBERDECK // BOOT")
                                .font(BrandFonts.mono(size: 10))
                                .foregroundStyle(Color.cyan.opacity(0.65))
                                .tracking(1.5)
                                .transaction { $0.animation = nil }

                            // Fixed-height slot so swapping quips never reflows this row.
                            // Opacity animation is scoped here only (not a global withAnimation).
                            Text(Self.quips[quipIndex % Self.quips.count])
                                .font(BrandFonts.mono(size: 13))
                                .foregroundStyle(.white.opacity(0.9))
                                .opacity(quipOpacity)
                                .animation(.easeInOut(duration: 0.28), value: quipOpacity)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: 420, minHeight: 36, maxHeight: 36, alignment: .topLeading)
                        }

                        Spacer(minLength: 12)

                        Text("Click or any key to skip")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                            .transaction { $0.animation = nil }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 28)
                }
            }
            .opacity(opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(.all)
        // Key skip via local monitor (not `.focusable()` — that draws a system focus ring).
        .onAppear {
            BrandFonts.registerIfNeeded()
            withAnimation(.easeOut(duration: 0.55)) {
                opacity = 1
                titleScale = 1
            }
            startQuipCycle()
            installKeyMonitor()
        }
        .onDisappear {
            quipTask?.cancel()
            removeKeyMonitor()
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onReceive(NotificationCenter.default.publisher(for: .launchSplashSkipKey)) { _ in
            dismiss()
        }
    }

    // MARK: - Key skip (no focus ring)

    @State private var keyMonitor: Any?

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let fr = NSApp.keyWindow?.firstResponder,
               fr is NSTextView || fr is NSTextField {
                return event
            }
            NotificationCenter.default.post(name: .launchSplashSkipKey, object: nil)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func startQuipCycle() {
        quipTask?.cancel()
        quipTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.introDelay * 1_000_000_000))
            for i in 0..<Self.quipsToShow {
                if Task.isCancelled || didDismiss { return }
                quipIndex = i
                quipOpacity = 0
                await Task.yield()
                if Task.isCancelled || didDismiss { return }
                quipOpacity = 1
                try? await Task.sleep(nanoseconds: UInt64(Self.secondsPerQuip * 1_000_000_000))
                if Task.isCancelled || didDismiss { return }
                quipOpacity = 0
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            if !didDismiss {
                dismiss()
            }
        }
    }

    private func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        quipTask?.cancel()
        removeKeyMonitor()
        // Immediate hand-off to the app veil; parent keeps cover while chrome/size settle.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            opacity = 0
            onDismiss()
        }
    }
}

private extension Notification.Name {
    static let launchSplashSkipKey = Notification.Name("com.shadowdeck.launchSplash.skipKey")
}

// MARK: - Brand fonts

enum BrandFonts {
    /// Font registration is process-global and intentionally one-shot.
    nonisolated(unsafe) private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        let names = ["Orbitron.ttf", "Rajdhani-Bold.ttf"]
        for name in names {
            let base = name.replacingOccurrences(of: ".ttf", with: "")
            let candidates: [URL?] = [
                Bundle.main.url(forResource: base, withExtension: "ttf", subdirectory: "Fonts"),
                Bundle.main.url(forResource: base, withExtension: "ttf"),
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources/Fonts/\(name)")
            ]
            for url in candidates.compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                break
            }
        }
    }

    static func title(size: CGFloat) -> Font {
        if NSFont(name: "Orbitron", size: size) != nil
            || NSFont(name: "Orbitron-Bold", size: size) != nil {
            return .custom("Orbitron", size: size).weight(.bold)
        }
        if NSFont(name: "Rajdhani-Bold", size: size) != nil {
            return .custom("Rajdhani-Bold", size: size)
        }
        return .system(size: size, weight: .heavy, design: .default)
    }

    static func subtitle(size: CGFloat) -> Font {
        if NSFont(name: "Rajdhani-Bold", size: size) != nil {
            return .custom("Rajdhani-Bold", size: size)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }

    static func mono(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

enum BrandArtLoader {
    static var splashImage: NSImage? {
        let name = "launch_splash"
        let bundle = Bundle.main
        // Xcode may flatten Resources/Brand into the Resources root.
        if let url = bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Brand")
            ?? bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/Brand")
            ?? bundle.url(forResource: name, withExtension: "jpg") {
            return NSImage(contentsOf: url)
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Brand/\(name).jpg")
        return NSImage(contentsOf: dev)
    }
}

#Preview {
    LaunchSplashView {}
        .frame(width: 1100, height: 720)
}
