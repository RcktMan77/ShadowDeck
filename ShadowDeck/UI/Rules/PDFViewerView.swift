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
        Group {
            if session.isLoading {
                ProgressView("Opening PDF…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError = session.loadError {
                ContentUnavailableView(
                    "Couldn’t open PDF",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.document != nil {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .id(url) // remount session when the open book changes
    }
}

