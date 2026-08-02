//
//  MainSidebarView.swift
//  ShadowDeck
//
//  Primary NavigationSplitView sidebar (Library + Create).
//

import SwiftUI

struct MainSidebarView: View {
    @Binding var selection: SidebarItem?
    var characterCount: Int
    var campaignCount: Int
    var runCount: Int
    var onNewRun: () -> Void

    var body: some View {
        // No `List(selection:)` — system selection greys out when the list is
        // not first responder (common right after splash / detail focus).
        List {
            Section("Library") {
                sidebarItem(.characters, badge: characterCount)
                sidebarItem(.campaigns, badge: campaignCount)
                sidebarItem(.runs, badge: runCount)
            }
            Section("Create") {
                sidebarItem(.newCharacter)
                sidebarItem(.importCharacter)
                sidebarItem(.newRun)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 28)
    }

    private func sidebarItem(_ item: SidebarItem, badge: Int? = nil) -> some View {
        let isSelected = selection == item
        return Button {
            if item == .newRun {
                // Re-clicking New Run while already selected still mints a fresh job.
                onNewRun()
            } else {
                selection = item
            }
        } label: {
            HStack(spacing: 0) {
                sidebarLabel(item, isSelected: isSelected)
                Spacer(minLength: 8)
                if let badge {
                    Text("\(badge)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .listRowBackground(sidebarRowBackground(isSelected: isSelected))
        .help(item.help ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sidebarLabel(_ item: SidebarItem, isSelected: Bool) -> some View {
        Label {
            Text(item.title)
                .font(.body.weight(isSelected ? .semibold : .regular))
        } icon: {
            Image(systemName: item.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(width: 24, height: 20, alignment: .center)
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Color.primary)
    }

    private func sidebarRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
    }
}
