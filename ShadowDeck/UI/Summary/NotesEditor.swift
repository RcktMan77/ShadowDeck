//
//  NotesEditor.swift
//  ShadowDeck
//
//  Scrollable rich-text notes editor with an embedded format toolbar
//  (system inspector bar is unreliable inside SwiftUI). Persists RTF.
//

import AppKit
import SwiftUI

/// Shared formatting helpers for toolbar, Format menu, and ⌘B / ⌘I / ⌘U key equivalents.
@MainActor
enum NotesTextFormatting {
    /// Walk the responder chain for the key window’s focused text view.
    static func focusedTextView() -> NSTextView? {
        var responder: NSResponder? = NSApp.keyWindow?.firstResponder
        while let current = responder {
            if let textView = current as? NSTextView, textView.isEditable, textView.isRichText {
                return textView
            }
            responder = current.nextResponder
        }
        return nil
    }

    static func applyBoldToFocusedTextView() {
        guard let textView = focusedTextView() else { return }
        toggleFontTrait(.boldFontMask, on: textView)
    }

    static func applyItalicToFocusedTextView() {
        guard let textView = focusedTextView() else { return }
        toggleFontTrait(.italicFontMask, on: textView)
    }

    static func applyUnderlineToFocusedTextView() {
        guard let textView = focusedTextView() else { return }
        toggleUnderline(on: textView)
    }

    static func toggleFontTrait(_ trait: NSFontTraitMask, on textView: NSTextView) {
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

    static func toggleUnderline(on textView: NSTextView) {
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
}

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
        guard let textView else { return }
        NotesTextFormatting.toggleFontTrait(.boldFontMask, on: textView)
    }

    func italic() {
        focus()
        guard let textView else { return }
        NotesTextFormatting.toggleFontTrait(.italicFontMask, on: textView)
    }

