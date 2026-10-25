// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  RequestsFeed.swift
//  Rivulet
//
//  What the Requests page shows: the Radarr / Sonarr download queue grouped
//  per title, Seerr requests still waiting, and requests now available.
//  Without Radarr or Sonarr, Seerr's own download status stands in for that
//  app's downloads.
//

import Foundation

/// One title on the Requests page.
nonisolated struct RequestTile: Hashable, Sendable {
    let id: String
    let type: SeerrMediaType
    var tmdbID: Int?
    var title: String
    /// The line under the title: a year, the episodes downloading, or who asked.
    var detail: String?
    var status: String
    /// Download progress, 0...1, when something is downloading.
    var progress: Double?
    /// "1.2 GB of 4.5 GB" while downloading.
    var sizeText: String?
    /// Seconds until the download finishes, as the download client estimates it.
    var secondsLeft: Int?
    /// The title is in the library: the request belongs to History.
    var isAvailable = false
    /// Where Seerr says the library copy is.
    var plexRatingKey: String?
    var jellyfinItemID: String?
    var posterURL: URL?
    var posterPath: String?
    var backdropPath: String?
    var overview: String?
    var releaseDate: String?
    var voteAverage: Double?

    static func key(_ type: SeerrMediaType, _ tmdbID: Int) -> String { "\(type.rawValue):\(tmdbID)" }
}

