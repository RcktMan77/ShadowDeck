//
//  PDFViewerView.swift
//  ShadowDeck
//
//  Continuous PDF reader with explicit zoom math.
//
//  Canvas  = host view size in window points (NOT the magnified clip bounds).
//  Page    = media box in PDF points (letter ≈ 612×765). Rotation applied.
//
//  Scale (aspect preserved; set via PDFView.scaleFactor only — do NOT touch
//  NSScrollView.magnification; PDFKit couples the two):
//    Fit Page    = min(innerW / pageW, innerH / pageH)  // inner = canvas − padding
//    Fit Width   = innerW / pageW
//    Actual Size = 1.0   (== 100%)
//    N%          = N/100
//
//  Continuous-mode document width = widest page in the file (SR5 has landscape
//  spreads ≈ 2286 pt). That is why PDFKit wants an H-scroller even on letter
//  pages — we hide it whenever the *current* page fits the canvas width, and
//  H-center so letter pages sit correctly in the wider strip.
//
//  Keyboard (when the PDF view is focused):
//    ↑/↓           line scroll
//    Page Up/Down  previous / next page
//    ←/→           previous / next page
//    Home/End      first / last page
//

import AppKit
import PDFKit
import SwiftUI

// MARK: - Zoom

enum PDFZoomPreset: String, CaseIterable, Identifiable, Sendable {
    case fitPage
    case fitWidth
    case actualSize
    case percent75
    case percent100
    case percent125
    case percent150
    case percent200

    var id: String { rawValue }

    /// Side/edge inset for Fit Page / Fit Width (points).
    /// Continuous mode top-aligns pages, so dual vertical insets only open a
    /// band at the *bottom* that peeks the next page — Fit Page uses one edge
    /// of vertical pad; Fit Width only insets width.
    static let fitPadding: CGFloat = 8

    var menuLabel: String {
        switch self {
        case .fitPage: "Fit Page"
        case .fitWidth: "Fit Width"
        case .actualSize: "Actual Size"
        case .percent75: "75%"
        case .percent100: "100%"
        case .percent125: "125%"
        case .percent150: "150%"
        case .percent200: "200%"
        }
    }

    /// Fixed scale in view-points per PDF-point, or nil when derived from the canvas.
    var fixedScale: CGFloat? {
        switch self {
        case .fitPage, .fitWidth: nil
        case .actualSize, .percent100: 1.0
        case .percent75: 0.75
        case .percent125: 1.25
        case .percent150: 1.5
        case .percent200: 2.0
        }
    }

    /// Pure scale math. No PDFView side effects.
    static func scale(
        preset: Self,
        canvas: CGSize,
        pageSize: CGSize
    ) -> CGFloat {
        let pageW = max(pageSize.width, 1)
        let pageH = max(pageSize.height, 1)
        let target = fitTargetSize(canvas: canvas, preset: preset)

        let raw: CGFloat
        switch preset {
        case .fitPage:
            raw = min(target.width / pageW, target.height / pageH)
        case .fitWidth:
            raw = target.width / pageW
        case .actualSize, .percent75, .percent100, .percent125, .percent150, .percent200:
            raw = preset.fixedScale ?? 1.0
        }
        return max(0.05, min(raw, 20))
    }

    /// Drawable target for Fit Page / Fit Width after padding.
    static func fitTargetSize(canvas: CGSize, preset: Self = .fitPage) -> CGSize {
        let pad = fitPadding
        let w = max(canvas.width - 2 * pad, 1)
        switch preset {
        case .fitPage:
            // One vertical pad only — continuous layout top-aligns, so 2× pad
            // becomes a next-page strip along the bottom.
            return CGSize(width: w, height: max(canvas.height - pad, 1))
        case .fitWidth:
            return CGSize(width: w, height: max(canvas.height, 1))
        default:
            return CGSize(width: max(canvas.width, 1), height: max(canvas.height, 1))
        }
    }
}

// MARK: - Search

@MainActor
final class PDFSearchBridge: ObservableObject {
    weak var pdfView: PDFView?

