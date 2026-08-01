//
//  ContactInteractionSheet.swift
//  ShadowDeck
//
//  Add a dated interaction log entry. Favor direction is a historical snapshot;
//  updating current favorState is opt-in via checkbox.
//

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
                TextField("What happened…", text: $summary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
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
                Button("Cancel", action: onCancel)
                Button("Save") {
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
                .keyboardShortcut(.defaultAction)
                .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
