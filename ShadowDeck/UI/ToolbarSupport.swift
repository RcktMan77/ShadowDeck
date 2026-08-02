//
//  ToolbarSupport.swift
//  ShadowDeck
//
//  App chrome buttons (toolbars, list headers, sticky footers) as AppKit
//  `NSButton`s — consistent look and native tooltips across the app.
//
//  Prefer these for sticky toolbars and library headers. Keep SwiftUI `Button`
//  for form fields, menus, confirmation dialogs, and dense inline row actions.
//

import AppKit
import SwiftUI

// MARK: - Primary API

/// Toolbar / chrome control backed by `NSButton` (native tooltips + matching chrome).
struct AppChromeButton: View {
    enum Kind: Equatable {
        /// Symbol only (export, delete, look up, …).
        case icon(systemImage: String)
        /// Title only (Save, Done, Cancel, …).
        case title(String)
        /// Symbol + title (Refresh, New Campaign, Dice, back chevron, …).
        case labeled(title: String, systemImage: String)
    }

    enum Style: Equatable {
        case regular
        case prominent
        case destructive
    }

    var kind: Kind
    /// Hover help; defaults to the visible title / accessibility name.
    var help: String?
    var style: Style = .regular
    var isEnabled: Bool = true
    /// Single character for `NSButton.keyEquivalent` (e.g. `"s"`).
    var keyEquivalent: String = ""
    var keyModifiers: NSEvent.ModifierFlags = []
    var action: () -> Void

    init(
        kind: Kind,
        help: String? = nil,
        style: Style = .regular,
        isEnabled: Bool = true,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [],
        action: @escaping () -> Void
    ) {
        self.kind = kind
        self.help = help
        self.style = style
        self.isEnabled = isEnabled
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.action = action
    }

    // Convenience factories

    static func icon(
        _ systemImage: String,
        help: String,
        style: Style = .regular,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> AppChromeButton {
        AppChromeButton(
            kind: .icon(systemImage: systemImage),
            help: help,
            style: style,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func title(
        _ title: String,
        help: String? = nil,
        style: Style = .regular,
        isEnabled: Bool = true,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [],
        action: @escaping () -> Void
    ) -> AppChromeButton {
        AppChromeButton(
            kind: .title(title),
            help: help ?? title,
            style: style,
            isEnabled: isEnabled,
            keyEquivalent: keyEquivalent,
            keyModifiers: keyModifiers,
            action: action
        )
    }

    static func labeled(
        _ title: String,
        systemImage: String,
        help: String? = nil,
        style: Style = .regular,
        isEnabled: Bool = true,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [],
        action: @escaping () -> Void
    ) -> AppChromeButton {
        AppChromeButton(
            kind: .labeled(title: title, systemImage: systemImage),
            help: help ?? title,
            style: style,
            isEnabled: isEnabled,
            keyEquivalent: keyEquivalent,
            keyModifiers: keyModifiers,
            action: action
        )
    }

    var body: some View {
        ChromeNSButton(
            kind: kind,
            help: resolvedHelp,
            style: style,
            isEnabled: isEnabled,
            keyEquivalent: keyEquivalent,
            keyModifiers: keyModifiers,
            action: action
        )
        .frame(minHeight: 28)
        .fixedSize(horizontal: kindIsIconOnly, vertical: false)
        .frame(width: kindIsIconOnly ? 32 : nil, height: kindIsIconOnly ? 28 : nil)
        .accessibilityLabel(resolvedHelp)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var kindIsIconOnly: Bool {
        if case .icon = kind { return true }
        return false
    }

    private var resolvedHelp: String {
        if let help, !help.isEmpty { return help }
        switch kind {
        case .icon(let systemImage):
            return systemImage
        case .title(let title):
            return title
        case .labeled(let title, _):
            return title
        }
    }
}

/// Backward-compatible icon-only toolbar control.
struct IconToolbarButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    var action: () -> Void

    var body: some View {
        AppChromeButton.icon(
            systemImage,
            help: title,
            style: role == .destructive ? .destructive : .regular,
            action: action
        )
    }
}

// MARK: - AppKit bridge

private struct ChromeNSButton: NSViewRepresentable {
    var kind: AppChromeButton.Kind
    var help: String
    var style: AppChromeButton.Style
    var isEnabled: Bool
    var keyEquivalent: String
    var keyModifiers: NSEvent.ModifierFlags
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> IntrinsicSizingButton {
        let button = IntrinsicSizingButton(frame: .zero)
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked)
        button.imageScaling = .scaleProportionallyDown
        apply(button)
        return button
    }

    func updateNSView(_ button: IntrinsicSizingButton, context: Context) {
        context.coordinator.action = action
        apply(button)
        button.invalidateIntrinsicContentSize()
    }

    private func apply(_ button: IntrinsicSizingButton) {
        button.toolTip = help
        button.isEnabled = isEnabled
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = keyModifiers
        button.setAccessibilityLabel(help)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

        switch kind {
        case .icon(let systemImage):
            button.title = ""
            button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: help)?
                .withSymbolConfiguration(symbolConfig)
            button.imagePosition = .imageOnly

        case .title(let title):
            button.title = title
            button.image = nil
            button.imagePosition = .noImage

        case .labeled(let title, let systemImage):
            button.title = title
            button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
                .withSymbolConfiguration(symbolConfig)
            button.imagePosition = .imageLeading
        }

        switch style {
        case .regular:
            button.contentTintColor = nil
            button.bezelColor = nil
        case .prominent:
            button.contentTintColor = nil
            button.bezelColor = .controlAccentColor
        case .destructive:
            button.contentTintColor = .systemRed
            button.bezelColor = nil
        }
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

/// Reports a sensible intrinsic size so SwiftUI `fixedSize()` lays out text buttons correctly.
private final class IntrinsicSizingButton: NSButton {
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        // Toolbar bezel can report a tiny height when title is empty (icon-only).
        size.height = max(size.height, 28)
        if imagePosition == .imageOnly {
            size.width = max(size.width, 28)
        } else {
            size.width = max(size.width, 44)
        }
        return size
    }
}
