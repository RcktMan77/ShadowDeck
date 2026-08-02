//
//  CharacterLibraryBrowserView.swift
//  ShadowDeck
//
//  Character library list/gallery pane (extracted from ContentView).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Browse / filter / open characters in the app library.
struct CharacterLibraryBrowserView: View {
    let summaries: [CharacterSummary]
    @Binding var libraryQuery: String
    @Binding var libraryLayout: CharacterLibraryLayout
    @Binding var isDropTargeted: Bool
    var statusMessage: String?
    var libraryError: String?
    var onRefresh: () -> Void
    var onLoadSamples: () -> Void
    var onNewCharacter: () -> Void
    var onImport: () -> Void
    var onOpen: (UUID) -> Void
    var onExportPackage: (CharacterSummary) -> Void
    var onExportPDF: (CharacterSummary) -> Void
    var onExportChummer: (CharacterSummary) -> Void
    var onDelete: (CharacterSummary) -> Void
    var onDropProviders: ([NSItemProvider]) -> Bool

    private var filteredSummaries: [CharacterSummary] {
        let q = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return summaries }
        return summaries.filter {
            $0.displayTitle.lowercased().contains(q)
                || $0.concept.lowercased().contains(q)
                || $0.editionRaw.lowercased().contains(q)
                || $0.metatypeRaw.lowercased().contains(q)
                || $0.name.lowercased().contains(q)
                || $0.streetName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isDropTargeted {
                Text("Drop to import (.json / .chum5 / .shadowdeck)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            }
            if !summaries.isEmpty {
                filterField
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let libraryError {
                Text(libraryError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            libraryBody
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            onDropProviders(providers)
        }
    }

    private var header: some View {
        HStack {
            Text("Character Library")
                .font(.title2.weight(.semibold))
            Spacer()
            Picker("Layout", selection: $libraryLayout) {
                ForEach(CharacterLibraryLayout.allCases) { layout in
                    Image(systemName: layout.systemImage)
                        .tag(layout)
                        .help(layout.title)
                        .accessibilityLabel(layout.title)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 88)
            .labelsHidden()
            .help("List or Gallery view")
            .accessibilityLabel("Library layout")

            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .help("Reload the library list from disk (useful after external changes).")
            Button("Load Samples", systemImage: "tray.and.arrow.down", action: onLoadSamples)
                .help("If the library is empty, add one sample runner for each edition (SR4 / SR5 / SR6). Does nothing when characters already exist.")
        }
    }

    private var filterField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Filter by name, street name, concept, edition…", text: $libraryQuery)
                .textFieldStyle(.plain)
            if !libraryQuery.isEmpty {
                Button {
                    libraryQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 480)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter characters")
    }

    @ViewBuilder
    private var libraryBody: some View {
        if summaries.isEmpty {
            // Create/import via Create sidebar or Load Samples in the header (no duplicate empty-state CTAs).
            ContentUnavailableView {
                Label("No Characters Yet", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text("Use Create → New Character or Import Character…, or Load Samples above, to add runners.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredSummaries.isEmpty {
            ContentUnavailableView {
                Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No characters match “\(libraryQuery)”.")
            } actions: {
                Button("Clear Filter") { libraryQuery = "" }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(
                libraryLayout == .gallery
                    ? "Click a portrait to open the sheet. Use ⓘ to flip a card for a quick summary."
                    : "Select a runner for the at-a-glance summary."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            switch libraryLayout {
            case .gallery:
                CharacterLibraryGalleryView(
                    summaries: filteredSummaries,
                    onOpen: { onOpen($0.id) },
                    onExportPackage: onExportPackage,
                    onExportPDF: onExportPDF,
                    onExportChummer: onExportChummer,
                    onDelete: onDelete
                )
            case .list:
                listBody
            }
        }
    }

    private var listBody: some View {
        List {
            ForEach(filteredSummaries) { summary in
                HStack(spacing: 10) {
                    HStack(spacing: 12) {
                        libraryPortrait(summary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.displayTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Text(librarySubtitle(for: summary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(summary.id) }
                    .layoutPriority(1)

                    HStack(spacing: 4) {
                        Button {
                            onOpen(summary.id)
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.body)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Open \(summary.displayTitle)")
                        .accessibilityLabel("Open \(summary.displayTitle)")

                        Menu {
                            Button("ShadowDeck Package…") { onExportPackage(summary) }
                            Button("PDF Character Sheet…") { onExportPDF(summary) }
                            Button("Chummer .chum5…") { onExportChummer(summary) }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Export \(summary.displayTitle)")
                        .accessibilityLabel("Export \(summary.displayTitle)")

                        Button {
                            onDelete(summary)
                        } label: {
                            Image(systemName: "trash")
                                .font(.body)
                                .foregroundStyle(.red)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Delete \(summary.displayTitle)")
                        .accessibilityLabel("Delete \(summary.displayTitle)")
                    }
                    .fixedSize()
                }
                .contextMenu {
                    Button("Open Character Sheet") { onOpen(summary.id) }
                    Button("Export ShadowDeck Package…") { onExportPackage(summary) }
                    Button("Export PDF Character Sheet…") { onExportPDF(summary) }
                    Button("Export Chummer .chum5…") { onExportChummer(summary) }
                    Button("Delete…", role: .destructive) { onDelete(summary) }
                }
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: 720)
    }

    @ViewBuilder
    private func libraryPortrait(_ summary: CharacterSummary) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let data = summary.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let metatype = summary.metatype,
                      let image = ChargenArtLoader.metatypeNSImage(for: metatype) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "person.crop.rectangle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func librarySubtitle(for summary: CharacterSummary) -> String {
        let tag = summary.concept.trimmingCharacters(in: .whitespacesAndNewlines)
        let conceptPart = tag.isEmpty ? "—" : tag
        return "\(summary.editionRaw) · \(summary.metatypeRaw.capitalized) · \(conceptPart)"
    }
}
