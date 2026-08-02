//
//  LibraryFileDrop.swift
//  ShadowDeck
//
//  Shared NSItemProvider → file URL extraction for library / import drops.
//

import Foundation
import UniformTypeIdentifiers

enum LibraryFileDrop {
    /// Load the first file URL from drag-and-drop providers (async).
    static func firstFileURL(from providers: [NSItemProvider]) async -> URL? {
        guard let provider = providers.first else { return nil }
        return await withCheckedContinuation { continuation in
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
                continuation.resume(returning: url)
            }
        }
    }
}
