// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  MediaRequestStatusResolver.swift
//  Rivulet
//
//  One answer to "can this title be requested, and how far along is it?",
//  merged from Seerr (request state) and Radarr / Sonarr (download progress).
//  Without Radarr / Sonarr configured, Seerr's own download status stands in.
//

import Foundation

nonisolated enum MediaRequestState: Equatable, Sendable {
    case requestable
    case pendingApproval
    case processing
    case downloading(DownloadProgress)
    case partiallyAvailable
    case available
    case blocklisted

    /// Picks the state to show. Download progress outranks everything, since
    /// it is the most specific thing to say; nil means no button at all.
    static func resolve(seerrStatus: SeerrMediaStatus?, hasPendingRequest: Bool,
                        canRequestMore: Bool, download: DownloadProgress?) -> MediaRequestState? {
        if let download { return .downloading(download) }
        guard let seerrStatus else { return nil }
        switch seerrStatus {
        case .blocklisted: return .blocklisted
        case .available: return .available
        default: break
        }
        if canRequestMore { return .requestable }
        if hasPendingRequest { return .pendingApproval }
        switch seerrStatus {
        case .partiallyAvailable: return .partiallyAvailable
        case .processing, .pending: return .processing
        case .unknown, .deleted: return .requestable
        case .available, .blocklisted: return nil
        }
    }

    var title: String {
        switch self {
        case .requestable: return "Request"
        case .pendingApproval: return "Requested"
        case .processing: return "Processing"
        case .downloading(let progress): return "Downloading \(progress.percentText)"
        case .partiallyAvailable: return "Partly Available"
        case .available: return "Available"
        case .blocklisted: return "Blocklisted"
        }
    }

    var systemImage: String {
        switch self {
        case .requestable: return "plus.circle"
        case .pendingApproval: return "clock"
        case .processing: return "hourglass"
        case .downloading: return "arrow.down.circle"
        case .partiallyAvailable: return "circle.lefthalf.filled"
        case .available: return "checkmark.circle"
        case .blocklisted: return "nosign"
        }
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

nonisolated struct MediaRequestSnapshot: Sendable {
    let state: MediaRequestState
    let requestableSeasons: [SeerrMediaDetail.Season]
    let tvdbID: Int?
}

@MainActor
final class MediaRequestStatusResolver {
    static let shared = MediaRequestStatusResolver()

    private var cache: [String: (snapshot: MediaRequestSnapshot?, at: Date)] = [:]
    private static let cacheLifetime: TimeInterval = 10

    /// True when the detail page should ask at all.
    var isEnabled: Bool {
        IntegrationService.allCases.contains { IntegrationStore.isConfigured($0) }
    }

    func invalidate() { cache.removeAll() }

    func snapshot(tmdbID: Int, type: SeerrMediaType, refresh: Bool = false) async -> MediaRequestSnapshot? {
        let key = "\(type.rawValue):\(tmdbID)"
        if !refresh, let cached = cache[key], Date().timeIntervalSince(cached.at) < Self.cacheLifetime {
            return cached.snapshot
        }
        let seerrConfig = IntegrationStore.config(for: .seerr)
        let arrService: IntegrationService = type == .movie ? .radarr : .sonarr
        let arrConfig = IntegrationStore.config(for: arrService)

        let detail: SeerrMediaDetail? = seerrConfig.isConfigured
            ? try? await SeerrClient(config: seerrConfig).detail(tmdbID: tmdbID, type: type)
            : nil
        let tvdbID = detail?.externalIds?.tvdbId

        var download: DownloadProgress?
        if arrConfig.isConfigured {
            download = try? await ArrClient(service: arrService, config: arrConfig)
                .progress(tmdbID: tmdbID, tvdbID: tvdbID)
        } else if let statuses = detail?.mediaInfo?.downloadStatus {
            download = DownloadProgress(sizes: statuses.map { ($0.size ?? 0, $0.sizeLeft ?? 0) })
        }

        let requestable = detail?.requestableSeasons ?? []
        let canRequestMore: Bool = {
            guard let detail else { return false }
            if type == .tv { return !requestable.isEmpty }
            return (detail.status == .unknown || detail.status == .deleted) && !detail.hasPendingRequest
        }()
        let snapshot = MediaRequestState.resolve(
            seerrStatus: detail?.status, hasPendingRequest: detail?.hasPendingRequest ?? false,
            canRequestMore: canRequestMore, download: download
        ).map { MediaRequestSnapshot(state: $0, requestableSeasons: requestable, tvdbID: tvdbID) }
        cache[key] = (snapshot, Date())
        return snapshot
    }

    func request(tmdbID: Int, type: SeerrMediaType, seasons: [Int], tvdbID: Int?) async throws {
        let config = IntegrationStore.config(for: .seerr)
        try await SeerrClient(config: config).request(tmdbID: tmdbID, type: type, seasons: seasons, tvdbID: tvdbID)
        cache.removeValue(forKey: "\(type.rawValue):\(tmdbID)")
    }
}
