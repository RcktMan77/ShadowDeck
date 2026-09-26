//
//  TestFixtures.swift
//  ShadowDeckTests
//
//  Load in-repo fixtures without probing the source tree path.
//  Fixtures ship in the test bundle (ShadowDeckTests/Fixtures) so the app
//  does not carry them, and tests do not touch ~/Desktop.
//

import Foundation
import XCTest

enum TestFixtures {
    /// Load a fixture file by name (e.g. `minimal_sr5.json`, `minimal_sr5.chum5`).
    static func data(named name: String) throws -> Data {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let bundles: [Bundle] = [
            Bundle(for: BundleToken.self),
            .main
        ]
        for bundle in bundles {
            let candidates: [URL?] = [
                bundle.url(forResource: base, withExtension: ext, subdirectory: "TestFixtures"),
                bundle.url(forResource: base, withExtension: ext, subdirectory: "Fixtures"),
                bundle.url(forResource: base, withExtension: ext)
            ]
            if let url = candidates.compactMap({ $0 }).first {
                return try Data(contentsOf: url)
            }
        }
        XCTFail(
            """
            Fixture “\(name)” not found in the test or app bundle. \
            Ensure ShadowDeckTests/Fixtures/\(name) is copied into the test bundle.
            """
        )
        throw FixtureError.notFound(name)
    }

    static func url(named name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for bundle in [Bundle(for: BundleToken.self), Bundle.main] {
            let candidates: [URL?] = [
                bundle.url(forResource: base, withExtension: ext, subdirectory: "TestFixtures"),
                bundle.url(forResource: base, withExtension: ext, subdirectory: "Fixtures"),
                bundle.url(forResource: base, withExtension: ext)
            ]
            if let url = candidates.compactMap({ $0 }).first {
                return url
            }
        }
        throw FixtureError.notFound(name)
    }

    enum FixtureError: Error, LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let name): "Test fixture not found: \(name)"
            }
        }
    }

    private final class BundleToken {}
}
