import AppKit
import PDFKit
import SwiftUI

// MARK: - Keyboard-aware PDFView

/// PDFView that accepts key focus and handles page / scroll keys.
final class KeyboardPDFView: PDFView {
    /// 1-based page jump (←/→, Page Up/Down, Home/End).
    var onJumpToPage: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Defer focus — claiming first responder mid-hierarchy attach can re-enter SwiftUI updates.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Ignore when user is typing in a field (search, page number).
        if let fr = window?.firstResponder,
           fr is NSTextView || fr is NSTextField || fr is NSComboBox {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 125: // ↓ — scroll toward later pages (non-flipped doc: lower y)
            scrollBy(dy: -lineScrollStep)
        case 126: // ↑ — earlier pages
            scrollBy(dy: lineScrollStep)
        case 121: // Page Down → next page
            jumpPage(delta: 1)
        case 116: // Page Up → previous page
            jumpPage(delta: -1)
        case 124: // → next page
            jumpPage(delta: 1)
        case 123: // ← previous page
            jumpPage(delta: -1)
        case 115: // Home
            onJumpToPage?(1)
        case 119: // End
            if let count = document?.pageCount, count > 0 {
                onJumpToPage?(count)
            }
        default:
            super.keyDown(with: event)
        }
    }

    private var lineScrollStep: CGFloat { max(36, bounds.height * 0.08) }

    private func scrollBy(dy: CGFloat) {
        guard let scroll = findScrollView(self) else { return }
        var origin = scroll.contentView.bounds.origin
        // Continuous PDF document view is not flipped: page 0 sits at high y.
        // Positive dy → earlier pages; negative dy → later pages.
        origin.y += dy
        let docH = scroll.documentView?.bounds.height ?? 0
        let clipH = scroll.contentView.bounds.height
        let maxY = max(0, docH - clipH)
        origin.y = min(max(0, origin.y), maxY)
        scroll.contentView.setBoundsOrigin(origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func jumpPage(delta: Int) {
        guard let document, let current = currentPage else { return }
        let idx = document.index(for: current) + delta
        let clamped = max(0, min(document.pageCount - 1, idx))
        onJumpToPage?(clamped + 1)
    }

    private func findScrollView(_ root: NSView) -> NSScrollView? {
        if let s = root as? NSScrollView { return s }
        for sub in root.subviews {
            if let f = findScrollView(sub) { return f }
        }
        return nil
    }
}


// MARK: - Host view

/// Owns the PDFView. Canvas for zoom = `bounds` (window points), never the
/// magnified NSScrollView contentView bounds (those grow/shrink with scale).
final class PDFCanvasHostView: NSView {
    let pdfView: KeyboardPDFView
    var onLayoutZoom: (() -> Void)?

    private var lastBounds: CGSize = .zero

    init() {
        pdfView = KeyboardPDFView()
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displayBox = .mediaBox
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor.windowBackgroundColor
        pdfView.minScaleFactor = 0.05
        pdfView.maxScaleFactor = 20
        pdfView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Drawable canvas in window points. Independent of PDFKit magnification.
    /// Prefer the internal scroll view’s bounds (the real clip area); fall back
    /// to host bounds. Never use contentView.bounds (magnified document space).
    var canvasSize: CGSize {
        if let scroll = findScrollView(pdfView) {
            // Frame size is in window points and does not grow with magnification.
            var s = scroll.bounds.size
            // If a scroller is currently shown, the content band is slightly smaller.
            // Using the full bounds makes Fit Page ~scroller-thickness too small.
            if scroll.hasVerticalScroller, scroll.scrollerStyle == .legacy {
                s.width -= scroll.verticalScroller?.frame.width ?? 0
            }
            if scroll.hasHorizontalScroller, scroll.scrollerStyle == .legacy {
                s.height -= scroll.horizontalScroller?.frame.height ?? 0
            }
            if s.width >= 40, s.height >= 40 { return s }
        }
        let b = bounds.size
        if b.width >= 40, b.height >= 40 { return b }
        return pdfView.bounds.size
    }

    private func findScrollView(_ root: NSView) -> NSScrollView? {
        if let s = root as? NSScrollView { return s }
        for sub in root.subviews {
            if let f = findScrollView(sub) { return f }
        }
        return nil
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width >= 40, size.height >= 40 else { return }
        let changed = abs(size.width - lastBounds.width) > 0.5
            || abs(size.height - lastBounds.height) > 0.5
        if changed {
            lastBounds = size
            onLayoutZoom?()
        }
    }
}

// MARK: - Main canvas

struct PDFCanvasView: NSViewRepresentable {
    @ObservedObject var session: SharedPDFDocumentSession
    @Binding var page: Int
    @Binding var zoomPreset: PDFZoomPreset
    var navigationEpoch: Int
    var searchBridge: PDFSearchBridge?
    var onPageChange: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFCanvasHostView {
        let host = PDFCanvasHostView()
        let c = context.coordinator
        c.host = host
        c.observe(host.pdfView)
        searchBridge?.pdfView = host.pdfView

        host.pdfView.onJumpToPage = { [weak c] page in
            c?.jumpToPageFromKeyboard(page)
        }

        host.onLayoutZoom = { [weak c] in
            c?.applyZoom(reason: "layout")
        }

        c.attach(session: session)
        return host
    }

    func updateNSView(_ host: PDFCanvasHostView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.host = host
        searchBridge?.pdfView = host.pdfView

        if c.loadedURL != session.url {
            c.attach(session: session)
            return
        }

        let epochChanged = c.lastEpoch != navigationEpoch
        let pageChanged = c.lastPage != page
        let zoomChanged = c.lastZoom != zoomPreset

        if epochChanged {
            c.applyForcedNavigation(to: page, reason: "epoch")
            return
        }

        if zoomChanged {
            c.lastZoom = zoomPreset
            c.applyZoom(reason: "zoom")
            c.goTo(page: page, force: true)
            c.lastPage = page
            return
        }

        if pageChanged {
            c.goTo(page: page, force: true)
            c.lastPage = page
            // Keep the new page horizontally centered in the (possibly wider) document strip.
            c.centerCurrentPageHorizontally()
        }
    }

    static func dismantleNSView(_ nsView: PDFCanvasHostView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFCanvasView
        weak var host: PDFCanvasHostView?
        var loadedURL: URL?
        var lastPage = -1
        var lastEpoch = -1
        var lastZoom: PDFZoomPreset?
        private var suppress = 0
        private var applyingZoom = false
        /// While set, ignore PDFKit page notifications that would clobber an explicit jump
        /// (document attach always reports page 1 first).
        private var pendingForcedPage: Int?

        init(_ parent: PDFCanvasView) { self.parent = parent }

        var pdfView: KeyboardPDFView? { host?.pdfView }

        func observe(_ pdf: PDFView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged),
                name: .PDFViewPageChanged,
                object: pdf
            )
        }

        func teardown() {
            parent.searchBridge?.pdfView = nil
            host?.onLayoutZoom = nil
            host?.pdfView.onJumpToPage = nil
            // Observer removal only in deinit (SwiftLint notification_center_detachment).
        }

        /// ←/→/Page Up/Down/Home/End from KeyboardPDFView — update binding + scroll.
        func jumpToPageFromKeyboard(_ page: Int) {
            guard let pdfView, let doc = pdfView.document, doc.pageCount > 0 else { return }
            let one = max(1, min(doc.pageCount, page))
            // Keyboard is outside the SwiftUI update pass; safe to write now.
            if parent.page != one {
                parent.page = one
            }
            goTo(page: one, force: true)
            lastPage = one
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        /// Attach the shared document (no second decode).
        func attach(session: SharedPDFDocumentSession) {
            guard let pdfView else { return }
            pdfView.autoScales = false
            let target = max(1, parent.page)
            pendingForcedPage = target
            // Assigning `document` always lands PDFKit on page 1 and fires
            // PDFViewPageChanged. Suppress that so we don't overwrite an explicit
            // page-chip / search target (first open from Reference was stuck on p.1).
            withSuppress {
                pdfView.document = session.document
            }
            loadedURL = session.url
            lastPage = -1
            lastZoom = nil
            // Sync epoch now so a same-turn updateNSView doesn't treat this as a
            // second navigation with a stale binding.
            lastEpoch = parent.navigationEpoch
            goTo(page: target, force: true)
            // After layout/zoom settle, re-assert the target (zoom can nudge scroll).
            afterViewUpdate { [weak self] in
                guard let self else { return }
                let page = max(1, self.parent.page)
                self.pendingForcedPage = page
                self.goTo(page: page, force: true)
                self.applyZoom(reason: "open")
                self.goTo(page: page, force: true)
                self.lastZoom = self.parent.zoomPreset
                self.lastPage = page
                self.lastEpoch = self.parent.navigationEpoch
                // Clear after a second turn so late page-1 notifications can't stick.
                afterViewUpdate { [weak self] in
                    guard let self else { return }
                    if self.pendingForcedPage == page {
                        self.pendingForcedPage = nil
                    }
                }
            }
        }

        private func withSuppress(_ body: () -> Void) {
            suppress += 1
            body()
            afterViewUpdate { [weak self] in
                self?.suppress = max(0, (self?.suppress ?? 1) - 1)
            }
        }

        @objc private func pageChanged() {
            guard suppress == 0,
                  let pdfView,
                  let doc = pdfView.document,
                  let cur = pdfView.currentPage
            else { return }
            let one = doc.index(for: cur) + 1
            // Explicit chip/search jump in flight: re-assert target, never write p.1 back.
            if let pending = pendingForcedPage {
                if one == pending {
                    lastPage = one
                    pendingForcedPage = nil
                    updateScrollerForCurrentPage()
                    centerCurrentPageHorizontally()
                } else {
                    goTo(page: pending, force: true)
                }
                return
            }
            lastPage = one
            updateScrollerForCurrentPage()
            centerCurrentPageHorizontally()
            guard parent.page != one else { return }
            let cb = parent.onPageChange
            afterViewUpdate { [weak self] in
                guard let self, self.suppress == 0, self.pendingForcedPage == nil else { return }
                if self.parent.page != one { self.parent.page = one }
                cb?(one)
            }
        }

        /// Page chip / search / epoch jump: hold the target until PDFKit settles.
        func applyForcedNavigation(to page: Int, reason: String) {
            let target = max(1, page)
            pendingForcedPage = target
            lastEpoch = parent.navigationEpoch
            goTo(page: target, force: true)
            applyZoom(reason: reason)
            goTo(page: target, force: true)
            lastZoom = parent.zoomPreset
            lastPage = target
            afterViewUpdate { [weak self] in
                guard let self else { return }
                self.goTo(page: max(1, self.parent.page), force: true)
                if self.pendingForcedPage == target {
                    self.pendingForcedPage = nil
                }
            }
        }

        func goTo(page: Int, force: Bool) {
            guard let pdfView, let doc = pdfView.document, doc.pageCount > 0 else { return }
            let idx = max(0, min(doc.pageCount - 1, page - 1))
            if !force, lastPage == idx + 1 { return }
            guard let pdfPage = doc.page(at: idx) else { return }
            withSuppress {
                pdfView.go(to: pdfPage)
                lastPage = idx + 1
            }
            updateScrollerForCurrentPage()
            centerCurrentPageHorizontally()
        }

        /// Letter vs landscape pages: only the current page decides H-scroller.
        private func updateScrollerForCurrentPage() {
            guard let host, let pdfView, let page = pdfView.currentPage else { return }
            let pageSz = pageSizePoints(page)
            let canvas = host.canvasSize
            let scale = pdfView.scaleFactor
            configureHorizontalScroller(
                needsHorizontal: pageSz.width * scale > canvas.width + 1
            )
        }

        private func pageSizePoints(_ page: PDFPage) -> CGSize {
            let media = page.bounds(for: .mediaBox)
            var mediaWidth = abs(media.width)
            var mediaHeight = abs(media.height)
            let rot = ((page.rotation % 360) + 360) % 360
            if rot == 90 || rot == 270 {
                swap(&mediaWidth, &mediaHeight)
            }
            return CGSize(width: mediaWidth, height: mediaHeight)
        }

        func applyZoom(reason: String) {
            guard !applyingZoom else { return }
            guard let host, let pdfView else { return }

            // CRITICAL: window-point canvas only — never contentView.bounds
            // (those inflate/shrink with magnification).
            var canvas = host.canvasSize
            guard canvas.width >= 40, canvas.height >= 40 else { return }
            guard let page = pdfView.currentPage ?? pdfView.document?.page(at: 0) else { return }

            let pageSz = pageSizePoints(page)
            guard pageSz.width > 1, pageSz.height > 1 else { return }

            // Fit modes: hide H-scroller first when the page will fit, so the
            // canvas height isn't reduced by a scroller gutter we don't need.
            if parent.zoomPreset == .fitPage || parent.zoomPreset == .fitWidth {
                let trial = PDFZoomPreset.scale(
                    preset: parent.zoomPreset, canvas: canvas, pageSize: pageSz
                )
                configureHorizontalScroller(
                    needsHorizontal: pageSz.width * trial > canvas.width + 1
                )
                // Re-measure after scroller visibility may have changed.
                canvas = host.canvasSize
            }

            var scale = PDFZoomPreset.scale(
                preset: parent.zoomPreset,
                canvas: canvas,
                pageSize: pageSz
            )

            applyingZoom = true
            defer { applyingZoom = false }

            pdfView.autoScales = false
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            pdfView.displayBox = .mediaBox

            // Set scaleFactor only. PDFKit mirrors this into scroll magnification —
            // never force magnification back to 1.0 (that resets scale to 1).
            if abs(pdfView.scaleFactor - scale) > 0.001 {
                pdfView.scaleFactor = scale
            }

            // Fit Page/Width: correct for PDFView drawing insets so the page
            // fills the *padded* target, not the raw canvas edge.
            if parent.zoomPreset == .fitPage || parent.zoomPreset == .fitWidth {
                scale = correctedFitScale(
                    pdfView: pdfView, page: page, canvas: canvas, baseScale: scale
                )
            }

            configureHorizontalScroller(
                needsHorizontal: pageSz.width * scale > canvas.width + 1
            )
            centerCurrentPageHorizontally()

            let preset = parent.zoomPreset
            let target = scale
            DispatchQueue.main.async { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                guard self.parent.zoomPreset == preset else { return }
                self.applyingZoom = true
                pdfView.autoScales = false
                if abs(pdfView.scaleFactor - target) > 0.001 {
                    pdfView.scaleFactor = target
                }
                // Second-pass correction after layout settles.
                if preset == .fitPage || preset == .fitWidth,
                   let page = pdfView.currentPage {
                    let canvas2 = self.host?.canvasSize ?? canvas
                    _ = self.correctedFitScale(
                        pdfView: pdfView, page: page, canvas: canvas2, baseScale: target
                    )
                    let pageSz2 = self.pageSizePoints(page)
                    self.configureHorizontalScroller(
                        needsHorizontal: pageSz2.width * pdfView.scaleFactor > canvas2.width + 1
                    )
                }
                self.centerCurrentPageHorizontally()
                self.applyingZoom = false
            }

            #if DEBUG
            print(String(
                format: "[PDFZoom] %@ preset=%@ canvas=%.0f×%.0f page=%.0f×%.0f scale=%.4f sf=%.4f",
                reason,
                parent.zoomPreset.rawValue,
                canvas.width,
                canvas.height,
                pageSz.width,
                pageSz.height,
                scale,
                pdfView.scaleFactor
            ))
            #endif
        }

        /// Measure the rendered page rect and nudge scale so Fit Page/Width
        /// fill the padded target (PDFKit often leaves a few points of inset).
        @discardableResult
        private func correctedFitScale(
            pdfView: PDFView,
            page: PDFPage,
            canvas: CGSize,
            baseScale: CGFloat
        ) -> CGFloat {
            let box = page.bounds(for: pdfView.displayBox)
            let rendered = pdfView.convert(box, from: page)
            guard rendered.width > 1, rendered.height > 1 else {
                return baseScale
            }

            let target = PDFZoomPreset.fitTargetSize(canvas: canvas, preset: parent.zoomPreset)
            let fillW = target.width / rendered.width
            let fillH = target.height / rendered.height
            // Fit Width only cares about width; Fit Page uses both.
            let boost: CGFloat
            if parent.zoomPreset == .fitWidth {
                boost = fillW
            } else {
                boost = min(fillW, fillH)
            }

            // Only enlarge when clearly short (avoid fighting float noise / overshoot).
            // Do not enlarge past the padded target (boost < 1 is fine — leave scale).
            guard boost > 1.002 else { return pdfView.scaleFactor }

            // Cap boost so a bad measurement can't explode scale (e.g. off-screen page).
            let capped = min(boost, 1.08)
            let newScale = max(0.05, min(pdfView.scaleFactor * capped, 20))
            if abs(newScale - pdfView.scaleFactor) > 0.001 {
                pdfView.scaleFactor = newScale
            }
            return newScale
        }

        /// Show H-scroller only when the *current* page is wider than the canvas.
        /// The continuous document is always as wide as the widest page in the
        /// file, but letter pages don't need an H-scroller once centered.
        private func configureHorizontalScroller(needsHorizontal: Bool) {
            guard let pdfView, let scroll = findScrollView(pdfView) else { return }
            scroll.hasHorizontalScroller = needsHorizontal
            scroll.horizontalScrollElasticity = needsHorizontal ? .automatic : .none
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
        }

        /// Continuous docs are as wide as the widest page (SR5 has ~2286 pt spreads).
        /// Center the current page so letter pages aren't stuck in a sea of side gutter.
        func centerCurrentPageHorizontally() {
            guard let pdfView,
                  let page = pdfView.currentPage,
                  let scroll = findScrollView(pdfView),
                  let docView = scroll.documentView
            else { return }

            let box = page.bounds(for: pdfView.displayBox)
            let pageInView = pdfView.convert(box, from: page)
            let pageInDocView = docView.convert(pageInView, from: pdfView)

            let clip = scroll.contentView.bounds
            var origin = clip.origin
            origin.x = pageInDocView.midX - clip.width / 2

            let maxX = max(0, docView.bounds.width - clip.width)
            origin.x = min(max(0, origin.x), maxX)

            if abs(origin.x - clip.origin.x) > 0.5 {
                scroll.contentView.setBoundsOrigin(origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        private func findScrollView(_ root: NSView) -> NSScrollView? {
            if let s = root as? NSScrollView { return s }
            for sub in root.subviews {
                if let f = findScrollView(sub) { return f }
            }
            return nil
        }
    }
}

