//
//  ToolbarSupport.swift
//  ShadowDeck
//
//  Shared sticky-toolbar chrome: icon-only actions with reliable macOS tooltips.
//
//  SwiftUI `.help()` is flaky on custom HStack toolbars (icon-only especially).
//  These controls are AppKit `NSButton`s with native `toolTip`.
//

import AppKit
import SwiftUI

/// Icon-only toolbar control backed by `NSButton` so hover tooltips work consistently.
struct IconToolbarButton: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    var action: () -> Void

    init(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = role == .destructive
        self.action = action
    }

    var body: some View {
        IconToolbarNSButton(
            title: title,
            systemImage: systemImage,
            isDestructive: isDestructive,
            action: action
        )
        .frame(width: 32, height: 28)
        .accessibilityLabel(title)
    }
}

// MARK: - AppKit button

private struct IconToolbarNSButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var isDestructive: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked)
        button.toolTip = title
        button.imageScaling = .scaleProportionallyDown
        applyAppearance(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = title
        applyAppearance(button)
    }

    private func applyAppearance(_ button: NSButton) {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        button.image = image
        button.contentTintColor = isDestructive ? .systemRed : nil
        // Keep tooltip + a11y in sync with title changes.
        button.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func clicked() {
            action()
        }
    }
}
