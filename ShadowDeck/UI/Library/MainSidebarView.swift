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
    var onNewCampaign: () -> Void
    var onNewRun: () -> Void
    var onNewRunFromTemplate: () -> Void

    var body: some View {
        // No `List(selection:)` — system selection greys out when the list is
        // not first responder (common right after splash / detail focus).
        List {
            // Hierarchy: characters → runs → campaigns (campaigns group runs).
            Section("Library") {
                sidebarItem(.characters, badge: characterCount)
                sidebarItem(.runs, badge: runCount)
                sidebarItem(.campaigns, badge: campaignCount)
            }
            // Create: character (+ import), run menu, campaign.
            Section("Create") {
                sidebarItem(.newCharacter)
                sidebarItem(.importCharacter)
                newRunMenuRow
                sidebarItem(.newCampaign)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 28)
    }

    /// New Run as a menu (blank run + from template) — one Create row, like the Run Library toolbar.
    private var newRunMenuRow: some View {
        let isSelected = selection == .newRun
        return Menu {
            Button("New Run") { onNewRun() }
            Button("New Run from Template…") { onNewRunFromTemplate() }
        } label: {
            HStack(spacing: 0) {
                sidebarLabel(.newRun, isSelected: isSelected)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .menuStyle(.borderlessButton)
        .listRowBackground(sidebarRowBackground(isSelected: isSelected))
        .help("Create a blank mission or start from a template")
    }

    private func sidebarItem(_ item: SidebarItem, badge: Int? = nil) -> some View {
        let isSelected = selection == item
        return Button {
            switch item {
            case .newRun:
                // Re-clicking New Run while already selected still mints a fresh job.
                onNewRun()
            case .newRunFromTemplate:
                onNewRunFromTemplate()
            case .newCampaign:
                // Same pattern: always mint a campaign and open its detail.
                onNewCampaign()
            default:
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
            // Base icon; optional shared + badge so Create Run / Create Campaign align
            // (system `doc.badge.plus` vs `folder.badge.plus` place the + in different corners).
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                if item.showsCreatePlusBadge {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : Color.primary)
                        .offset(x: 5, y: -4)
                }
            }
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
