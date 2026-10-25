// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import Rivulet

final class IntegrationHeaderTests: XCTestCase {
    func test_parse_splitsOnFirstColonOnly() {
        let header = IntegrationHeader.parse("Authorization: Basic abc:def")
        XCTAssertEqual(header, IntegrationHeader(name: "Authorization", value: "Basic abc:def"))
    }

    func test_parse_trimsWhitespace() {
        XCTAssertEqual(IntegrationHeader.parse("  CF-Access-Client-Id :  abc123 "),
                       IntegrationHeader(name: "CF-Access-Client-Id", value: "abc123"))
    }

    func test_parse_rejectsMissingPartsAndBadNames() {
        XCTAssertNil(IntegrationHeader.parse("NoColon"))
        XCTAssertNil(IntegrationHeader.parse(": value"))
        XCTAssertNil(IntegrationHeader.parse("Name:"))
        XCTAssertNil(IntegrationHeader.parse("Bad Name: value"))
        XCTAssertNil(IntegrationHeader.parse("Bäd: value"))
    }
}

final class IntegrationConfigTests: XCTestCase {
    func test_normalizedBaseURL_stripsTrailingSlashesAndKeepsPath() {
        let config = IntegrationConfig(baseURL: " https://example.com/seerr// ")
        XCTAssertEqual(config.normalizedBaseURL?.absoluteString, "https://example.com/seerr")
    }

    func test_normalizedBaseURL_requiresHTTPSchemeAndHost() {
        XCTAssertNil(IntegrationConfig(baseURL: "example.com").normalizedBaseURL)
        XCTAssertNil(IntegrationConfig(baseURL: "ftp://example.com").normalizedBaseURL)
        XCTAssertNil(IntegrationConfig(baseURL: "").normalizedBaseURL)
        XCTAssertNotNil(IntegrationConfig(baseURL: "http://192.168.1.10:5055").normalizedBaseURL)
    }

    func test_isConfigured_needsURLAndKey() {
        XCTAssertFalse(IntegrationConfig(baseURL: "https://a.com").isConfigured)
        XCTAssertTrue(IntegrationConfig(baseURL: "https://a.com", apiKey: "k").isConfigured)
    }

    func test_request_sendsApiKeyAndCustomHeaders() throws {
        let config = IntegrationConfig(baseURL: "https://example.com/radarr/", apiKey: "secret",
                                       headers: [IntegrationHeader(name: "CF-Access-Client-Id", value: "abc")])
        let request = try IntegrationHTTPClient(config: config)
            .request("api/v3/movie", query: [URLQueryItem(name: "tmdbId", value: "603")])
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/radarr/api/v3/movie?tmdbId=603")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "abc")
    }

    func test_request_throwsWhenNotConfigured() {
        XCTAssertThrowsError(try IntegrationHTTPClient(config: IntegrationConfig()).request("x"))
    }
}

final class DownloadProgressTests: XCTestCase {
    func test_combinesQueueItems() throws {
        let progress = try XCTUnwrap(DownloadProgress(sizes: [(size: 100, left: 50), (size: 300, left: 50)]))
        XCTAssertEqual(progress.fraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(progress.downloads, 2)
        XCTAssertEqual(progress.percentText, "75%")
    }

    func test_nilWithoutKnownSizes() {
        XCTAssertNil(DownloadProgress(sizes: []))
        XCTAssertNil(DownloadProgress(sizes: [(size: 0, left: 0)]))
    }

    func test_clampsBadSizeLeft() throws {
        let progress = try XCTUnwrap(DownloadProgress(sizes: [(size: 100, left: 200)]))
        XCTAssertEqual(progress.fraction, 0)
    }
}

final class MediaRequestStateTests: XCTestCase {
    func test_finishedDownload_readsAsProcessing() throws {
        let done = try XCTUnwrap(DownloadProgress(sizes: [(size: 10, left: 0)]))
        let partial = try XCTUnwrap(DownloadProgress(sizes: [(size: 10, left: 1)]))
        XCTAssertEqual(MediaRequestState.downloading(done).title, "Processing Download")
        XCTAssertEqual(MediaRequestState.downloading(partial).title, "Downloading 90%")
    }

    func test_downloadWins() throws {
        let progress = try XCTUnwrap(DownloadProgress(sizes: [(size: 10, left: 5)]))
        XCTAssertEqual(MediaRequestState.resolve(seerrStatus: nil, hasPendingRequest: false,
                                                 canRequestMore: false, download: progress),
                       .downloading(progress))
    }

    func test_noSeerrNoDownload_isNil() {
        XCTAssertNil(MediaRequestState.resolve(seerrStatus: nil, hasPendingRequest: false,
                                               canRequestMore: false, download: nil))
    }

