import AppKit
import PDFKit
import SwiftUI

// MARK: - Thumbnails (hidden driver PDFView; shared document)

struct PDFThumbnailPane: NSViewRepresentable {
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
            // Suppress: assigning document always jumps to PDF page 1 and would
            // publish back through the shared page binding.
            suppress += 1
            driver?.document = session.document
            attachedURL = session.url
            syncFromBinding()
            afterViewUpdate { [weak self] in
                self?.suppress = max(0, (self?.suppress ?? 1) - 1)
            }
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
            // Thumbnail strip is secondary: never push page 1 (document-load default)
            // over an explicit chip/search jump still in the binding.
            // Only propagate when the user actually picks a different thumb.
            afterViewUpdate { [weak self] in
                guard let self, self.suppress == 0 else { return }
                if self.page.wrappedValue != one {
                    self.page.wrappedValue = one
                }
            }
        }
    }
}

