// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  TMDBDiscoverServiceTests.swift
//  RivuletTests

import XCTest
@testable import Rivulet

final class TMDBDiscoverServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(TMDBMockURLProtocol.self)
        TMDBMockURLProtocol.responses = [:]
        // Clear any stale disk caches from previous runs
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        for sub in ["TMDBDiscoverDetailCacheDirect", "TMDBDiscoverListCache"] {
            try? FileManager.default.removeItem(at: cachesDir.appendingPathComponent(sub, isDirectory: true))
        }
    }

    override func tearDown() {
        URLProtocol.unregisterClass(TMDBMockURLProtocol.self)
        super.tearDown()
    }

    func testFetchSectionDecodesPopularMovies() async {
        let json = """
        {
          "results": [
            {"id": 100, "title": "Test Movie", "poster_path": "/p.jpg", "backdrop_path": "/b.jpg", "release_date": "2024-01-01", "vote_average": 7.5, "overview": "..."}
          ]
        }
        """.data(using: .utf8)!

        TMDBMockURLProtocol.responses["3/movie/popular?"] = (200, json)

        let service = TMDBDiscoverService(session: makeMockSession())
        let items = await service.fetchSection(.moviePopular)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, 100)
        XCTAssertEqual(items.first?.title, "Test Movie")
        XCTAssertEqual(items.first?.mediaType, .movie)
    }

    func testFetchSectionUsesTVTitleField() async {
        let json = """
        {
          "results": [
            {"id": 200, "name": "Test Show", "poster_path": "/p.jpg", "first_air_date": "2024-01-01"}
          ]
        }
        """.data(using: .utf8)!

        TMDBMockURLProtocol.responses["3/tv/popular?"] = (200, json)

        let service = TMDBDiscoverService(session: makeMockSession())
        let items = await service.fetchSection(.tvPopular)

        XCTAssertEqual(items.first?.title, "Test Show")
        XCTAssertEqual(items.first?.releaseDate, "2024-01-01")
        XCTAssertEqual(items.first?.mediaType, .tv)
    }

    func testFetchSectionReturnsEmptyOnFailure() async {
        TMDBMockURLProtocol.responses["3/movie/popular?"] = (500, Data())
        let service = TMDBDiscoverService(session: makeMockSession())
        let items = await service.fetchSection(.moviePopular)
        XCTAssertTrue(items.isEmpty)
    }

    func testFetchSectionUsesInMemoryCache() async {
        let json = """
        {"results": [{"id": 1, "title": "A"}]}
        """.data(using: .utf8)!
        TMDBMockURLProtocol.responses["3/movie/popular?"] = (200, json)

        let service = TMDBDiscoverService(session: makeMockSession())
        _ = await service.fetchSection(.moviePopular)

        // Second call: blank out the response. Cache should serve.
        TMDBMockURLProtocol.responses["3/movie/popular?"] = (500, Data())
        let second = await service.fetchSection(.moviePopular)
        XCTAssertEqual(second.first?.id, 1)
    }

    func testFetchDetailStampsTVMediaType() async {
        let json = """
        {"id": 300, "name": "Test Show", "overview": "A television series.",
         "episode_run_time": [47], "genres": [{"id":18,"name":"Drama"}],
         "credits": {"cast": [{"id":1,"name":"Example Actor"}]}}
        """.data(using: .utf8)!
        TMDBMockURLProtocol.responses["3/tv/300?append_to_response=credits"] = (200, json)

        let service = TMDBDiscoverService(session: makeMockSession())
        let detail = await service.fetchDetail(tmdbId: 300, type: .tv)

        XCTAssertEqual(detail?.mediaType, .tv)
        XCTAssertEqual(detail?.title, "Test Show")
        XCTAssertEqual(detail?.overview, "A television series.")
        XCTAssertEqual(detail?.runtime, 47)
        XCTAssertEqual(detail?.cast.first?.name, "Example Actor")
        XCTAssertEqual(detail?.genres.first?.name, "Drama")
    }

    func testFetchDetailReturnsNilOnFailure() async {
        TMDBMockURLProtocol.responses["3/movie/1?append_to_response=credits"] = (404, Data())
        let service = TMDBDiscoverService(session: makeMockSession())
        let detail = await service.fetchDetail(tmdbId: 1, type: .movie)
        XCTAssertNil(detail)
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TMDBMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class TMDBMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var hitCounts: [String: Int] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = components.queryItems?.filter { $0.name != "api_key" }
        let key = "\(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))?\(components.percentEncodedQuery ?? "")"
        TMDBMockURLProtocol.hitCounts[key, default: 0] += 1
        let (status, data) = TMDBMockURLProtocol.responses[key] ?? (404, Data())
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
