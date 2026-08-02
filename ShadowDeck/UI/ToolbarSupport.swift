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
///
/// Always **hugs content** (never expands to fill an `HStack` / `Spacer` region).
/// Uses **regular** control size so chrome matches standard SwiftUI bordered controls.
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

    /// Host height for regular rounded NSButtons (~system bordered button).
    static let chromeHeight: CGFloat = 34

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
        .frame(height: Self.chromeHeight)
        .fixedSize(horizontal: true, vertical: true)
        .layoutPriority(1)
        .accessibilityLabel(resolvedHelp)
        .opacity(isEnabled ? 1 : 0.45)
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

/// Host that reports a fixed height and centers the real `NSButton` so SwiftUI
/// HStacks line it up with neighboring controls.
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

    func makeNSView(context: Context) -> ChromeButtonHost {
        let host = ChromeButtonHost()
        host.button.target = context.coordinator
        host.button.action = #selector(Coordinator.clicked)
        apply(to: host.button)
        return host
    }

    func updateNSView(_ host: ChromeButtonHost, context: Context) {
        context.coordinator.action = action
        apply(to: host.button)
        host.needsLayout = true
        host.invalidateIntrinsicContentSize()
    }

    private func apply(to button: NSButton) {
        button.toolTip = help
        button.isEnabled = isEnabled
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = keyModifiers
        button.setAccessibilityLabel(help)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)

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

/// Fixed-height host; button is centered so neighboring SwiftUI controls align.
private final class ChromeButtonHost: NSView {
    let button: NSButton = {
        let b = NSButton(frame: .zero)
        b.bezelStyle = .rounded
        b.isBordered = true
        b.controlSize = .regular
        b.setButtonType(.momentaryPushIn)
        b.imageScaling = .scaleProportionallyDown
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        return b
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        button.sizeToFit()
        var w = button.fittingSize.width
        if w < 1 {
            w = button.intrinsicContentSize.width
        }
        if button.imagePosition == .imageOnly {
            w = max(w, 32)
        } else {
            w = max(w + 8, 56)
        }
        return NSSize(width: w, height: AppChromeButton.chromeHeight)
    }

    override func layout() {
        super.layout()
        button.sizeToFit()
        var size = button.fittingSize
        if size.width < 1 || size.height < 1 {
            size = button.intrinsicContentSize
        }
        if button.imagePosition == .imageOnly {
            size.width = max(size.width, 32)
            size.height = min(max(size.height, 28), AppChromeButton.chromeHeight)
        } else {
            size.width = max(size.width + 8, 56)
            size.height = min(max(size.height, 28), AppChromeButton.chromeHeight)
        }
        // Vertically center within the fixed host height.
        let y = (bounds.height - size.height) / 2
        button.frame = NSRect(
            x: 0,
            y: max(0, y),
            width: min(size.width, max(bounds.width, size.width)),
            height: size.height
        )
    }

    /// Zero out AppKit alignment insets so SwiftUI doesn’t offset us downward.
    override var alignmentRectInsets: NSEdgeInsets {
        .init(top: 0, left: 0, bottom: 0, right: 0)
    }
}
