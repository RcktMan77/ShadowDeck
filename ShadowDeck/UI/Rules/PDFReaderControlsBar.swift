import AppKit
import PDFKit
import SwiftUI

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