/// The pure part: queue entries and requests in, tiles out.
nonisolated enum RequestTiles {
    static let posterBase = "https://image.tmdb.org/t/p/w500"

    /// One tile per movie or series, in queue order.
    static func downloads(_ records: [ArrQueueRecord], type: SeerrMediaType,
                          tmdbForTVDB: [Int: Int] = [:]) -> [RequestTile] {
        var order: [Int] = []
        var groups: [Int: [ArrQueueRecord]] = [:]
        for record in records {
            guard let id = type == .movie ? record.movieId : record.seriesId else { continue }
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(record)
        }
        return order.compactMap { id in
            guard let group = groups[id], let first = group.first else { return nil }
            let info = type == .movie ? first.movie : first.series
            let tmdbID = info?.tmdbId.flatMap { $0 > 0 ? $0 : nil }
                ?? info?.tvdbId.flatMap { tmdbForTVDB[$0] }
            let sizes = group.map { ($0.size ?? 0, $0.sizeleft ?? 0) }
            let progress = DownloadProgress(sizes: sizes)
            let paused = group.allSatisfy { $0.status?.lowercased() == "paused" }
            return RequestTile(
                id: tmdbID.map { RequestTile.key(type, $0) } ?? "\(type.rawValue)-arr:\(id)",
                type: type,
                tmdbID: tmdbID,
                title: info?.title ?? "Unknown",
                detail: type == .movie ? info?.year.map(String.init) : episodesText(group),
                status: downloadStatus(group),
                progress: progress?.fraction,
                sizeText: sizeText(sizes),
                secondsLeft: paused ? nil : group.compactMap { $0.timeleft.flatMap(seconds(timeSpan:)) }.max(),
                posterURL: info?.posterURL)
        }
    }

    static func downloadStatus(_ records: [ArrQueueRecord]) -> String {
        let states = Set(records.compactMap { $0.status?.lowercased() })
        let tracked = Set(records.compactMap { $0.trackedDownloadState?.lowercased() })
        if !tracked.isEmpty, tracked.isSubset(of: ["importpending", "importing", "imported"]) { return "Importing" }
        if !states.isEmpty, states == ["paused"] { return "Paused" }
        if !states.isEmpty, states.isSubset(of: ["queued", "delay"]) { return "Queued" }
        if states.contains("warning") || states.contains("failed") { return "Stalled" }
        return "Downloading"
    }

    /// "1.2 GB of 4.5 GB"; nil when no size is known.
    static func sizeText(_ sizes: [(size: Double, left: Double)]) -> String? {
        let known = sizes.filter { $0.size > 0 }
        guard !known.isEmpty else { return nil }
        let total = known.reduce(0) { $0 + $1.size }
        let done = known.reduce(0) { $0 + $1.size - min(max($1.left, 0), $1.size) }
        let format = ByteCountFormatter()
        format.countStyle = .file
        return "\(format.string(fromByteCount: Int64(done))) of \(format.string(fromByteCount: Int64(total)))"
    }

    /// Reads a .NET TimeSpan: "hh:mm:ss" or "d.hh:mm:ss", fractions ignored.
    static func seconds(timeSpan: String) -> Int? {
        let parts = timeSpan.split(separator: ":")
        guard parts.count == 3 else { return nil }
        var days = 0
        var hourPart = parts[0]
        if let dot = hourPart.firstIndex(of: ".") {
            guard let value = Int(hourPart[..<dot]) else { return nil }
            days = value
            hourPart = hourPart[hourPart.index(after: dot)...]
        }
        guard let hours = Int(hourPart), let minutes = Int(parts[1]),
              let secs = Int(parts[2].split(separator: ".").first ?? "") else { return nil }
        return ((days * 24 + hours) * 60 + minutes) * 60 + secs
    }

    /// "12 min left", "1 hr, 5 min left".
    static func timeLeftText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "Less than a minute left" }
        let format = DateComponentsFormatter()
        format.allowedUnits = [.day, .hour, .minute]
        format.unitsStyle = .short
        format.maximumUnitCount = 2
        return format.string(from: TimeInterval(seconds)).map { "\($0) left" } ?? ""
    }

    static func episodesText(_ records: [ArrQueueRecord]) -> String? {
        let episodes = records.compactMap(\.episode)
        guard !episodes.isEmpty else { return nil }
        if episodes.count == 1, let season = episodes[0].seasonNumber, let number = episodes[0].episodeNumber {
            return "S\(season), E\(number)"
        }
        let seasons = Set(episodes.compactMap(\.seasonNumber))
        if seasons.count == 1, let season = seasons.first {
            return "Season \(season), \(episodes.count) episodes"
        }
        return "\(episodes.count) episodes"
    }

    /// One tile per title, newest request first. Seerr lists a title once per
    /// request, so a show asked for season by season would repeat. Declined
    /// requests are left out.
    static func requests(_ requests: [SeerrRequest]) -> [RequestTile] {
        var seen = Set<String>()
        return requests.compactMap { request in
            guard let type = request.mediaType, let tmdbID = request.media?.tmdbId,
                  request.status != SeerrRequestStatus.declined.rawValue else { return nil }
            let key = RequestTile.key(type, tmdbID)
            guard seen.insert(key).inserted else { return nil }
            let sizes = (request.media?.downloadStatus ?? []).map { ($0.size ?? 0, $0.sizeLeft ?? 0) }
            let progress = DownloadProgress(sizes: sizes)
            let mediaStatus = request.media?.status.flatMap(SeerrMediaStatus.init(rawValue:))
            return RequestTile(
                id: key, type: type, tmdbID: tmdbID, title: "",
                detail: request.requestedBy?.displayName.map { "Requested by \($0)" },
                status: requestStatus(request),
                progress: progress?.fraction,
                sizeText: progress == nil ? nil : sizeText(sizes),
                isAvailable: mediaStatus == .available || mediaStatus == .partiallyAvailable,
                plexRatingKey: request.media?.ratingKey,
                jellyfinItemID: request.media?.jellyfinMediaId)
        }
    }

    static func requestStatus(_ request: SeerrRequest) -> String {
        switch request.status.flatMap(SeerrRequestStatus.init(rawValue:)) {
        case .pending: return "Pending Approval"
        case .declined: return "Declined"
        case .failed: return "Failed"
        default: break
        }
        switch request.media?.status.flatMap(SeerrMediaStatus.init(rawValue:)) {
        case .available: return "Available"
        case .partiallyAvailable: return "Partly Available"
        case .blocklisted: return "Blocklisted"
        default:
            if request.media?.downloadStatus?.isEmpty == false { return "Downloading" }
            return request.status == SeerrRequestStatus.approved.rawValue ? "Approved" : "Processing"
        }
    }

    /// Titles a download app is not set up for, downloading as far as Seerr knows.
    static func seerrDownloads(_ requests: [SeerrRequest], skipping: Set<SeerrMediaType>) -> [RequestTile] {
        Self.requests(requests).filter { $0.progress != nil && !skipping.contains($0.type) }.map {
            var tile = $0
            tile.detail = nil
            tile.status = "Downloading"
            return tile
        }
    }

    /// Splits requests into those still waiting and those now available.
    /// A title already in the download list shows there, not as waiting.
    static func sections(requests: [RequestTile], downloading: [RequestTile])
        -> (waiting: [RequestTile], history: [RequestTile]) {
        let busy = Set(downloading.map(\.id))
        return (requests.filter { !$0.isAvailable && !busy.contains($0.id) },
                requests.filter(\.isAvailable))
    }

    /// Fills a tile's title and artwork from the title's Seerr detail.
    static func applying(_ detail: SeerrMediaDetail, to tile: RequestTile) -> RequestTile {
        var tile = tile
        if let title = detail.title ?? detail.name, !title.isEmpty { tile.title = title }
        if let path = detail.posterPath {
            tile.posterPath = path
            tile.posterURL = URL(string: posterBase + path)
        }
        tile.backdropPath = detail.backdropPath
        tile.overview = detail.overview
        tile.releaseDate = detail.releaseDate ?? detail.firstAirDate
        tile.voteAverage = detail.voteAverage
        return tile
    }
}

/// Loads the page's three sections. Main actor: the page reads it directly.
@MainActor
final class RequestsFeed {
    private(set) var downloads: [RequestTile] = []
    /// Requested, not downloading and not yet available.
    private(set) var requests: [RequestTile] = []
    /// Requested and now available.
    private(set) var history: [RequestTile] = []
    private(set) var hasLoaded = false
    /// Set when every configured service failed to answer.
    private(set) var failure: String?