    func test_statuses() {
        func state(_ status: SeerrMediaStatus, pending: Bool = false, more: Bool = false) -> MediaRequestState? {
            MediaRequestState.resolve(seerrStatus: status, hasPendingRequest: pending,
                                      canRequestMore: more, download: nil)
        }
        XCTAssertEqual(state(.unknown), .requestable)
        XCTAssertEqual(state(.deleted), .requestable)
        XCTAssertEqual(state(.available), .available)
        XCTAssertEqual(state(.blocklisted), .blocklisted)
        XCTAssertEqual(state(.pending, pending: true), .pendingApproval)
        XCTAssertEqual(state(.processing), .processing)
        XCTAssertEqual(state(.partiallyAvailable), .partiallyAvailable)
        XCTAssertEqual(state(.partiallyAvailable, more: true), .requestable)
    }
}

final class SeerrMediaDetailTests: XCTestCase {
    func test_requestableSeasons_skipsSpecialsAvailableAndRequested() throws {
        let json = """
        {
          "id": 1399,
          "externalIds": { "tvdbId": 121361 },
          "seasons": [
            { "seasonNumber": 0, "name": "Specials" },
            { "seasonNumber": 1, "name": "Season 1" },
            { "seasonNumber": 2, "name": "Season 2" },
            { "seasonNumber": 3, "name": "Season 3" },
            { "seasonNumber": 4, "name": "Season 4" }
          ],
          "mediaInfo": {
            "status": 4,
            "seasons": [ { "seasonNumber": 1, "status": 5 }, { "seasonNumber": 4, "status": 1 } ],
            "requests": [
              { "status": 1, "is4k": false, "seasons": [ { "seasonNumber": 2 } ] },
              { "status": 3, "is4k": false, "seasons": [ { "seasonNumber": 3 } ] }
            ]
          }
        }
        """
        let detail = try JSONDecoder().decode(SeerrMediaDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.status, .partiallyAvailable)
        XCTAssertTrue(detail.hasPendingRequest)
        XCTAssertEqual(detail.externalIds?.tvdbId, 121361)
        XCTAssertEqual(detail.requestableSeasons.map(\.seasonNumber), [3, 4])
    }

