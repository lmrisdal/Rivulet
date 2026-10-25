// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  ArrClient.swift
//  Rivulet
//
//  Radarr and Sonarr, read only: find the title, then read its download queue.
//  Both share the v3 API shape, so one client serves both.
//

import Foundation

/// How far along a title's downloads are, summed over every queue entry (a
/// season pack and loose episodes alike).
nonisolated struct DownloadProgress: Equatable, Sendable {
    let fraction: Double
    let downloads: Int

    /// nil when nothing with a known size is downloading.
    init?(sizes: [(size: Double, left: Double)]) {
        let known = sizes.filter { $0.size > 0 }
        guard !known.isEmpty else { return nil }
        let total = known.reduce(0) { $0 + $1.size }
        let left = known.reduce(0) { $0 + min(max($1.left, 0), $1.size) }
        fraction = min(max(1 - left / total, 0), 1)
        downloads = known.count
    }

    var percentText: String { "\(Int((fraction * 100).rounded(.down)))%" }
}

nonisolated struct ArrQueueItem: Decodable, Sendable {
    let size: Double?
    let sizeleft: Double?
}

/// One entry of the whole download queue, with the movie or series it belongs to.
nonisolated struct ArrQueueRecord: Decodable, Sendable {
    struct Image: Decodable, Sendable {
        let coverType: String?
        let remoteUrl: String?
    }
    struct Title: Decodable, Sendable {
        let title: String?
        let year: Int?
        let tmdbId: Int?
        let tvdbId: Int?
        let images: [Image]?

        var posterURL: URL? {
            images?.first { $0.coverType == "poster" }?.remoteUrl.flatMap(URL.init(string:))
        }
    }
    struct Episode: Decodable, Sendable {
        let seasonNumber: Int?
        let episodeNumber: Int?
    }
    let movieId: Int?
    let seriesId: Int?
    let size: Double?
    let sizeleft: Double?
    let status: String?
    let trackedDownloadState: String?
    /// A .NET TimeSpan, "hh:mm:ss" or "d.hh:mm:ss".
    let timeleft: String?
    let movie: Title?
    let series: Title?
    let episode: Episode?
}

nonisolated struct ArrClient: Sendable {
    let service: IntegrationService
    let http: IntegrationHTTPClient

    init(service: IntegrationService, config: IntegrationConfig) {
        self.service = service
        http = IntegrationHTTPClient(config: config)
    }

    func testConnection() async throws -> String {
        struct Status: Decodable { let appName: String?; let version: String? }
        let status = try await http.get(Status.self, "api/v3/system/status")
        let name = status.appName ?? service.displayName
        return status.version.map { "Connected to \(name) \($0)." } ?? "Connected to \(name)."
    }

    /// The download progress of a movie (Radarr) or a series (Sonarr), or nil
    /// when the title is not in that app or nothing of it is downloading.
    func progress(tmdbID: Int, tvdbID: Int?) async throws -> DownloadProgress? {
        guard let id = try await libraryID(tmdbID: tmdbID, tvdbID: tvdbID) else { return nil }
        let queryName = service == .radarr ? "movieId" : "seriesId"
        let queue = try await http.get([ArrQueueItem].self, "api/v3/queue/details",
                                       query: [URLQueryItem(name: queryName, value: String(id))])
        return DownloadProgress(sizes: queue.map { ($0.size ?? 0, $0.sizeleft ?? 0) })
    }

    /// Everything in the download queue, in queue order.
    func queue() async throws -> [ArrQueueRecord] {
        struct Page: Decodable { let records: [ArrQueueRecord] }
        var query = [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "pageSize", value: "200")]
        if service == .radarr {
            query.append(URLQueryItem(name: "includeMovie", value: "true"))
        } else {
            query.append(URLQueryItem(name: "includeSeries", value: "true"))
            query.append(URLQueryItem(name: "includeEpisode", value: "true"))
        }
        return try await http.get(Page.self, "api/v3/queue", query: query).records
    }

    /// Asks Radarr or Sonarr to re-read its download clients now. Left alone
    /// they do it about once a minute, so a faster poll would read the same
    /// queue sizes over and over. The command runs in the background.
    func refreshDownloads() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": "RefreshMonitoredDownloads"])
        _ = try await http.send("api/v3/command", method: "POST", body: body)
    }

    private struct LibraryItem: Decodable {
        let id: Int
        let tmdbId: Int?
        let tvdbId: Int?
    }

    private func libraryID(tmdbID: Int, tvdbID: Int?) async throws -> Int? {
        if service == .radarr {
            let movies = try await http.get([LibraryItem].self, "api/v3/movie",
                                            query: [URLQueryItem(name: "tmdbId", value: String(tmdbID))])
            return movies.first?.id
        }
        if let tvdbID {
            let series = try await http.get([LibraryItem].self, "api/v3/series",
                                            query: [URLQueryItem(name: "tvdbId", value: String(tvdbID))])
            if let match = series.first { return match.id }
        }
        // No TVDB id to ask with: Sonarr v4 stores the TMDB id on each series.
        let all = try await http.get([LibraryItem].self, "api/v3/series")
        return all.first { $0.tmdbId == tmdbID || (tvdbID != nil && $0.tvdbId == tvdbID) }?.id
    }
}
