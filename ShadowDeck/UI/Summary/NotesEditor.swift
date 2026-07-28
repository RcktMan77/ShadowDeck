//
//  NotesEditor.swift
//  ShadowDeck
//
//  Scrollable rich-text notes editor with an embedded format toolbar
//  (system inspector bar is unreliable inside SwiftUI). Persists RTF.
//

import AppKit
import SwiftUI

/// Shared handle so the toolbar can talk to the NSTextView.
@MainActor
final class NotesTextBridge: ObservableObject {
    weak var textView: NSTextView?

    func focus() {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
    }

    func bold() {
        focus()
        toggleFontTrait(.boldFontMask)
    }

    func italic() {
        focus()
        toggleFontTrait(.italicFontMask)
    }

    func underline() {
        focus()
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let current = attrs[.underlineStyle] as? Int ?? 0
            attrs[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes = attrs
            return
        }
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        var anyUnderlined = false
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
            if let style = value as? Int, style != 0 { anyUnderlined = true }
        }
        let newStyle = anyUnderlined ? 0 : NSUnderlineStyle.single.rawValue
        storage.addAttribute(.underlineStyle, value: newStyle, range: range)
        storage.endEditing()
        textView.didChangeText()
    }

    func showFonts() {
        focus()
        if let textView {
            NSFontManager.shared.target = textView
        }
        NSFontManager.shared.orderFrontFontPanel(nil)
    }

    func showColors() {
        focus()
        NSApp.orderFrontColorPanel(nil)
    }

    func alignLeft() {
        focus()
        textView?.alignLeft(nil)
    }

    func alignCenter() {
        focus()
        textView?.alignCenter(nil)
    }

    func alignRight() {
        focus()
        textView?.alignRight(nil)
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let manager = NSFontManager.shared
        let range = textView.selectedRange()

        if range.length == 0 {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            if manager.traits(of: font).contains(trait) {
                attrs[.font] = manager.convert(font, toNotHaveTrait: trait)
            } else {
                attrs[.font] = manager.convert(font, toHaveTrait: trait)
            }
            textView.typingAttributes = attrs
            return
        }

        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let next: NSFont
            if manager.traits(of: font).contains(trait) {
                next = manager.convert(font, toNotHaveTrait: trait)
            } else {
                next = manager.convert(font, toHaveTrait: trait)
            }
            storage.addAttribute(.font, value: next, range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
    }
}

struct NotesEditor: View {
    @Binding var text: String
    var onCommit: (() -> Void)?

    @StateObject private var bridge = NotesTextBridge()

    var body: some View {
        VStack(spacing: 0) {
            formatToolbar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            NotesTextView(text: $text, bridge: bridge, onCommit: onCommit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        }
    }

    private var formatToolbar: some View {
        HStack(spacing: 4) {
            formatButton("bold", help: "Bold (⌘B)", action: bridge.bold)
            formatButton("italic", help: "Italic (⌘I)", action: bridge.italic)
            formatButton("underline", help: "Underline (⌘U)", action: bridge.underline)

            Divider().frame(height: 18).padding(.horizontal, 4)

            formatButton("textformat.size", help: "Fonts…", action: bridge.showFonts)
            formatButton("paintpalette", help: "Text color…", action: bridge.showColors)

            Divider().frame(height: 18).padding(.horizontal, 4)

            formatButton("text.alignleft", help: "Align left", action: bridge.alignLeft)
            formatButton("text.aligncenter", help: "Align center", action: bridge.alignCenter)
            formatButton("text.alignright", help: "Align right", action: bridge.alignRight)

            Spacer(minLength: 0)

            Text("Select text, then format")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - NSTextView host

private struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    var bridge: NotesTextBridge
    var onCommit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        // System inspector bar is flaky under SwiftUI; we ship our own toolbar.
        textView.usesInspectorBar = false
        textView.usesFontPanel = true
        textView.usesRuler = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.textColor,
        ]
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.backgroundColor = NSColor.textBackgroundColor

        Coordinator.load(text, into: textView)
        context.coordinator.lastExported = text
        context.coordinator.textView = textView
        bridge.textView = textView

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        bridge.textView = scrollView.documentView as? NSTextView
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard context.coordinator.isEditing == false else { return }
        guard text != context.coordinator.lastExported else { return }
        Coordinator.load(text, into: textView)
        context.coordinator.lastExported = text
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        weak var textView: NSTextView?
        var isEditing = false
        var lastExported: String = ""
        private var saveWorkItem: DispatchWorkItem?

        init(_ parent: NotesTextView) {
            self.parent = parent
        }

        nonisolated func textDidBeginEditing(_ notification: Notification) {
            Task { @MainActor in self.isEditing = true }
        }

        nonisolated func textDidEndEditing(_ notification: Notification) {
            Task { @MainActor in
                self.isEditing = false
                self.pushText()
                self.parent.onCommit?()
            }
        }

        nonisolated func textDidChange(_ notification: Notification) {
            Task { @MainActor in
                self.pushText()
                self.saveWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    Task { @MainActor in self?.parent.onCommit?() }
                }
                self.saveWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
            }
        }

        private func pushText() {
            guard let textView else { return }
            let exported = Self.export(from: textView)
            lastExported = exported
            parent.text = exported
        }

        static func looksLikeRTF(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{\\rtf")
        }

        static func load(_ value: String, into textView: NSTextView) {
            let full = NSRange(location: 0, length: textView.string.utf16.count)
            if looksLikeRTF(value), let data = value.data(using: .utf8) {
                textView.replaceCharacters(in: full, withRTF: data)
                return
            }
            textView.string = value
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.textColor,
            ]
        }

        static func export(from textView: NSTextView) -> String {
            let full = NSRange(location: 0, length: textView.string.utf16.count)
            if full.length > 0,
               let rtfData = textView.rtf(from: full),
               let rtf = String(data: rtfData, encoding: .utf8),
               !rtf.isEmpty
            {
                return rtf
            }
            return textView.string
        }
    }
}
