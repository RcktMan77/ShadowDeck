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
    /// Inverse of `AppPreferences.skipLaunchSplash` (default: show splash).
    @State private var showSplashOnStartup = !AppPreferences.bool(.skipLaunchSplash)
    @State private var status: String = ""
    @ObservedObject private var catalog = CatalogStore.shared

    var body: some View {
        TabView {
            Form {
                Section {
                    Toggle("Show splash screen on startup", isOn: $showSplashOnStartup)
                        .onChange(of: showSplashOnStartup) { _, show in
                            AppPreferences.set(!show, for: .skipLaunchSplash)
                        }
                } header: {
                    Text("Launch")
                } footer: {
                    Text("When on, ShadowDeck shows the launch splash on each cold start. Turn off to open the library window directly.")
                }

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
                    Text("ShadowDeck ships edition-scoped catalogs: SR4A and SR6 core packs for costs/names, plus a large SR5 reference catalog derived from Chummer5a’s open data. Management tabs load the catalog that matches the open character’s edition. No Chummer install is required.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledContent(
                        "Entries loaded",
                        value: "\(catalog.totalEntriesAcrossEditions)"
                    )
                    // Per-edition breakdown (SR4 → SR5 → SR6).
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(catalog.editionSummaries) { row in
                            if row.loadedFiles.isEmpty {
                                Text("\(row.edition.shortName): \(row.entryCount) entries")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(row.loadedFiles, id: \.self) { line in
                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            ForEach(row.errors, id: \.self) { err in
                                Text("\(row.edition.shortName): \(err)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if let dir = catalog.result.sourceDirectory {
                        LabeledContent("Active override source", value: dir.lastPathComponent)
                    }

                    AppChromeButton.title("Reload Catalog", help: "Reload all edition catalogs") {
                        catalog.reload()
                        status = "Reloaded \(catalog.totalEntriesAcrossEditions) entries across \(catalog.editionSummaries.count) editions."
                    }
                } header: {
                    Text("Built-in catalogs")
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
                                status = catalog.totalEntriesAcrossEditions == 0
                                    ? "No entries from external folder."
                                    : "Loaded \(catalog.totalEntriesAcrossEditions) entries across editions."
                            }
                        }
                    }
                } header: {
                    Text("Developer override")
                } footer: {
                    // Grouped Form footers default to centered; force natural leading wrap.
                    Text("Optional live Chummer data XML for SR5-oriented loads. End users should leave this off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: 560, height: 480)
        .onAppear {
            preferExternal = CatalogSettings.preferExternalCatalog
            externalPath = CatalogSettings.chummerDataPath ?? ""
            showSplashOnStartup = !AppPreferences.bool(.skipLaunchSplash)
            catalog.reload()
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
        status = "Reloaded catalogs: \(catalog.totalEntriesAcrossEditions) total entries."
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
