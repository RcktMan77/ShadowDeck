//
//  CharacterLibraryExportActions.swift
//  ShadowDeck
//
//  Save-panel export helpers for library characters (package / PDF / Chummer).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum CharacterLibraryExportActions {
    static func exportPackage(
        summary: CharacterSummary,
        library: CharacterLibrary
    ) throws -> String {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.shadowdeckCharacter]
        panel.nameFieldStringValue = "\(exportBaseName(summary)).\(ShadowDeckFormat.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Export a portable ShadowDeck character package"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw CancellationError()
        }
        try library.exportPackage(id: summary.id, to: url)
        return "Exported \(url.lastPathComponent)."
    }

    static func exportPDFSheet(
        summary: CharacterSummary,
        library: CharacterLibrary
    ) throws -> String {
        let character = try library.require(summary.id)
        let report = CampaignSheetReport.build(for: character)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(exportBaseName(summary))_sheet.pdf"
        panel.canCreateDirectories = true
        panel.message = "Export a printable ShadowDeck character sheet (PDF)"
        panel.prompt = "Export PDF"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw CancellationError()
        }
        try CharacterSheetPDF.write(report: report, to: url)
        return "Exported PDF sheet for \(summary.displayTitle)."
    }

    static func exportChummer(
        summary: CharacterSummary,
        library: CharacterLibrary
    ) throws -> String {
        let character = try library.require(summary.id)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "chum5") ?? .xml]
        panel.nameFieldStringValue = "\(exportBaseName(summary)).chum5"
        panel.canCreateDirectories = true
        let hasOriginal = character.importProvenance?.originalPayload != nil
        panel.message = hasOriginal
            ? "Export original imported Chummer file when available"
            : "Best-effort regenerated Chummer .chum5"
        panel.prompt = "Export .chum5"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw CancellationError()
        }
        let result = try ChummerXMLExporter.export(character, mode: .preferOriginal)
        try result.xmlData.write(to: url, options: .atomic)
        return result.usedOriginalPayload
            ? "Exported original Chummer file for \(summary.displayTitle)."
            : "Exported regenerated Chummer file for \(summary.displayTitle)."
    }

    private static func exportBaseName(_ summary: CharacterSummary) -> String {
        if !summary.streetName.isEmpty { return summary.streetName }
        if !summary.name.isEmpty { return summary.name }
        return "Runner"
    }
}
