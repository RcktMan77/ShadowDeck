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
    var allowCustom: Bool = true
    var onPick: (CatalogEntry) -> Void
    var onCustom: (() -> Void)?
    var onCancel: () -> Void

    @ObservedObject private var catalog = CatalogStore.shared
    @State private var query = ""

    private var rows: [CatalogEntry] {
        catalog.entries(kinds: kinds, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2.weight(.semibold))
                Spacer()
                AppChromeButton.title("Cancel", help: "Close catalog browser") {
                    onCancel()
                }
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
