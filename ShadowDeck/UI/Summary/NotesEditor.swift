//
//  NotesEditor.swift
//  ShadowDeck
//
//  Scrollable rich-text notes editor with an embedded format toolbar
//  (system inspector bar is unreliable inside SwiftUI). Persists RTF.
//

import AppKit
import SwiftUI


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
        let state = bridge.formatState
        return HStack(spacing: 4) {
            // Shortcuts live on Format menu + NotesNSTextView (not toolbar buttons),
            // so they work while the text field is first responder.
            formatButton("bold", help: "Bold (⌘B)", isActive: state.isBold, action: bridge.bold)
            formatButton("italic", help: "Italic (⌘I)", isActive: state.isItalic, action: bridge.italic)
            formatButton("underline", help: "Underline (⌘U)", isActive: state.isUnderline, action: bridge.underline)

            Divider().frame(height: 18).padding(.horizontal, 4)

            formatButton("textformat.size", help: "Fonts…", action: bridge.showFonts)
            formatButton("paintpalette", help: "Text color…", action: bridge.showColors)

            Divider().frame(height: 18).padding(.horizontal, 4)

            formatButton(
                "list.bullet",
                help: "Bulleted list",
                isActive: state.isBulletedList,
                action: bridge.toggleBulletedList
            )
            formatButton(
                "list.number",
                help: "Numbered list",
                isActive: state.isNumberedList,
                action: bridge.toggleNumberedList
            )

            Divider().frame(height: 18).padding(.horizontal, 4)

            formatButton(
                "text.alignleft",
                help: "Align left",
                isActive: state.alignment == .left || state.alignment == .natural,
                action: bridge.alignLeft
            )
            formatButton(
                "text.aligncenter",
                help: "Align center",
                isActive: state.alignment == .center,
                action: bridge.alignCenter
            )
            formatButton(
                "text.alignright",
                help: "Align right",
                isActive: state.alignment == .right,
                action: bridge.alignRight
            )

            Spacer(minLength: 0)
        }
    }

    private func formatButton(
        _ systemImage: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(isActive ? .semibold : .regular))
                .frame(width: 28, height: 24)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - NSTextView host

/// Rich-text view that honors standard format key equivalents while first responder.
/// SwiftUI apps often lack the AppKit Format menu, so ⌘B / ⌘I / ⌘U would otherwise no-op.
final class NotesNSTextView: NSTextView {
    weak var formatBridge: NotesTextBridge?

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
            formatBridge?.refreshFormatState()
            return true
        case "i":
            NotesTextFormatting.toggleFontTrait(.italicFontMask, on: self)
            formatBridge?.refreshFormatState()
            return true
        case "u":
            NotesTextFormatting.toggleUnderline(on: self)
            formatBridge?.refreshFormatState()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    /// Keep the insertion point / selection in view when wrapping or typing past the clip.
    override func didChangeText() {
        super.didChangeText()
        scrollCaretIntoView()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting {
            scrollCaretIntoView()
        }
    }

    func scrollCaretIntoView() {
        let range = selectedRange()
        // Immediate scroll, then once after layout so soft-wrap line breaks are accounted for.
        scrollRangeToVisible(range)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollRangeToVisible(self.selectedRange())
            if let scrollView = self.enclosingScrollView {
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
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
        textView.formatBridge = bridge
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
            .foregroundColor: NSColor.textColor
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
        context.coordinator.bridge = bridge
        bridge.textView = textView
        // Defer: publishing @Published from makeNSView runs during a view update.
        bridge.refreshFormatStateDeferred()

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        bridge.textView = scrollView.documentView as? NSTextView
        if let notesView = scrollView.documentView as? NotesNSTextView {
            notesView.formatBridge = bridge
        }
        context.coordinator.bridge = bridge
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard context.coordinator.isEditing == false else { return }
        guard text != context.coordinator.lastExported else { return }
        Coordinator.load(text, into: textView)
        context.coordinator.lastExported = text
        bridge.refreshFormatStateDeferred()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        weak var textView: NSTextView?
        weak var bridge: NotesTextBridge?
        var isEditing = false
        var lastExported: String = ""
        private var saveWorkItem: DispatchWorkItem?

        init(_ parent: NotesTextView) {
            self.parent = parent
        }

        nonisolated func textDidBeginEditing(_ notification: Notification) {
            Task { @MainActor in
                self.isEditing = true
                self.bridge?.refreshFormatState()
            }
        }

        nonisolated func textDidEndEditing(_ notification: Notification) {
            Task { @MainActor in
                self.isEditing = false
                self.pushText()
                self.parent.onCommit?()
                self.bridge?.refreshFormatState()
            }
        }

        nonisolated func textDidChange(_ notification: Notification) {
            Task { @MainActor in
                self.pushText()
                self.bridge?.refreshFormatState()
                (self.textView as? NotesNSTextView)?.scrollCaretIntoView()
                self.saveWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    Task { @MainActor in self?.parent.onCommit?() }
                }
                self.saveWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
            }
        }

        nonisolated func textViewDidChangeSelection(_ notification: Notification) {
            Task { @MainActor in
                self.bridge?.refreshFormatState()
                (self.textView as? NotesNSTextView)?.scrollCaretIntoView()
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
                .foregroundColor: NSColor.textColor
            ]
        }

        static func export(from textView: NSTextView) -> String {
            let full = NSRange(location: 0, length: textView.string.utf16.count)
            if full.length > 0,
               let rtfData = textView.rtf(from: full),
               let rtf = String(data: rtfData, encoding: .utf8),
               !rtf.isEmpty {
                return rtf
            }
            return textView.string
        }
    }
}
