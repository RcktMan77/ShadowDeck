//
//  SettingsView.swift
//  ShadowDeck
//
//  App preferences. Expanded in later phases (house rules, defaults, paths).
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Form {
                Section("About") {
                    LabeledContent("Application", value: "ShadowDeck")
                    LabeledContent("Version", value: Bundle.main.shortVersionString)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
        }
        .frame(width: 420, height: 240)
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
