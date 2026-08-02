//
//  ImportView.swift
//  ShadowDeck
//
//  File picker + drag-and-drop entry point for Chummer / ShadowDeck import.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    /// Called after a successful import when the user taps Done (e.g. return to library).
    var onFinished: ((UUID) -> Void)?

    @State private var isDropTargeted = false
    @State private var isImporting = false
    @State private var lastResult: ImportResult?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Import Character")
                    .font(.title2.weight(.semibold))

                Text("Import Chummer5a (`.json` / `.chum5`) or native `.shadowdeck` packages into your library. One place for all character imports — original files are never modified.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        presentOpenPanel()
                    } label: {
                        Label("Choose File…", systemImage: "folder")
                    }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(isImporting)

                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Importing…")
                            .foregroundStyle(.secondary)
                    }
                }

                dropZone

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if let lastResult {
                    resultPanel(lastResult)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Drop target sized around a standard macOS icon (64×64).
    private var dropZone: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Drop a character file here")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                Text("`.json`, `.chum5`, or `.shadowdeck`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 440, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func resultPanel(_ result: ImportResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(result.userFacingSummary, systemImage: result.isPartial ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.headline)

                LabeledContent("Name", value: result.character.displayTitle)
                LabeledContent("Edition", value: result.character.edition.rawValue)
                LabeledContent("Metatype", value: result.character.metatype.displayName)
                LabeledContent("Path", value: result.character.awakened.displayName)
                LabeledContent("Skills", value: "\(result.character.skills.count)")
                LabeledContent("Qualities", value: "\(result.character.qualities.count)")
                LabeledContent("Contacts", value: "\(result.character.contacts.count)")
                LabeledContent("Nuyen", value: "\(result.character.nuyen)")
                LabeledContent("Karma", value: "\(result.character.karmaAvailable) available / \(result.character.karmaTotal) total")

                if !result.issues.isEmpty {
                    Divider()
                    Text("Messages")
                        .font(.subheadline.weight(.semibold))
                    ForEach(result.issues.prefix(12)) { issue in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: icon(for: issue.severity))
                                .foregroundStyle(color(for: issue.severity))
                            Text(issue.message)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    if result.issues.count > 12 {
                        Text("…and \(result.issues.count - 12) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack {
                    Button("Import Another…") {
                        presentOpenPanel()
                    }
                    .disabled(isImporting)

                    Spacer()

                    Button("Done") {
                        onFinished?(result.character.id)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
        } label: {
            Text("Last Import")
        }
    }

    private func icon(for severity: ValidationSeverity) -> String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }

    private func color(for severity: ValidationSeverity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .info: .secondary
        }
    }

    /// Native macOS open panel so the user can navigate the filesystem freely.
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Character"
        panel.message = "Choose a Chummer export (.json / .chum5) or a ShadowDeck package"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = CharacterImporter.contentTypes
        // .chum5 / .shadowdeck may not always resolve to a registered UTI;
        // allow the user to pick “All Files” style selections when needed.
        panel.allowsOtherFileTypes = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importURL(url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            guard let url = await LibraryFileDrop.firstFileURL(from: providers) else { return }
            await importURL(url)
        }
        return true
    }

    @MainActor
    private func importURL(_ url: URL) async {
        isImporting = true
        errorMessage = nil
        lastResult = nil
        defer { isImporting = false }

        do {
            let result = try await libraryEnvironment.library.importAndSave(from: url)
            lastResult = result
            libraryEnvironment.lastErrorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ImportView { _ in }
        .environment(LibraryEnvironment.preview())
        .frame(width: 640, height: 520)
}
