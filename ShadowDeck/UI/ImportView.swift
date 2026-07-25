//
//  ImportView.swift
//  ShadowDeck
//
//  File picker + drag-and-drop entry point for Chummer / ShadowDeck import.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false
    @State private var isImporting = false
    @State private var lastResult: ImportResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Character")
                .font(.title2.weight(.semibold))

            Text("Bring in Chummer5a exports (`.json` or `.chum5`) or native `.shadowdeck` packages. Original files are never modified.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            dropZone

            HStack {
                Button {
                    isImporterPresented = true
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

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let lastResult {
                resultPanel(lastResult)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: CharacterImporter.contentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importURL(url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            )
            .frame(maxWidth: 520, minHeight: 120)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Drop `.json`, `.chum5`, or `.shadowdeck` here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let urlItem = item as? URL {
                url = urlItem
            } else if let str = item as? String {
                url = URL(fileURLWithPath: str)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in
                await importURL(url)
            }
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
            let result = try libraryEnvironment.library.importAndSave(from: url)
            lastResult = result
            // Notify shell to refresh library list if needed via environment side channel.
            libraryEnvironment.lastErrorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ImportView()
        .environment(LibraryEnvironment.preview())
        .frame(width: 640, height: 520)
}
