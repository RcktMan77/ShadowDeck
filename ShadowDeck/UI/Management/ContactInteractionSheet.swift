//
//  ContactInteractionSheet.swift
//  ShadowDeck
//
//  Add a dated interaction log entry. Favor direction is a historical snapshot;
//  updating current favorState is opt-in via checkbox.
//

import AppKit
import SwiftUI

struct ContactInteractionSheet: View {
    let contactName: String
    let runSummaries: [RunSummary]
    var onCancel: () -> Void
    var onSave: (_ entry: ContactInteraction, _ updateCurrentFavor: Bool) -> Void

    @State private var date = Date()
    @State private var summary = ""
    @State private var favorDirection: ContactFavorState = .none
    @State private var relatedRunID: UUID?
    @State private var updateCurrentFavor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Interaction")
                .font(.title2.weight(.semibold))
            Text("Log a touchpoint with \(contactName). Favor direction is recorded as history only unless you opt in below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .frame(maxWidth: 320)

            VStack(alignment: .leading, spacing: 4) {
                Text("Summary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                // Multi-line wrapping box (~2–3 lines). TextField axis:.vertical still
                // scrolls sideways on macOS; TextEditor wraps and scrolls vertically.
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $summary)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                    if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("What happened…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 56, idealHeight: 64, maxHeight: 80)
                .frame(maxWidth: .infinity)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Favor (snapshot for this entry)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Favor", selection: $favorDirection) {
                    ForEach(ContactFavorState.allCases) { state in
                        Text(state.displayName).tag(state)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Toggle("Also update current favor status", isOn: $updateCurrentFavor)
                    .toggleStyle(.checkbox)
                    .disabled(favorDirection == .none)
                    .help("When checked, sets the contact’s current favor standing to this direction. Off by default so the log stays historical.")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Related run (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Run", selection: $relatedRunID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(runSummaries) { summary in
                        Text(summary.title.isEmpty ? "Untitled run" : summary.title)
                            .tag(Optional(summary.id))
                    }
                }
                .frame(maxWidth: 400)
            }

            HStack {
                Spacer()
                AppChromeButton.title("Cancel", help: "Close without saving") {
                    onCancel()
                }
                AppChromeButton.title(
                    "Save",
                    help: "Save this interaction",
                    style: .prominent,
                    isEnabled: !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    keyEquivalent: "\r"
                ) {
                    var entry = ContactInteraction(
                        date: date,
                        summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                        favorDirection: favorDirection == .none ? nil : favorDirection,
                        relatedRunID: relatedRunID
                    )
                    // Store none as nil for cleaner history, or keep none — plan allows optional.
                    if favorDirection == .none {
                        entry.favorDirection = nil
                    }
                    onSave(entry, updateCurrentFavor && favorDirection != .none)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