    @Published var query: String = ""
    @Published private(set) var matchCount: Int = 0
    @Published private(set) var activeIndex: Int = 0

    private var matches: [PDFSelection] = []

    /// Clear find UI. Skips @Published writes when already idle (avoids
    /// “Publishing changes from within view updates” storms on book open).
    func clear() {
        let needsPublish = !query.isEmpty || matchCount != 0 || activeIndex != 0 || !matches.isEmpty
        matches = []
        if !query.isEmpty { query = "" }
        if matchCount != 0 { matchCount = 0 }
        if activeIndex != 0 { activeIndex = 0 }
        pdfView?.highlightedSelections = nil
        pdfView?.currentSelection = nil
        _ = needsPublish
    }

    func find(query newQuery: String? = nil) {
        if let newQuery, newQuery != query { query = newQuery }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pdfView, let document = pdfView.document, !q.isEmpty else {
            matches = []
            if matchCount != 0 { matchCount = 0 }
            if activeIndex != 0 { activeIndex = 0 }
            pdfView?.highlightedSelections = nil
            return
        }
        matches = document.findString(q, withOptions: [.caseInsensitive])
        let count = matches.count
        if matchCount != count { matchCount = count }
        if let first = matches.first {
            if activeIndex != 1 { activeIndex = 1 }
            reveal(first, in: pdfView)
        } else {
            if activeIndex != 0 { activeIndex = 0 }
            pdfView.highlightedSelections = []
            pdfView.currentSelection = nil
        }
    }

    func findNext() {
        guard !matches.isEmpty, let pdfView else { return }
        activeIndex = activeIndex >= matches.count ? 1 : activeIndex + 1
        reveal(matches[activeIndex - 1], in: pdfView)
    }

    func findPrevious() {
        guard !matches.isEmpty, let pdfView else { return }
        activeIndex = activeIndex <= 1 ? matches.count : activeIndex - 1
        reveal(matches[activeIndex - 1], in: pdfView)
    }

    private func reveal(_ selection: PDFSelection, in pdfView: PDFView) {
        pdfView.highlightedSelections = matches
        pdfView.currentSelection = selection
        pdfView.go(to: selection)
        DispatchQueue.main.async {
            pdfView.scrollSelectionToVisible(nil)
        }
    }
}

// MARK: - Shared document (one PDFDocument for reader + thumbnails)

/// Loads a book once and shares the same `PDFDocument` instance with the continuous
/// reader and the thumbnail strip (avoids 2× decode / peak memory on large CRBs).
@MainActor
final class SharedPDFDocumentSession: ObservableObject {
    let url: URL
    let document: PDFDocument?

    init(url: URL) {
        self.url = url
        self.document = PDFDocument(url: url)
    }
}

// MARK: - Workspace

struct PDFReaderWorkspace: View {
    let url: URL
    @Binding var page: Int
    @Binding var zoomPreset: PDFZoomPreset
    var navigationEpoch: Int = 0
    var thumbnailWidth: CGFloat = 128
    var searchBridge: PDFSearchBridge?
    var onPageChange: ((Int) -> Void)?

    @StateObject private var session: SharedPDFDocumentSession

    init(
        url: URL,
        page: Binding<Int>,
        zoomPreset: Binding<PDFZoomPreset>,
        navigationEpoch: Int = 0,
        thumbnailWidth: CGFloat = 128,
        searchBridge: PDFSearchBridge? = nil,
        onPageChange: ((Int) -> Void)? = nil
    ) {
        self.url = url
        self._page = page
        self._zoomPreset = zoomPreset
        self.navigationEpoch = navigationEpoch
        self.thumbnailWidth = thumbnailWidth
        self.searchBridge = searchBridge
        self.onPageChange = onPageChange
        _session = StateObject(wrappedValue: SharedPDFDocumentSession(url: url))
    }

