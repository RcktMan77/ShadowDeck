//
//  SettingsView.swift
//  ShadowDeck
//
//  App preferences: catalog source, about.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var preferExternal = CatalogSettings.preferExternalCatalog
    @State private var externalPath: String = CatalogSettings.chummerDataPath ?? ""
    @State private var status: String = ""
    @ObservedObject private var catalog = CatalogStore.shared

    var body: some View {
        TabView {
            Form {
                Section("About") {
                    LabeledContent("Application", value: "ShadowDeck")
                    LabeledContent("Version", value: Bundle.main.shortVersionString)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                    Text("Native macOS character creation and campaign tracking for Shadowrun 4th, 5th, and 6th edition. Unofficial fan tool — not affiliated with Catalyst Game Labs.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Portable format") {
                    LabeledContent("Package extension", value: ".\(ShadowDeckFormat.fileExtension)")
                    LabeledContent("Type ID", value: ShadowDeckFormat.utTypeIdentifier)
                    Text("Double-click a .shadowdeck package in Finder, or use File → Open Package…, to import a runner into your library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Tips") {
                    Text("• Profile fields (contacts, attributes, gear) save automatically.\n• Rich-text Notes need Save Notes (or collapse a contact to commit its notes).\n• House Rules… on the Summary identity column applies table rules after chargen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section {
                    Text("ShadowDeck ships edition-scoped catalogs: SR4A and SR6 core packs extracted from the rulebooks for costs/names, plus a large SR5 reference catalog derived from Chummer5a’s open data. Management tabs load the catalog that matches the open character’s edition. No Chummer install is required.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let dir = catalog.result.sourceDirectory {
                        LabeledContent("Active source", value: dir.lastPathComponent)
                    }
                    LabeledContent("Entries loaded", value: "\(catalog.result.entries.count)")
                    if !catalog.result.loadedFiles.isEmpty {
                        Text(catalog.result.loadedFiles.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if !catalog.result.errors.isEmpty {
                        Text(catalog.result.errors.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    AppChromeButton.title("Reload Catalog", help: "Reload the gear/quality catalog") {
                        catalog.reload()
                        status = "Reloaded \(catalog.result.entries.count) entries."
                    }
                } header: {
                    Text("Built-in catalog")
                } footer: {
                    Text("Data is GPL-3.0-derived from Chummer5a (see Resources/Catalog/NOTICE.txt). Shadowrun remains a trademark of its owners; this is an unofficial fan tool.")
                }

                Section {
                    Toggle("Use external Chummer data folder (advanced)", isOn: $preferExternal)
                        .onChange(of: preferExternal) { _, newValue in
                            CatalogSettings.preferExternalCatalog = newValue
                            catalog.reload()
                        }

                    if preferExternal {
                        TextField("Path to Chummer data/", text: $externalPath)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            AppChromeButton.title("Choose Folder…", help: "Choose a Chummer data folder") {
                                chooseFolder()
                            }
                            AppChromeButton.title(
                                "Apply",
                                help: "Load catalog from the external folder",
                                style: .prominent
                            ) {
                                CatalogSettings.chummerDataPath = externalPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                CatalogSettings.preferExternalCatalog = true
                                preferExternal = true
                                catalog.reload()
                                status = catalog.result.isEmpty
                                    ? "No entries from external folder."
                                    : "Loaded \(catalog.result.entries.count) from external folder."
                            }
                        }
                    }
                } header: {
                    Text("Developer override")
                } footer: {
                    Text("Only needed if you regenerate catalogs from a Chummer checkout. End users should leave this off.")
                }

                if !status.isEmpty {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Catalog", systemImage: "books.vertical")
            }
        }
        .frame(width: 560, height: 440)
        .onAppear {
            preferExternal = CatalogSettings.preferExternalCatalog
            externalPath = CatalogSettings.chummerDataPath ?? ""
            catalog.ensureLoaded()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Chummer5a data folder (contains gear.xml, …)"
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        externalPath = url.path
        CatalogSettings.chummerDataPath = url.path
        CatalogSettings.preferExternalCatalog = true
        preferExternal = true
        catalog.reload()
        status = "External catalog: \(catalog.result.entries.count) entries."
    }
}

private extension Bundle {
    var shortVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#Preview {
    SettingsView()
}
