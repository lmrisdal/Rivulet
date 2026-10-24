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
