//
//  PDFLibraryShelfViews.swift
//  ShadowDeck
//
//  List + gallery presentations for the PDF Library shelf.
//

import AppKit
import SwiftUI

// MARK: - Cover image

struct PDFCoverImage: View {
    let coverURL: URL?
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let coverURL, let image = NSImage(contentsOf: coverURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Mission draft-run control

/// Cover control for Missions & Adventures — draft a run from the PDF.
/// Sparkles = familiar AI affordance; neutral material so it doesn’t clash with chrome.
struct MissionDraftRunBadge: View {
    var compact: Bool = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: compact ? 9 : 12, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: compact ? 1 : 2, y: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Gallery

struct PDFLibraryGalleryView: View {
    let groups: [LibraryShelfSectionGroup]
    var coverURL: (PDFLibraryItem) -> URL?
    var onOpen: (PDFLibraryItem) -> Void
    var onBookSettings: (PDFLibraryItem) -> Void
    var onRename: (PDFLibraryItem) -> Void
    var onReveal: (PDFLibraryItem) -> Void
    var onRemove: (PDFLibraryItem) -> Void
    var onDraftRun: (PDFLibraryItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(group.items) { item in
                                PDFLibraryGalleryCard(
                                    item: item,
                                    coverURL: coverURL(item),
                                    onOpen: { onOpen(item) },
                                    onBookSettings: { onBookSettings(item) },
                                    onRename: { onRename(item) },
                                    onReveal: { onReveal(item) },
                                    onRemove: { onRemove(item) },
                                    onDraftRun: item.shelfSection == .mission
                                        ? { onDraftRun(item) }
                                        : nil
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    } header: {
                        sectionHeader(group)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sectionHeader(_ group: LibraryShelfSectionGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.section.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(group.section.displayName)
                .font(.subheadline.weight(.semibold))
            Text("\(group.items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct PDFLibraryGalleryCard: View {
    let item: PDFLibraryItem
    let coverURL: URL?
    var onOpen: () -> Void
    var onBookSettings: () -> Void
    var onRename: () -> Void
    var onReveal: () -> Void
    var onRemove: () -> Void
    var onDraftRun: (() -> Void)?

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PDFCoverImage(coverURL: coverURL, cornerRadius: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)

                if let onDraftRun {
                    Button(action: onDraftRun) {
                        MissionDraftRunBadge()
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Draft a planning run from this mission PDF")
                    .accessibilityLabel("Draft run from PDF")
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)

                HStack(spacing: 6) {
                    if let key = item.bookKey, !key.isEmpty {
                        Text(key)
                            .font(.caption2.weight(.semibold).monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(.tint)
                    } else {
                        Text("No key")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let pages = item.pageCount {
                        Text("\(pages) pp")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(cardShape)
        .overlay { cardShape.strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1) }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .contextMenu {
            Button("Open", action: onOpen)
            if let onDraftRun {
                Button("Draft run from PDF…", action: onDraftRun)
            }
            Button("Book settings…", action: onBookSettings)
            Button("Rename…", action: onRename)
            Button("Reveal in Finder", action: onReveal)
            Divider()
            Button("Remove from library", role: .destructive, action: onRemove)
        }
    }
}

// MARK: - List (sectioned)

struct PDFLibraryListView: View {
    let groups: [LibraryShelfSectionGroup]
    var coverURL: (PDFLibraryItem) -> URL?
    var onOpen: (PDFLibraryItem) -> Void
    var onBookSettings: (PDFLibraryItem) -> Void
    var onRename: (PDFLibraryItem) -> Void
    var onReveal: (PDFLibraryItem) -> Void
    var onRemove: (PDFLibraryItem) -> Void
    var onDraftRun: (PDFLibraryItem) -> Void

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(item) }
                            .contextMenu {
                                Button("Open") { onOpen(item) }
                                if item.shelfSection == .mission {
                                    Button("Draft run from PDF…") { onDraftRun(item) }
                                }
                                Button("Book settings…") { onBookSettings(item) }
                                Button("Rename…") { onRename(item) }
                                Button("Reveal in Finder") { onReveal(item) }
                                Divider()
                                Button("Remove from library", role: .destructive) {
                                    onRemove(item)
                                }
                            }
                    }
                } header: {
                    Label(group.section.displayName, systemImage: group.section.systemImage)
                }
            }
        }
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, 56)
    }

    private func row(_ item: PDFLibraryItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                PDFCoverImage(coverURL: coverURL(item), cornerRadius: 4)
                    .frame(width: 40, height: 54)
                    .clipped()

                if item.shelfSection == .mission {
                    Button {
                        onDraftRun(item)
                    } label: {
                        MissionDraftRunBadge(compact: true)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .help("Draft a planning run from this mission PDF")
                    .accessibilityLabel("Draft run from PDF")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let key = item.bookKey, !key.isEmpty {
                        Text(key)
                            .font(.caption2.weight(.semibold).monospaced())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(.tint)
                    } else {
                        Text("No book key")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let pages = item.pageCount {
                        Text("\(pages) pp")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !item.editionTags.isEmpty {
                        Text(item.editionTags.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(item.addedAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
