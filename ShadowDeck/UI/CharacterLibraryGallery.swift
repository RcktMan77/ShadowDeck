//
//  CharacterLibraryGallery.swift
//  ShadowDeck
//
//  Portrait-forward grid of character cards with flip-to-summary and row actions.
//

import AppKit
import SwiftUI

enum CharacterLibraryLayout: String, CaseIterable, Identifiable {
    case list
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .gallery: "Gallery"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .gallery: "square.grid.2x2"
        }
    }
}

/// Adaptive portrait card grid for the Character Library.
struct CharacterLibraryGalleryView: View {
    let summaries: [CharacterSummary]
    var onOpen: (CharacterSummary) -> Void
    var onExportPackage: (CharacterSummary) -> Void
    var onExportPDF: (CharacterSummary) -> Void
    var onExportChummer: (CharacterSummary) -> Void
    var onDelete: (CharacterSummary) -> Void

    @State private var flippedIDs: Set<UUID> = []

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16, alignment: .top),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(summaries) { summary in
                    CharacterLibraryCard(
                        summary: summary,
                        isFlipped: flippedIDs.contains(summary.id),
                        onToggleFlip: { toggleFlip(summary.id) },
                        onOpen: { onOpen(summary) },
                        onExportPackage: { onExportPackage(summary) },
                        onExportPDF: { onExportPDF(summary) },
                        onExportChummer: { onExportChummer(summary) },
                        onDelete: { onDelete(summary) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggleFlip(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.45)) {
            if flippedIDs.contains(id) {
                flippedIDs.remove(id)
            } else {
                flippedIDs.insert(id)
            }
        }
    }
}

// MARK: - Card

private struct CharacterLibraryCard: View {
    let summary: CharacterSummary
    let isFlipped: Bool
    var onToggleFlip: () -> Void
    var onOpen: () -> Void
    var onExportPackage: () -> Void
    var onExportPDF: () -> Void
    var onExportChummer: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ZStack {
            cardFront
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.55
                )
                .allowsHitTesting(!isFlipped)

            cardBack
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.55
                )
                .allowsHitTesting(isFlipped)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.72, contentMode: .fit)
        .contextMenu {
            Button("Open Character Sheet", action: onOpen)
            Button("Flip Card", action: onToggleFlip)
            Divider()
            Button("Export ShadowDeck Package…", action: onExportPackage)
            Button("Export PDF Character Sheet…", action: onExportPDF)
            Button("Export Chummer .chum5…", action: onExportChummer)
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        }
    }

    // MARK: Front

    private var cardFront: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                portrait
                    .frame(maxWidth: .infinity)
                    .frame(height: 168)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)

                flipButton
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)

                HStack(spacing: 6) {
                    Text(summary.editionRaw)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(.tint)
                    Text(summary.metatypeRaw.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(conceptLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 28, alignment: .top)

                HStack {
                    Spacer(minLength: 0)
                    actionCluster
                }
            }
            .padding(10)
        }
        .background(cardBackground)
        .clipShape(cardShape)
        .overlay { cardShape.strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1) }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    // MARK: Back

    private var cardBack: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Summary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                flipButton
            }
            .padding(10)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(summary.displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)

                labeledRow("Ruleset", summary.editionRaw)
                labeledRow("Metatype", summary.metatypeRaw.capitalized)
                labeledRow("Concept", conceptLine)

                if let edition = summary.edition {
                    labeledRow("Edition book", edition.coreBookLabel)
                }

                labeledRow(
                    "Modified",
                    summary.modifiedAt.formatted(date: .abbreviated, time: .shortened)
                )

                Spacer(minLength: 0)

                Button("Open Character Sheet", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                HStack {
                    Spacer(minLength: 0)
                    actionCluster
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(cardBackground)
        .clipShape(cardShape)
        .overlay { cardShape.strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1) }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    // MARK: Shared chrome

    private var flipButton: some View {
        Button(action: onToggleFlip) {
            Image(systemName: isFlipped ? "arrow.uturn.backward.circle.fill" : "info.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .black.opacity(0.45))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(isFlipped ? "Show portrait" : "Show summary")
    }

    private var actionCluster: some View {
        HStack(spacing: 2) {
            Button(action: onOpen) {
                Image(systemName: "square.and.pencil")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Open \(summary.displayTitle)")

            Menu {
                Button("ShadowDeck Package…", action: onExportPackage)
                Button("PDF Character Sheet…", action: onExportPDF)
                Button("Chummer .chum5…", action: onExportChummer)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Export \(summary.displayTitle)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Delete \(summary.displayTitle)")
        }
        .font(.body)
        .fixedSize()
    }

    private var portrait: some View {
        Group {
            if let data = summary.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.secondary.opacity(0.22),
                            Color.secondary.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var conceptLine: String {
        let tag = summary.concept.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? "—" : tag
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private func labeledRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