    private var seerrRequests: [SeerrRequest] = []
    private var details: [String: SeerrMediaDetail] = [:]
    private var lastRefreshCommand: Date?
    private static let refreshCommandInterval: TimeInterval = 10

    /// Reads the queues and, with `includeRequests`, Seerr's request list.
    func load(includeRequests: Bool) async {
        let seerr = IntegrationStore.config(for: .seerr)
        let radarr = IntegrationStore.config(for: .radarr)
        let sonarr = IntegrationStore.config(for: .sonarr)
        nudgeDownloadClients(radarr: radarr, sonarr: sonarr)

        async let radarrQueue = Self.queue(.radarr, radarr)
        async let sonarrQueue = Self.queue(.sonarr, sonarr)
        var errors: [String] = []
        var answered = false

        if seerr.isConfigured, includeRequests || !hasLoaded {
            do {
                seerrRequests = try await SeerrClient(config: seerr).requests()
                answered = true
            } catch {
                errors.append("Seerr: \(error.localizedDescription)")
            }
        } else if seerr.isConfigured {
            answered = true
        }

        let radarrResult = await radarrQueue
        let sonarrResult = await sonarrQueue
        for result in [radarrResult, sonarrResult] {
            switch result {
            case .success(let records): if records != nil { answered = true }
            case .failure(let error): errors.append(error.localizedDescription)
            }
        }

        let tmdbForTVDB = Dictionary(seerrRequests.compactMap { request -> (Int, Int)? in
            guard let tvdb = request.media?.tvdbId, let tmdb = request.media?.tmdbId else { return nil }
            return (tvdb, tmdb)
        }, uniquingKeysWith: { first, _ in first })

        var nextDownloads = RequestTiles.downloads((try? radarrResult.get()) ?? [], type: .movie)
            + RequestTiles.downloads((try? sonarrResult.get()) ?? [], type: .tv, tmdbForTVDB: tmdbForTVDB)
        var skipping = Set<SeerrMediaType>()
        if radarr.isConfigured { skipping.insert(.movie) }
        if sonarr.isConfigured { skipping.insert(.tv) }
        nextDownloads += RequestTiles.seerrDownloads(seerrRequests, skipping: skipping)
        var nextRequests = RequestTiles.requests(seerrRequests)

        if seerr.isConfigured {
            await fetchDetails(for: nextRequests + nextDownloads, config: seerr)
        }
        nextRequests = nextRequests.map(withDetail)
        nextDownloads = nextDownloads.map(withDetail)

        let split = RequestTiles.sections(requests: nextRequests.filter { !$0.title.isEmpty },
                                          downloading: nextDownloads)
        downloads = nextDownloads
        requests = split.waiting
        history = split.history
        failure = answered || errors.isEmpty ? nil : errors.joined(separator: "\n")
        hasLoaded = true
    }

    private func withDetail(_ tile: RequestTile) -> RequestTile {
        guard let detail = details[tile.id] else { return tile }
        var filled = RequestTiles.applying(detail, to: tile)
        // The download app's poster stays when Seerr has none.
        if filled.posterURL == nil { filled.posterURL = tile.posterURL }
        return filled
    }

    private func fetchDetails(for tiles: [RequestTile], config: IntegrationConfig) async {
        let missing = Dictionary(tiles.compactMap { tile -> (String, (Int, SeerrMediaType))? in
            guard details[tile.id] == nil, let tmdbID = tile.tmdbID else { return nil }
            return (tile.id, (tmdbID, tile.type))
        }, uniquingKeysWith: { first, _ in first })
        guard !missing.isEmpty else { return }
        let client = SeerrClient(config: config)
        let fetched = await withTaskGroup(of: (String, SeerrMediaDetail?).self) { group in
            for (key, value) in missing {
                group.addTask { (key, try? await client.detail(tmdbID: value.0, type: value.1)) }
            }
            var results: [String: SeerrMediaDetail] = [:]
            for await (key, detail) in group { if let detail { results[key] = detail } }
            return results
        }
        details.merge(fetched) { _, new in new }
    }

    /// nil when the app is not set up.
    private nonisolated static func queue(_ service: IntegrationService,
                                          _ config: IntegrationConfig) async -> Result<[ArrQueueRecord]?, Error> {
        guard config.isConfigured else { return .success(nil) }
        do {
            return .success(try await ArrClient(service: service, config: config).queue())
        } catch {
            return .failure(QueueError(message: "\(service.displayName): \(error.localizedDescription)"))
        }
    }

    private struct QueueError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Left alone, Radarr and Sonarr re-read their download clients about once
    /// a minute, so the page asks for it while it is open.
    private func nudgeDownloadClients(radarr: IntegrationConfig, sonarr: IntegrationConfig) {
        if let last = lastRefreshCommand, Date().timeIntervalSince(last) < Self.refreshCommandInterval { return }
        lastRefreshCommand = Date()
        for (service, config) in [(IntegrationService.radarr, radarr), (.sonarr, sonarr)] where config.isConfigured {
            Task.detached { try? await ArrClient(service: service, config: config).refreshDownloads() }
        }
    }
}