    var body: some View {
        GeometryReader { geo in
            let thumbW = min(thumbnailWidth, max(100, geo.size.width * 0.18))

            HStack(spacing: 0) {
                PDFThumbnailPane(session: session, page: $page)
                    .frame(width: thumbW)
                    .frame(maxHeight: .infinity)

                Divider()

                PDFCanvasView(
                    session: session,
                    page: $page,
                    zoomPreset: $zoomPreset,
                    navigationEpoch: navigationEpoch,
                    searchBridge: searchBridge,
                    onPageChange: onPageChange
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .id(url) // remount session when the open book changes
    }
}

// MARK: - Thumbnails (hidden driver PDFView; shared document)

private struct PDFThumbnailPane: NSViewRepresentable {
    @ObservedObject var session: SharedPDFDocumentSession
    @Binding var page: Int

    func makeCoordinator() -> Coord { Coord(page: $page) }

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        let driver = PDFView()
        driver.isHidden = true
        driver.displayMode = .singlePage
        driver.autoScales = true

        let thumbs = PDFThumbnailView()
        thumbs.thumbnailSize = NSSize(width: 88, height: 114)
        thumbs.backgroundColor = NSColor.controlBackgroundColor
        thumbs.pdfView = driver
        thumbs.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(driver)
        box.addSubview(thumbs)
        NSLayoutConstraint.activate([
            thumbs.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            thumbs.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            thumbs.topAnchor.constraint(equalTo: box.topAnchor),
            thumbs.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])

        context.coordinator.driver = driver
        context.coordinator.observe(driver)
        context.coordinator.attach(session: session)
        context.coordinator.syncFromBinding()
        return box
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.page = $page
        context.coordinator.attach(session: session)
        context.coordinator.syncFromBinding()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coord) {
        coordinator.teardown()
    }

    @MainActor
    final class Coord: NSObject {
        var page: Binding<Int>
        weak var driver: PDFView?
        private var attachedURL: URL?
        private var suppress = 0

        init(page: Binding<Int>) { self.page = page }

        func observe(_ driver: PDFView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(changed),
                name: .PDFViewPageChanged,
                object: driver
            )
        }

        func teardown() {
            // Observer removal only in deinit (SwiftLint notification_center_detachment).
        }
        deinit { NotificationCenter.default.removeObserver(self) }

        func attach(session: SharedPDFDocumentSession) {
            guard attachedURL != session.url else { return }
            driver?.document = session.document
            attachedURL = session.url
        }

        func syncFromBinding() {
            guard let driver, let doc = driver.document, doc.pageCount > 0 else { return }
            let idx = max(0, min(doc.pageCount - 1, page.wrappedValue - 1))
            guard let p = doc.page(at: idx) else { return }
            let cur = driver.currentPage.flatMap { doc.index(for: $0) } ?? -1
            guard cur != idx else { return }
            suppress += 1
            driver.go(to: p)
            afterViewUpdate { [weak self] in
                self?.suppress = max(0, (self?.suppress ?? 1) - 1)
            }
        }

        @objc private func changed() {
            guard suppress == 0,
                  let driver, let doc = driver.document, let cur = driver.currentPage
            else { return }
            let one = doc.index(for: cur) + 1
            guard page.wrappedValue != one else { return }
            // Never write the SwiftUI binding from inside a PDFKit notification
            // that may still be nested under updateNSView.
            afterViewUpdate { [weak self] in
                guard let self, self.suppress == 0 else { return }
                if self.page.wrappedValue != one {
                    self.page.wrappedValue = one
                }
            }
        }
    }
}

// MARK: - Keyboard-aware PDFView

/// PDFView that accepts key focus and handles page / scroll keys.
private final class KeyboardPDFView: PDFView {
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

// MARK: - Safe publish helper

/// Run work after the current SwiftUI update/layout pass finishes.
@MainActor
private func afterViewUpdate(_ work: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        await Task.yield()
        work()
    }
}

// MARK: - Host view

/// Owns the PDFView. Canvas for zoom = `bounds` (window points), never the
/// magnified NSScrollView contentView bounds (those grow/shrink with scale).
private final class PDFCanvasHostView: NSView {
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

private struct PDFCanvasView: NSViewRepresentable {
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
            c.lastEpoch = navigationEpoch
            c.goTo(page: page, force: true)
            c.applyZoom(reason: "epoch")
            c.lastZoom = zoomPreset
            c.lastPage = page
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
            pdfView.document = session.document
            loadedURL = session.url
            lastPage = -1
            lastZoom = nil
            // Do not clear search here — open runs under makeNSView/updateNSView.
            // Reader onAppear clears find results after the view update settles.
            afterViewUpdate { [weak self] in
                guard let self else { return }
                self.goTo(page: self.parent.page, force: true)
                self.applyZoom(reason: "open")
                self.lastZoom = self.parent.zoomPreset
                self.lastPage = self.parent.page
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
            lastPage = one
            updateScrollerForCurrentPage()
            centerCurrentPageHorizontally()
            guard parent.page != one else { return }
            let cb = parent.onPageChange
            afterViewUpdate { [weak self] in
                guard let self, self.suppress == 0 else { return }
                if self.parent.page != one { self.parent.page = one }
                cb?(one)
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

// MARK: - Controls

struct PDFReaderControlsBar: View {
    let pageCount: Int?
    @Binding var page: Int
    @Binding var zoomPreset: PDFZoomPreset
    @ObservedObject var search: PDFSearchBridge

    @State private var goToPageField: Int = 1

    var body: some View {
        HStack(spacing: 10) {
            pageControls
            Divider().frame(height: 18)
            zoomControls
            Divider().frame(height: 18)
            searchControls
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { goToPageField = page }
        .onChange(of: page) { _, n in if goToPageField != n { goToPageField = n } }
    }

    private var pageControls: some View {
        HStack(spacing: 4) {
            Button { page = max(1, page - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous page")
            .help("Previous page")

            HStack(spacing: 4) {
                TextField(
                    "",
                    value: Binding(
                        get: { goToPageField },
                        set: { goToPageField = max(1, $0) }
                    ),
                    format: .number
                )
                .frame(width: 56)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.center)
                .onSubmit { page = max(1, goToPageField) }
                .accessibilityLabel("Page number")

                Text("of \(pageCount.map(String.init) ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("of \(pageCount.map(String.init) ?? "unknown") pages")
            }

            Button { page = min(pageCount ?? 9999, page + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next page")
            .help("Next page")
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Zoom out")
            .help("Zoom out")

            Picker("Zoom", selection: $zoomPreset) {
                ForEach(PDFZoomPreset.allCases) { p in
                    Text(p.menuLabel).tag(p)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 120)
            .controlSize(.small)
            .accessibilityLabel("Zoom")
            .help("Zoom level")

            Button { zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Zoom in")
            .help("Zoom in")
        }
    }

    private var searchControls: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityHidden(true)
            TextField("Search", text: $search.query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 220)
                .onSubmit { search.find() }
                .accessibilityLabel("Find in document")

            if search.matchCount > 0 {
                Text("\(search.activeIndex) of \(search.matchCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Match \(search.activeIndex) of \(search.matchCount)")
            }

            Button { search.findPrevious() } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(search.matchCount == 0)
            .accessibilityLabel("Previous match")
            .help("Previous match")

            Button { search.findNext() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(search.matchCount == 0)
            .accessibilityLabel("Next match")
            .help("Next match")

            if !search.query.isEmpty {
                Button { search.clear() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
    }

    private func zoomIn() {
        let order: [PDFZoomPreset] = [.percent75, .percent100, .percent125, .percent150, .percent200]
        if let i = order.firstIndex(of: zoomPreset), i + 1 < order.count {
            zoomPreset = order[i + 1]
        } else if zoomPreset == .fitPage || zoomPreset == .fitWidth || zoomPreset == .actualSize {
            zoomPreset = .percent125
        }
    }

    private func zoomOut() {
        let order: [PDFZoomPreset] = [.percent75, .percent100, .percent125, .percent150, .percent200]
        if let i = order.firstIndex(of: zoomPreset), i > 0 {
            zoomPreset = order[i - 1]
        } else if zoomPreset == .fitPage || zoomPreset == .fitWidth {
            zoomPreset = .percent75
        }
    }
}
