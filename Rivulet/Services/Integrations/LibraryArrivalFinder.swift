// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  LibraryArrivalFinder.swift
//  Rivulet
//
//  Finds the library copy of a requested title once it has arrived, so the
//  detail page can switch from the TMDB entry to the playable one.
//  Seerr's own pointer comes first; otherwise the newest additions on each
//  server are matched by title, and confirmed by their TMDB id.
//

import Foundation

@MainActor
enum LibraryArrivalFinder {
    static func find(tmdbID: Int, type: SeerrMediaType, title: String, year: Int?,
                     snapshot: MediaRequestSnapshot?) async -> MediaItem? {
        let providers = MediaProviderRegistry.shared.enabledProviders()
        var hinted: [(any MediaProvider, MediaItemRef)] = []
        if let key = snapshot?.plexRatingKey, let plex = MediaProviderRegistry.shared.plexProvider {
            hinted.append((plex, MediaItemRef(providerID: plex.id, itemID: key)))
        }
        if let id = snapshot?.jellyfinItemID {
            for provider in providers where provider.kind == .jellyfin {
                hinted.append((provider, MediaItemRef(providerID: provider.id, itemID: id)))
            }
        }
        for (provider, ref) in hinted {
            if let item = await confirmed(ref, on: provider, tmdbID: tmdbID) { return item }
        }

        let kind: MediaKind = type == .movie ? .movie : .show
        for provider in providers {
            guard let recent = try? await provider.recentlyAdded(limit: 30) else { continue }
            for ref in candidateRefs(in: recent, title: title, year: year, kind: kind) {
                if let item = await confirmed(ref, on: provider, tmdbID: tmdbID) { return item }
            }
        }
        return nil
    }

    /// The item behind `ref`, if it really is this TMDB title.
    private static func confirmed(_ ref: MediaItemRef, on provider: any MediaProvider,
                                  tmdbID: Int) async -> MediaItem? {
        guard let detail = try? await provider.fullDetail(for: ref),
              detail.externalIDs["tmdb"] == String(tmdbID) else { return nil }
        return detail.item
    }

    /// Refs among `items` worth checking: movies by their own title, shows
    /// through whichever season or episode was added. Deduplicated, in order.
    nonisolated static func candidateRefs(in items: [MediaItem], title: String, year: Int?,
                                          kind: MediaKind) -> [MediaItemRef] {
        let wanted = normalized(title)
        var seen = Set<MediaItemRef>()
        var refs: [MediaItemRef] = []
        for item in items {
            let match: (ref: MediaItemRef, title: String)?
            switch (kind, item.kind) {
            case (.movie, .movie): match = (item.ref, item.title)
            case (.show, .show): match = (item.ref, item.title)
            case (.show, .season): match = item.parentRef.map { ($0, item.seriesTitle ?? "") }
            case (.show, .episode): match = item.grandparentRef.map { ($0, item.seriesTitle ?? "") }
            default: match = nil
            }
            guard let match, normalized(match.title) == wanted else { continue }
            if kind == .movie, let year, let itemYear = item.year, abs(itemYear - year) > 1 { continue }
            if seen.insert(match.ref).inserted { refs.append(match.ref) }
        }
        return refs
    }

    nonisolated static func normalized(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}
