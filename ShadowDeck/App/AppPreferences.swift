//
//  AppPreferences.swift
//  ShadowDeck
//
//  Typed UserDefaults keys for app-wide preferences (no free-floating string keys).
//

import Foundation

/// Central schema for UserDefaults keys used by ShadowDeck.
enum AppPreferences {
    enum Key: String {
        // Launch / window
        case mainWindowFrame = "ShadowDeck.mainWindowFrame"
        /// Legacy once-per-install flag; removed on launch.
        case hasSeenLaunchSplash = "hasSeenLaunchSplash"
        /// Legacy revision counter; removed on launch (splash always shows).
        case launchSplashRevision = "launchSplashRevision"

        // Catalog
        case chummerDataPath = "chummerDataPath"
        case preferExternalChummerCatalog = "preferExternalChummerCatalog"

        // Rules Reference UI state
        case rulesRefMode = "RulesRef.mode"
        case rulesRefQuery = "RulesRef.query"
        case rulesRefCategory = "RulesRef.category"
        case rulesRefEdition = "RulesRef.edition"
        case rulesRefSelectedID = "RulesRef.selectedID"
        case rulesRefLibraryLayout = "RulesRef.libraryLayout"
        case rulesRefLibrarySort = "RulesRef.librarySort"
        case rulesRefLibraryItem = "RulesRef.libraryItem"
        case rulesRefPDFPage = "RulesRef.pdfPage"
        case rulesRefZoomMap = "RulesRef.zoomMap"
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Generic accessors

    static func string(_ key: Key) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    static func set(_ value: String?, for key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    static func int(_ key: Key) -> Int {
        defaults.integer(forKey: key.rawValue)
    }

    static func set(_ value: Int, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    static func bool(_ key: Key) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    static func set(_ value: Bool, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    static func data(_ key: Key) -> Data? {
        defaults.data(forKey: key.rawValue)
    }

    static func set(_ value: Data?, for key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    static func remove(_ key: Key) {
        defaults.removeObject(forKey: key.rawValue)
    }
}
