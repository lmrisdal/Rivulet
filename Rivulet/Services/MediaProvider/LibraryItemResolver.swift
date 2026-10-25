// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  LibraryItemResolver.swift
//  Rivulet
//
//  Opens the library copy of a metadata-only (TMDB) item when the user owns
//  it, so every route into detail lands on the playable item instead of the
//  TMDB entry.
//

import Foundation

@MainActor
enum LibraryItemResolver {
    /// The library copy of a metadata-only item, from the in-memory Plex GUID
    /// index. Nil for provider-backed items and titles not in the library.
    static func libraryItem(for item: MediaItem) async -> MediaItem? {
        guard item.isMetadataOnly,
              let decoded = TMDBMediaMapper.decodeItemID(item.ref.itemID) else { return nil }
        return await libraryItem(tmdbID: decoded.tmdbId, type: decoded.type)
    }

    static func libraryItem(tmdbID: Int, type: TMDBMediaType) async -> MediaItem? {
        let auth = PlexAuthManager.shared
        guard let serverURL = auth.selectedServerURL,
              let token = auth.selectedServerToken,
              let match = await LibraryGUIDIndex.shared.lookup(tmdbId: tmdbID, type: type) else { return nil }
        let providerID = MediaProviderRegistry.shared.plexProvider?.id ?? "plex:\(serverURL)"
        return PlexMediaMapper.item(match, providerID: providerID, serverURL: serverURL, authToken: token)
    }

    /// `item`, or its library copy when there is one.
    static func resolved(_ item: MediaItem) async -> MediaItem {
        await libraryItem(for: item) ?? item
    }

    /// Each metadata-only item swapped for its library copy where there is one.
    static func resolved(_ items: [MediaItem]) async -> [MediaItem] {
        guard items.contains(where: \.isMetadataOnly) else { return items }
        var out = items
        for (index, item) in items.enumerated() where item.isMetadataOnly {
            if let match = await libraryItem(for: item) { out[index] = match }
        }
        return out
    }
}
