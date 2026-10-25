// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  SeerrClient.swift
//  Rivulet
//
//  Seerr (Overseerr / Jellyseerr) request API: what a title's request state
//  is, and making a request. Requests made with the API key are made as the
//  Seerr admin, which auto-approves them on a default install.
//

import Foundation

nonisolated enum SeerrMediaType: String, Sendable {
    case movie, tv
}

/// Seerr's `MediaStatus`.
nonisolated enum SeerrMediaStatus: Int, Sendable {
    case unknown = 1, pending, processing, partiallyAvailable, available, blocklisted, deleted
}

/// Seerr's `MediaRequestStatus`.
nonisolated enum SeerrRequestStatus: Int, Sendable {
    case pending = 1, approved, declined, failed, completed
}

nonisolated struct SeerrDownload: Decodable, Equatable, Sendable {
    let size: Double?
    let sizeLeft: Double?
}

nonisolated struct SeerrMediaDetail: Decodable, Sendable {
    struct Season: Decodable, Sendable {
        let seasonNumber: Int
        let name: String?
    }
    struct ExternalIDs: Decodable, Sendable {
        let tvdbId: Int?
    }
    struct MediaInfo: Decodable, Sendable {
        struct SeasonStatus: Decodable, Sendable {
            let seasonNumber: Int
            let status: Int?
        }
        struct Request: Decodable, Sendable {
            struct RequestedSeason: Decodable, Sendable {
                let seasonNumber: Int
            }
            let status: Int?
            let is4k: Bool?
            let requestedBy: SeerrRequest.User?
            let seasons: [RequestedSeason]?
        }
        let status: Int?
        let seasons: [SeasonStatus]?
        let requests: [Request]?
        let downloadStatus: [SeerrDownload]?
        /// The library copy once Seerr has seen it: Plex ratingKey or Jellyfin item id.
        let ratingKey: String?
        let jellyfinMediaId: String?
    }

    let id: Int?
    let seasons: [Season]?
    let externalIds: ExternalIDs?
    let mediaInfo: MediaInfo?
    /// TMDB's own fields, which Seerr passes through. Movies carry `title` and
    /// `releaseDate`, shows `name` and `firstAirDate`.
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?

    var status: SeerrMediaStatus {
        mediaInfo?.status.flatMap(SeerrMediaStatus.init(rawValue:)) ?? .unknown
    }

    /// True while a non-4K request is waiting for approval.
    var hasPendingRequest: Bool {
        activeRequests.contains { $0.status == SeerrRequestStatus.pending.rawValue }
    }

    var requesterName: String? {
        activeRequests.compactMap { $0.requestedBy?.displayName }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var activeRequests: [MediaInfo.Request] {
        (mediaInfo?.requests ?? []).filter { request in
            request.is4k != true
                && (request.status == SeerrRequestStatus.pending.rawValue
                    || request.status == SeerrRequestStatus.approved.rawValue)
        }
    }

    /// Seasons that are neither on the server nor already asked for. Specials
    /// (season 0) are left out, as Seerr's own request dialog does by default.
    var requestableSeasons: [Season] {
        let handled = Set((mediaInfo?.seasons ?? []).compactMap { season -> Int? in
            guard let status = season.status.flatMap(SeerrMediaStatus.init(rawValue:)) else { return nil }
            return status == .unknown || status == .deleted ? nil : season.seasonNumber
        })
        let requested = Set(activeRequests.flatMap { $0.seasons ?? [] }.map(\.seasonNumber))
        return (seasons ?? []).filter {
            $0.seasonNumber > 0 && !handled.contains($0.seasonNumber) && !requested.contains($0.seasonNumber)
        }
    }
}

/// One entry of Seerr's request list. Carries no title or artwork: those come
/// from the title's detail.
nonisolated struct SeerrRequest: Decodable, Sendable {
    struct Media: Decodable, Sendable {
        let tmdbId: Int?
        let tvdbId: Int?
        let mediaType: String?
        let status: Int?
        let downloadStatus: [SeerrDownload]?
        let ratingKey: String?
        let jellyfinMediaId: String?
    }
    struct User: Decodable, Sendable {
        let displayName: String?
    }
    struct RequestedSeason: Decodable, Sendable {
        let seasonNumber: Int
    }
    let id: Int
    let status: Int?
    let type: String?
    let is4k: Bool?
    let media: Media?
    let requestedBy: User?
    let seasons: [RequestedSeason]?

    var mediaType: SeerrMediaType? {
        (media?.mediaType ?? type).flatMap(SeerrMediaType.init(rawValue:))
    }
}

nonisolated struct SeerrClient: Sendable {
    let http: IntegrationHTTPClient

    init(config: IntegrationConfig) {
        http = IntegrationHTTPClient(config: config)
    }

    /// Checks the URL and the key together: `auth/me` needs a valid key.
    func testConnection() async throws -> String {
        struct Me: Decodable { let displayName: String? }
        let me = try await http.get(Me.self, "api/v1/auth/me")
        return me.displayName.map { "Signed in as \($0)." } ?? "Connected."
    }

    func detail(tmdbID: Int, type: SeerrMediaType) async throws -> SeerrMediaDetail {
        try await http.get(SeerrMediaDetail.self, "api/v1/\(type.rawValue)/\(tmdbID)")
    }

    /// The newest requests first, from every user.
    /// Most recently changed first, so a title that just became available leads History.
    func requests(take: Int = 100) async throws -> [SeerrRequest] {
        struct Page: Decodable { let results: [SeerrRequest] }
        return try await http.get(Page.self, "api/v1/request", query: [
            URLQueryItem(name: "take", value: String(take)),
            URLQueryItem(name: "skip", value: "0"),
            URLQueryItem(name: "filter", value: "all"),
            URLQueryItem(name: "sort", value: "modified"),
        ]).results
    }

    /// `seasons` is required for TV and ignored for movies.
    func request(tmdbID: Int, type: SeerrMediaType, seasons: [Int] = [], tvdbID: Int? = nil) async throws {
        var body: [String: Any] = ["mediaType": type.rawValue, "mediaId": tmdbID]
        if type == .tv {
            body["seasons"] = seasons
            if let tvdbID { body["tvdbId"] = tvdbID }
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await http.send("api/v1/request", method: "POST", body: data)
    }
}
