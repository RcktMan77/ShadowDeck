//
//  ToolbarSupport.swift
//  ShadowDeck
//
//  Shared sticky-toolbar chrome: icon-only actions with reliable macOS tooltips.
//

import SwiftUI

/// Icon-only toolbar control. Prefer `Image` + `.help` over `Label` + `.labelStyle(.iconOnly)`,
/// which often fails to show tooltips on macOS custom HStack toolbars.
struct IconToolbarButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .frame(minWidth: 28, minHeight: 22)
                .contentShape(Rectangle())
        }
        // Apply help on the control *and* keep an accessibility name — both improve
        // tooltip reliability vs Label+iconOnly in non-NSToolbar stacks.
        .help(title)
        .accessibilityLabel(title)
        .accessibilityHint(title)
    }
}