    func test_movieWithoutMediaInfo_isUnknown() throws {
        let detail = try JSONDecoder().decode(SeerrMediaDetail.self, from: Data(#"{"id": 603}"#.utf8))
        XCTAssertEqual(detail.status, .unknown)
        XCTAssertFalse(detail.hasPendingRequest)
    }
}

final class LibraryArrivalFinderTests: XCTestCase {
    private func item(_ id: String, kind: MediaKind, title: String, year: Int? = nil,
                      seriesTitle: String? = nil, parent: String? = nil, grandparent: String? = nil) -> MediaItem {
        MediaItem(
            ref: MediaItemRef(providerID: "plex:x", itemID: id),
            kind: kind, title: title, sortTitle: nil, overview: nil, year: year, runtime: nil,
            parentRef: parent.map { MediaItemRef(providerID: "plex:x", itemID: $0) },
            grandparentRef: grandparent.map { MediaItemRef(providerID: "plex:x", itemID: $0) },
            seriesTitle: seriesTitle, episodeNumber: nil, seasonNumber: nil, childProgress: nil,
            userState: MediaUserState(isPlayed: false, viewOffset: 0, isFavorite: false, lastViewedAt: nil),
            artwork: MediaArtwork(poster: nil, backdrop: nil, thumbnail: nil, logo: nil),
            parentArtwork: nil, grandparentArtwork: nil)
    }

    func test_movie_matchesTitleAndYear() {
        let items = [
            item("1", kind: .movie, title: "Dune", year: 1984),
            item("2", kind: .movie, title: "Dune: Part Two", year: 2024),
            item("3", kind: .movie, title: "dune", year: 2021),
        ]
        let refs = LibraryArrivalFinder.candidateRefs(in: items, title: "Dune", year: 2021, kind: .movie)
        XCTAssertEqual(refs.map(\.itemID), ["3"])
    }

    func test_show_matchesThroughSeasonsAndEpisodes_once() {
        let items = [
            item("10", kind: .season, title: "Season 1", seriesTitle: "Severance", parent: "9"),
            item("11", kind: .episode, title: "Good News About Hell", seriesTitle: "Severance", grandparent: "9"),
            item("12", kind: .movie, title: "Severance"),
        ]
        let refs = LibraryArrivalFinder.candidateRefs(in: items, title: "Severance", year: nil, kind: .show)
        XCTAssertEqual(refs.map(\.itemID), ["9"])
    }

    func test_normalized_ignoresCasePunctuationAndAccents() {
        XCTAssertEqual(LibraryArrivalFinder.normalized("Amélie!"), LibraryArrivalFinder.normalized("amelie"))
    }
}

final class RequestTilesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func test_downloads_groupPerSeries_sumProgress_andMapTVDBToTMDB() throws {
        let records = try decode([ArrQueueRecord].self, """
        [{"seriesId": 7, "size": 100, "sizeleft": 50, "status": "downloading", "timeleft": "00:12:30",
          "series": {"title": "Severance", "tvdbId": 371980, "tmdbId": 0},
          "episode": {"seasonNumber": 2, "episodeNumber": 1}},
         {"seriesId": 7, "size": 100, "sizeleft": 0, "status": "downloading", "timeleft": "1.02:00:00",
          "series": {"title": "Severance", "tvdbId": 371980},
          "episode": {"seasonNumber": 2, "episodeNumber": 2}},
         {"seriesId": 9, "size": 10, "sizeleft": 10, "status": "queued",
          "series": {"title": "Other", "tmdbId": 5}}]
        """)
        let tiles = RequestTiles.downloads(records, type: .tv, tmdbForTVDB: [371980: 95396])

        XCTAssertEqual(tiles.map(\.id), ["tv:95396", "tv:5"])
        XCTAssertEqual(tiles[0].progress, 0.75)
        XCTAssertEqual(tiles[0].status, "Downloading")
        XCTAssertEqual(tiles[0].secondsLeft, 26 * 3600)
        XCTAssertNotNil(tiles[0].sizeText)
        XCTAssertEqual(tiles[0].detail, "Season 2, 2 episodes")
        XCTAssertEqual(tiles[1].status, "Queued")
    }

    func test_downloads_withoutTMDBID_cannotOpenDetail() throws {
        let records = try decode([ArrQueueRecord].self, """
        [{"movieId": 3, "size": 10, "sizeleft": 5, "movie": {"title": "Heat", "year": 1995}}]
        """)
        let tile = try XCTUnwrap(RequestTiles.downloads(records, type: .movie).first)
        XCTAssertNil(tile.tmdbID)
        XCTAssertEqual(tile.detail, "1995")
    }

    func test_requests_dedupePerTitle_andMapStatus() throws {
        let requests = try decode([SeerrRequest].self, """
        [{"id": 3, "status": 1, "type": "tv", "media": {"tmdbId": 10, "mediaType": "tv", "status": 2}},
         {"id": 2, "status": 2, "type": "tv", "media": {"tmdbId": 10, "mediaType": "tv", "status": 3}},
         {"id": 1, "status": 2, "type": "movie", "requestedBy": {"displayName": "Ann"},
          "media": {"tmdbId": 11, "mediaType": "movie", "status": 5}},
         {"id": 0, "status": 3, "type": "movie", "media": {"tmdbId": 12, "mediaType": "movie", "status": 1}}]
        """)
        let tiles = RequestTiles.requests(requests)

        XCTAssertEqual(tiles.map(\.id), ["tv:10", "movie:11"])
        XCTAssertEqual(tiles.map(\.status), ["Pending Approval", "Available"])
        XCTAssertEqual(tiles.map(\.isAvailable), [false, true])
        XCTAssertEqual(tiles[1].detail, "Requested by Ann")
    }

    func test_sections_splitWaitingFromHistory_andDropWaitingThatIsDownloading() {
        func tile(_ id: String, available: Bool) -> RequestTile {
            RequestTile(id: id, type: .movie, title: id, status: "", isAvailable: available)
        }
        let split = RequestTiles.sections(
            requests: [tile("a", available: false), tile("b", available: true), tile("c", available: false)],
            downloading: [tile("c", available: false)])
        XCTAssertEqual(split.waiting.map(\.id), ["a"])
        XCTAssertEqual(split.history.map(\.id), ["b"])
    }

    func test_seconds_readsDotNetTimeSpans() {
        XCTAssertEqual(RequestTiles.seconds(timeSpan: "00:01:05"), 65)
        XCTAssertEqual(RequestTiles.seconds(timeSpan: "2.03:00:00"), (2 * 24 + 3) * 3600)
        XCTAssertEqual(RequestTiles.seconds(timeSpan: "00:00:10.5000000"), 10)
        XCTAssertNil(RequestTiles.seconds(timeSpan: "soon"))
    }

    func test_seerrDownloads_skipTypesWithADownloadApp() throws {
        let requests = try decode([SeerrRequest].self, """
        [{"id": 1, "status": 2, "media": {"tmdbId": 1, "mediaType": "movie", "status": 3,
          "downloadStatus": [{"size": 4, "sizeLeft": 1}]}},
         {"id": 2, "status": 2, "media": {"tmdbId": 2, "mediaType": "tv", "status": 3,
          "downloadStatus": [{"size": 4, "sizeLeft": 3}]}}]
        """)
        let tiles = RequestTiles.seerrDownloads(requests, skipping: [.movie])
        XCTAssertEqual(tiles.map(\.id), ["tv:2"])
        XCTAssertEqual(tiles.first?.status, "Downloading")
        XCTAssertEqual(tiles.first?.progress, 0.25)
    }
}
