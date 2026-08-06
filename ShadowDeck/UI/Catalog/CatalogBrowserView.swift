//
//  CatalogBrowserView.swift
//  ShadowDeck
//
//  Searchable picker over bundled catalog entries + custom entry.
//

import SwiftUI

struct CatalogBrowserView: View {
    let title: String
    let kinds: Set<CatalogKind>
    /// Which edition’s bundled catalog to load (`sr4_catalog` / `sr5_catalog` / `sr6_catalog`).
    var edition: Edition = .sr5
    var allowCustom: Bool = true
    /// Optional extra filter (e.g. spells stored as gear with category containing “Spell”).
    var matching: ((CatalogEntry) -> Bool)?
    var onPick: (CatalogEntry) -> Void
    var onCustom: (() -> Void)?
    var onCancel: () -> Void

    @ObservedObject private var catalog = CatalogStore.shared
    @State private var query = ""

    private var rows: [CatalogEntry] {
        catalog.entries(kinds: kinds, query: query, edition: edition, matching: matching)
    }

    private var editionBadge: String {
        switch edition {
        case .sr4: "SR4A catalog"
        case .sr5: "SR5 reference catalog"
        case .sr6: "SR6 catalog"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(editionBadge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
                    .help(
                        edition == .sr5
                            ? "Bundled SR5 catalog from Chummer GPL data — table reference for costs/names."
                            : "Edition-scoped bundled catalog (\(editionBadge))."
                    )
                Spacer()
                AppChromeButton.title("Cancel", help: "Close catalog browser") {
                    onCancel()
                }
            }
            .onAppear {
                catalog.ensureLoaded(for: edition)
            }

            if catalog.isLoaded && catalog.result.isEmpty {
                Text("Catalog not loaded. Check Settings → Catalog, or add a custom item.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by name…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            if rows.isEmpty {
                ContentUnavailableView {
                    Label(catalog.result.isEmpty ? "Catalog Empty" : "No Matches", systemImage: "tray")
                } description: {
                    Text(
                        catalog.result.isEmpty
                            ? "The built-in catalog failed to load."
                            : "Try another search, or add a custom entry."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows.prefix(500)) { entry in
                    Button {
                        onPick(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            HStack {
                if allowCustom, let onCustom {
                    AppChromeButton.title("Custom…", help: "Add a custom entry not in the catalog") {
                        onCustom()
                    }
                }
                Spacer()
                Text("\(min(rows.count, 500)) shown" + (rows.count > 500 ? " (refine search)" : ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            catalog.ensureLoaded()
        }
    }
}
