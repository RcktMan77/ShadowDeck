//
//  AppCommands.swift
//  ShadowDeck
//
//  Phase 8 — menu actions and open-package notifications shared app-wide.
//

import Foundation

public enum AppCommand {
    public static let newCharacter = Notification.Name("com.shadowdeck.command.newCharacter")
    public static let newRun = Notification.Name("com.shadowdeck.command.newRun")
    public static let importCharacter = Notification.Name("com.shadowdeck.command.importCharacter")
    public static let openPackage = Notification.Name("com.shadowdeck.command.openPackage")
    /// Posted with a `URL` object when Finder / File > Open hands us a package.
    public static let openPackageURL = Notification.Name("com.shadowdeck.openPackageURL")
    /// Marketing screenshot runner: seed samples if library empty.
    public static let seedSamplesForScreenshots = Notification.Name("com.shadowdeck.marketing.seedSamples")
    /// Marketing screenshot runner: open character by UUID (object is UUID).
    public static let openCharacterForScreenshots = Notification.Name("com.shadowdeck.marketing.openCharacter")
    /// Marketing screenshot runner: jump generation wizard to Concept & Role.
    public static let wizardShowRoleStep = Notification.Name("com.shadowdeck.marketing.wizardRole")
}

import UniformTypeIdentifiers

public extension UTType {
    /// Declared exported type for `.shadowdeck` character packages.
    static var shadowdeckCharacter: UTType {
        // Prefer filename extension resolution; fall back to exported UTI identity.
        if let byExt = UTType(filenameExtension: ShadowDeckFormat.fileExtension) {
            return byExt
        }
        return UTType(exportedAs: ShadowDeckFormat.utTypeIdentifier)
    }
}