    func underline() {
        focus()
        guard let textView else { return }
        NotesTextFormatting.toggleUnderline(on: textView)
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

    func toggleBulletedList() {
        focus()
        applyListToggle(kind: .bullet)
    }

    func toggleNumberedList() {
        focus()
        applyListToggle(kind: .numbered)
    }

    /// Rebuild the covered paragraphs as one attributed replacement.
    /// Avoids multi-pass range math that could throw after the first edit.
    private func applyListToggle(kind: NotesListKind) {
        guard let textView, let storage = textView.textStorage else { return }

        let font = (textView.typingAttributes[.font] as? NSFont)
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let color = (textView.typingAttributes[.foregroundColor] as? NSColor) ?? .textColor
        let listStyle = Self.hangingListParagraphStyle()
        let plainStyle = NSParagraphStyle.default

        // Empty document → insert one list line with a visible marker.
        if storage.length == 0 {
            let marker = kind.markerPrefix(index: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: listStyle,
            ]
            storage.setAttributedString(NSAttributedString(string: marker, attributes: attrs))
            textView.typingAttributes = attrs
            textView.setSelectedRange(NSRange(location: (marker as NSString).length, length: 0))
            textView.didChangeText()
            return
        }

        let selection = textView.selectedRange().clamped(to: storage.length)
        let ns = storage.string as NSString
        let cover = Self.paragraphCover(for: selection, in: ns)
        guard cover.length >= 0, cover.location + cover.length <= ns.length else { return }

        // Split into paragraph bodies + whether each ended with a newline.
        struct Para {
            var body: String
            var hadTrailingNewline: Bool
        }
        var paras: [Para] = []
        var cursor = cover.location
        let coverEnd = NSMaxRange(cover)
        while cursor < coverEnd {
            let pr = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            let clamped = NSRange(
                location: pr.location,
                length: min(pr.length, coverEnd - pr.location)
            )
            guard clamped.length > 0 || paras.isEmpty else { break }
            let raw = ns.substring(with: clamped)
            let hadNL = raw.hasSuffix("\n") || raw.hasSuffix("\r\n") || raw.hasSuffix("\r")
            var body = raw
            if body.hasSuffix("\r\n") {
                body = String(body.dropLast(2))
            } else if body.hasSuffix("\n") || body.hasSuffix("\r") {
                body = String(body.dropLast())
            }
            paras.append(Para(body: body, hadTrailingNewline: hadNL))
            let next = pr.location + max(pr.length, 1)
            if next <= cursor { break }
            cursor = next
        }

        // Drop a trailing empty paragraph from a selection that ends on a newline.
        if paras.count > 1, paras.last?.body.isEmpty == true, paras.last?.hadTrailingNewline == true {
            paras.removeLast()
        }
        guard !paras.isEmpty else { return }

        let alreadyListed = paras.allSatisfy { kind.matchesMarker(in: $0.body) }
        let enabling = !alreadyListed

        // Build replacement plain string first.
        var newBodies: [String] = []
        if enabling {
            for (i, p) in paras.enumerated() {
                let stripped = NotesListKind.stripAnyMarker(from: p.body)
                newBodies.append(kind.markerPrefix(index: i + 1) + stripped)
            }
        } else {
            newBodies = paras.map { NotesListKind.stripAnyMarker(from: $0.body) }
        }

        let replacement = NSMutableAttributedString()
        let style = enabling ? listStyle : plainStyle
        for (i, body) in newBodies.enumerated() {
            var line = body
            // Preserve structure: keep original trailing newlines; ensure separators between items.
            if paras[i].hadTrailingNewline || i < newBodies.count - 1 {
                if !line.hasSuffix("\n") { line += "\n" }
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style,
            ]
            if storage.length > 0 {
                let sampleLoc = min(cover.location, storage.length - 1)
                let existing = storage.attributes(at: sampleLoc, effectiveRange: nil)
                if let f = existing[.font] { attrs[.font] = f }
                if let c = existing[.foregroundColor] { attrs[.foregroundColor] = c }
            }
            attrs[.paragraphStyle] = style
            replacement.append(NSAttributedString(string: line, attributes: attrs))
        }

        // If cover ended mid-document without including final newline of last para, OK.
        // Single atomic replace — no intermediate invalid ranges.
        storage.beginEditing()
        storage.replaceCharacters(in: cover, with: replacement)
        storage.endEditing()

        var typing = textView.typingAttributes
        typing[.paragraphStyle] = style
        typing[.font] = font
        typing[.foregroundColor] = color
        textView.typingAttributes = typing

        let newLen = replacement.length
        let caret = min(cover.location + newLen, storage.length)
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.didChangeText()
    }

    private enum NotesListKind: Equatable {
        case bullet
        case numbered

        func markerPrefix(index: Int) -> String {
            switch self {
            case .bullet: return "• "
            case .numbered: return "\(index). "
            }
        }

        func matchesMarker(in body: String) -> Bool {
            switch self {
            case .bullet:
                return NotesListKind.bulletRegex.firstMatch(
                    in: body,
                    options: [],
                    range: NSRange(location: 0, length: (body as NSString).length)
                ) != nil
            case .numbered:
                return NotesListKind.numberRegex.firstMatch(
                    in: body,
                    options: [],
                    range: NSRange(location: 0, length: (body as NSString).length)
                ) != nil
            }
        }

        static func stripAnyMarker(from body: String) -> String {
            let ns = body as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let m = bulletRegex.firstMatch(in: body, options: [], range: full) {
                return ns.substring(from: m.range.length)
            }
            if let m = numberRegex.firstMatch(in: body, options: [], range: full) {
                return ns.substring(from: m.range.length)
            }
            // Also strip legacy tab-based markers from earlier attempts.
            if let m = legacyTabBulletRegex.firstMatch(in: body, options: [], range: full) {
                return ns.substring(from: m.range.length)
            }
            if let m = legacyTabNumberRegex.firstMatch(in: body, options: [], range: full) {
                return ns.substring(from: m.range.length)
            }
            return body
        }

        static let bulletRegex = try! NSRegularExpression(pattern: #"^[•\-\*▪◦][ \t]+"#)
        static let numberRegex = try! NSRegularExpression(pattern: #"^\d+\.[ \t]+"#)
        static let legacyTabBulletRegex = try! NSRegularExpression(pattern: #"^[•\-\*▪◦]\t"#)
        static let legacyTabNumberRegex = try! NSRegularExpression(pattern: #"^\d+\.\t"#)
    }

    private static func hangingListParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.setParagraphStyle(.default)
        style.firstLineHeadIndent = 0
        style.headIndent = 22
        style.textLists = []
        return style
    }

    private static func paragraphCover(for selection: NSRange, in ns: NSString) -> NSRange {
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let loc = max(0, min(selection.location, ns.length))
        if selection.length == 0 {
            let safe = min(loc, ns.length - 1)
            return ns.paragraphRange(for: NSRange(location: safe, length: 0))
        }
        let end = min(NSMaxRange(selection), ns.length)
        let startPara = ns.paragraphRange(for: NSRange(location: min(loc, ns.length - 1), length: 0))
        let endPara = ns.paragraphRange(for: NSRange(location: max(min(end - 1, ns.length - 1), 0), length: 0))
        return NSRange(location: startPara.location, length: NSMaxRange(endPara) - startPara.location)
    }
}

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        let loc = max(0, min(location, length))
        let len = max(0, min(self.length, length - loc))
        return NSRange(location: loc, length: len)
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
            // Shortcuts live on Format menu + NotesNSTextView (not toolbar buttons),
            // so they work while the text field is first responder.
            formatButton("bold", help: "Bold (⌘B)", action: bridge.bold)
            formatButton("italic", help: "Italic (⌘I)", action: bridge.italic)
            formatButton("underline", help: "Underline (⌘U)", action: bridge.underline)

            Divider().frame(height: 18).padding(.horizontal, 4)

            formatButton("textformat.size", help: "Fonts…", action: bridge.showFonts)
            formatButton("paintpalette", help: "Text color…", action: bridge.showColors)

            Divider().frame(height: 18).padding(.horizontal, 4)

            formatButton("list.bullet", help: "Bulleted list", action: bridge.toggleBulletedList)
            formatButton("list.number", help: "Numbered list", action: bridge.toggleNumberedList)

            Divider().frame(height: 18).padding(.horizontal, 4)

            formatButton("text.alignleft", help: "Align left", action: bridge.alignLeft)
            formatButton("text.aligncenter", help: "Align center", action: bridge.alignCenter)
            formatButton("text.alignright", help: "Align right", action: bridge.alignRight)

            Spacer(minLength: 0)
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

/// Rich-text view that honors standard format key equivalents while first responder.
/// SwiftUI apps often lack the AppKit Format menu, so ⌘B / ⌘I / ⌘U would otherwise no-op.
private final class NotesNSTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Plain ⌘ only (no ⇧ / ⌥ / ⌃) so we don't steal other bindings.
        guard flags == .command,
              let key = event.charactersIgnoringModifiers?.lowercased(),
              key.count == 1
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "b":
            NotesTextFormatting.toggleFontTrait(.boldFontMask, on: self)
            return true
        case "i":
            NotesTextFormatting.toggleFontTrait(.italicFontMask, on: self)
            return true
        case "u":
            NotesTextFormatting.toggleUnderline(on: self)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

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

        let textView = NotesNSTextView()
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
