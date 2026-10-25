// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  TMDBMediaMapper.swift
//  Rivulet
//
//  TMDB DTO -> agnostic-type translations. Mirror of PlexMediaMapper for
//  the TMDB MetadataSource side.
//

import Foundation

enum TMDBMediaMapper {
    static let providerID = "tmdb"

    private static let backdropBase = "https://image.tmdb.org/t/p/original"
    // w780 (not w500): posters appear on large carousel/detail cards where w500
    // visibly upscales. Still small enough that row cards downsample cheaply.
    private static let posterBase = "https://image.tmdb.org/t/p/w780"

    /// TMDB ids are not globally unique — id 100 can exist as a movie AND a TV
    /// show. `MediaItemRef.itemID` encodes both so callers that only have a ref
    /// can disambiguate without a second round-trip. Format: "{movie|tv}:{id}".
    /// Decoding tolerates bare numeric itemIDs for backward compatibility with
    /// anything persisted before this format landed.
    static func encodeItemID(tmdbId: Int, type: TMDBMediaType) -> String {
        "\(type.rawValue):\(tmdbId)"
    }

    static func decodeItemID(_ itemID: String) -> (tmdbId: Int, type: TMDBMediaType)? {
        let parts = itemID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let type = TMDBMediaType(rawValue: parts[0]),
              let id = Int(parts[1]) else { return nil }
        return (id, type)
    }

    static func item(_ tmdb: TMDBListItem) -> MediaItem {
        // TMDBMediaType currently only has .movie / .tv (TMDBClient.swift).
        // If TMDB person results are ever supported, extend both that enum
        // and this mapping to cover .person.
        let kind: MediaKind = (tmdb.mediaType == .movie) ? .movie : .show
        let year: Int? = {
            guard let raw = tmdb.releaseDate?.prefix(4), !raw.isEmpty else { return nil }
            return Int(raw)
        }()
        let artwork = MediaArtwork(
            poster: tmdb.posterPath.flatMap { URL(string: "\(posterBase)\($0)") },
            backdrop: tmdb.backdropPath.flatMap { URL(string: "\(backdropBase)\($0)") },
            thumbnail: tmdb.posterPath.flatMap { URL(string: "\(posterBase)\($0)") },
            logo: nil
        )
        return MediaItem(
            ref: MediaItemRef(providerID: providerID, itemID: encodeItemID(tmdbId: tmdb.id, type: tmdb.mediaType)),
            kind: kind,
            title: tmdb.title,
            sortTitle: nil,
            overview: tmdb.overview,
            year: year,
            releaseDate: tmdb.releaseDate,
            contentRating: nil,
            runtime: nil,
            parentRef: nil,
            grandparentRef: nil,
            episodeNumber: nil,
            seasonNumber: nil,
            childProgress: nil,
            userState: MediaUserState(isPlayed: false, viewOffset: 0, isFavorite: false, lastViewedAt: nil),
            artwork: artwork,
            parentArtwork: nil,
            grandparentArtwork: nil
        )
    }

    static func detail(_ tmdb: TMDBItemDetail) -> MediaItemDetail {
        func person(_ credit: TMDBCredit, filter: String = "actor") -> MediaPerson {
            MediaPerson(
                id: "\(credit.id ?? 0)", name: credit.name ?? "",
                role: credit.character ?? credit.job,
                imageURL: credit.profilePath.flatMap { URL(string: "https://image.tmdb.org/t/p/w185" + $0) },
                originFilter: filter, titleTmdbId: tmdb.id, titleIsMovie: tmdb.mediaType == .movie,
                backdropURL: tmdb.backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280" + $0) })
        }
        let cast = tmdb.cast.filter { $0.id != nil && $0.name != nil }.map { person($0) }
        let directors = tmdb.crew.filter { $0.job == "Director" }.map { person($0, filter: "director") }
        let writers = tmdb.crew.filter { $0.department == "Writing" }.map { person($0, filter: "writer") }
        let trailers: [MediaItemDetail.Extra] = tmdb.videos.compactMap { video in
            guard video.site == "YouTube", video.type == "Trailer" || video.type == "Teaser",
                  !video.key.isEmpty else { return nil }
            var url = URLComponents(string: "https://www.youtube.com/watch")!
            url.queryItems = [URLQueryItem(name: "v", value: video.key)]
            return MediaItemDetail.Extra(
                id: video.id, title: video.name,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(video.key)/hqdefault.jpg"),
                duration: nil, playbackKey: url.url?.absoluteString,
                providerID: providerID, subtype: .trailer)
        }
        // Re-stub a TMDBListItem so we can reuse `item(_:)` for the embedded MediaItem.
        let stub = TMDBListItem(
            id: tmdb.id,
            title: tmdb.title,
            overview: tmdb.overview,
            posterPath: tmdb.posterPath,
            backdropPath: tmdb.backdropPath,
            releaseDate: tmdb.releaseDate,
            voteAverage: tmdb.voteAverage,
            mediaType: tmdb.mediaType
        )
        let runtime: TimeInterval? = tmdb.runtime.map { TimeInterval($0 * 60) }
        var embedded = item(stub)
        embedded = MediaItem(
            ref: embedded.ref,
            kind: embedded.kind,
            title: embedded.title,
            sortTitle: embedded.sortTitle,
            overview: embedded.overview,
            year: embedded.year,
            releaseDate: embedded.releaseDate,
            contentRating: embedded.contentRating,
            runtime: runtime,
            parentRef: embedded.parentRef,
            grandparentRef: embedded.grandparentRef,
            episodeNumber: embedded.episodeNumber,
            seasonNumber: embedded.seasonNumber,
            childProgress: embedded.childProgress,
            userState: embedded.userState,
            artwork: embedded.artwork,
            parentArtwork: embedded.parentArtwork,
            grandparentArtwork: embedded.grandparentArtwork
        )
        return MediaItemDetail(
            item: embedded,
            tagline: nil,
            genres: tmdb.genres.compactMap(\.name),
            studios: [],
            cast: cast,
            directors: directors,
            writers: writers,
            chapters: [],
            mediaSources: [],
            trailerURL: trailers.first?.playbackKey.flatMap(URL.init(string:)),
            contentRating: nil,
            ratings: MediaRating.ordered([MediaRating(tmdb.voteAverage, source: .tmdb)]),
            nextEpisode: nil,
            collections: [],
            extras: trailers
        )
    }
}

extension MediaItem {
    /// True when the item exists only as external metadata (TMDB-mapped, no
    /// playback-capable MediaProvider registered for its ref). Surfaces
    /// should offer Watchlist as the primary action instead of Play, and
    /// hide watched-state controls.
    var isMetadataOnly: Bool { ref.providerID == TMDBMediaMapper.providerID }

    /// The TMDB id for metadata-only items (nil for provider-backed items).
    var tmdbID: Int? {
        guard isMetadataOnly else { return nil }
        return TMDBMediaMapper.decodeItemID(ref.itemID)?.tmdbId
    }
}
