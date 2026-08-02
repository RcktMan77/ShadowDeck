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
        // Use a plain label layout (not system Menu chevron-only styling) so the shared
        // top-trailing + badge matches New Campaign and is not clipped by Menu defaults.
        return Menu {
            Button("New Run") { onNewRun() }
            Button("New Run from Template…") { onNewRunFromTemplate() }
        } label: {
            HStack(spacing: 0) {
                createSidebarIcon(
                    systemImage: SidebarItem.newRun.systemImage,
                    showPlusBadge: true,
                    isSelected: isSelected
                )
                Text(SidebarItem.newRun.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                    .padding(.leading, 8)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .listRowBackground(sidebarRowBackground(isSelected: isSelected))
        .help("Create a blank mission or start from a template")
    }

    private func sidebarItem(_ item: SidebarItem, badge: Int? = nil) -> some View {
        let isSelected = selection == item
        return Button {
            switch item {
            case .newRun:
                onNewRun()
            case .newRunFromTemplate:
                onNewRunFromTemplate()
            case .newCampaign:
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
            createSidebarIcon(
                systemImage: item.systemImage,
                showPlusBadge: item.showsCreatePlusBadge,
                isSelected: isSelected
            )
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Color.primary)
    }

    /// Shared icon metrics so Library and Create create-actions align, including + badge.
    private func createSidebarIcon(
        systemImage: String,
        showPlusBadge: Bool,
        isSelected: Bool
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            if showPlusBadge {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.primary)
                    .offset(x: 5, y: -4)
            }
        }
        // Extra room so Menu / List do not clip the top-trailing badge.
        .frame(width: 26, height: 22, alignment: .center)
        .padding(.trailing, 2)
    }

    private func sidebarRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
    }
}
