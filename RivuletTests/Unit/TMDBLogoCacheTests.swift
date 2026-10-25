// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  TMDBLogoCacheTests.swift
//  RivuletTests
//

import XCTest
@testable import Rivulet

final class TMDBLogoCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(TMDBMockURLProtocol.self)
        TMDBMockURLProtocol.responses = [:]
        TMDBMockURLProtocol.hitCounts = [:]
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TMDBLogoCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(TMDBMockURLProtocol.self)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Selection rule (pure)

    func testSelectionPrefersEnglish() {
        let response = TMDBImagesResponse(logos: [
            TMDBImageEntry.make(path: "/fr.png", lang: "fr", vote: 9),
            TMDBImageEntry.make(path: "/en.png", lang: "en", vote: 5),
            TMDBImageEntry.make(path: "/null.png", lang: nil, vote: 8)
        ])
        XCTAssertEqual(response.bestLogoPath, "/en.png")
    }

    func testSelectionFallsBackToNullLangWhenNoEnglish() {
        let response = TMDBImagesResponse(logos: [
            TMDBImageEntry.make(path: "/fr.png", lang: "fr", vote: 3),
            TMDBImageEntry.make(path: "/null.png", lang: nil, vote: 7)
        ])
        XCTAssertEqual(response.bestLogoPath, "/null.png")
    }

    func testSelectionFallsBackToAnyWhenNoEnglishOrNull() {
        let response = TMDBImagesResponse(logos: [
            TMDBImageEntry.make(path: "/fr.png", lang: "fr", vote: 2),
            TMDBImageEntry.make(path: "/de.png", lang: "de", vote: 4)
        ])
        XCTAssertEqual(response.bestLogoPath, "/de.png")
    }

    func testSelectionPicksHighestVoteWithinTier() {
        let response = TMDBImagesResponse(logos: [
            TMDBImageEntry.make(path: "/en-low.png", lang: "en", vote: 2),
            TMDBImageEntry.make(path: "/en-high.png", lang: "en", vote: 9),
            TMDBImageEntry.make(path: "/en-mid.png", lang: "en", vote: 5)
        ])
        XCTAssertEqual(response.bestLogoPath, "/en-high.png")
    }

    func testSelectionSkipsEntriesWithMissingPath() {
        let response = TMDBImagesResponse(logos: [
            TMDBImageEntry.make(path: nil, lang: "en", vote: 10),
            TMDBImageEntry.make(path: "", lang: "en", vote: 10),
            TMDBImageEntry.make(path: "/valid.png", lang: "en", vote: 3)
        ])
        XCTAssertEqual(response.bestLogoPath, "/valid.png")
    }

    func testSelectionReturnsNilForEmptyLogos() {
        let response = TMDBImagesResponse(logos: [])
        XCTAssertNil(response.bestLogoPath)
    }

    // MARK: - Cache behavior

    func testFetchResolvesLogoURL() async {
        stub(tmdbId: 42, type: .movie, body: """
        {"logos": [{"file_path": "/abc.png", "iso_639_1": "en", "vote_average": 8.0}]}
        """)

        let cache = TMDBLogoCache(session: makeMockSession(), directory: tempDir)
        let url = await cache.logoURL(tmdbId: 42, type: .movie)

        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w500/abc.png")
    }

    func testSecondCallHitsMemoryCache() async {
        stub(tmdbId: 42, type: .movie, body: """
        {"logos": [{"file_path": "/abc.png", "iso_639_1": "en", "vote_average": 8.0}]}
        """)

        let cache = TMDBLogoCache(session: makeMockSession(), directory: tempDir)
        _ = await cache.logoURL(tmdbId: 42, type: .movie)
        _ = await cache.logoURL(tmdbId: 42, type: .movie)

        XCTAssertEqual(TMDBMockURLProtocol.hitCounts["3/movie/42/images?"], 1)
    }

    func testNilResultIsCachedAndDoesNotRefetch() async {
        stub(tmdbId: 42, type: .tv, body: #"{"logos": []}"#)

        let cache = TMDBLogoCache(session: makeMockSession(), directory: tempDir)
        let first = await cache.logoURL(tmdbId: 42, type: .tv)
        let second = await cache.logoURL(tmdbId: 42, type: .tv)

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(TMDBMockURLProtocol.hitCounts["3/tv/42/images?"], 1)
    }

    func testInflightDedupMergesConcurrentCalls() async {
        stub(tmdbId: 42, type: .movie, body: """
        {"logos": [{"file_path": "/abc.png", "iso_639_1": "en", "vote_average": 8.0}]}
        """)

        let cache = TMDBLogoCache(session: makeMockSession(), directory: tempDir)

        async let a = cache.logoURL(tmdbId: 42, type: .movie)
        async let b = cache.logoURL(tmdbId: 42, type: .movie)
        async let c = cache.logoURL(tmdbId: 42, type: .movie)
        let results = await [a, b, c]

        XCTAssertTrue(results.allSatisfy { $0 != nil })
        XCTAssertEqual(TMDBMockURLProtocol.hitCounts["3/movie/42/images?"], 1)
    }

    func testDiskRoundTripSurvivesNewInstance() async {
        stub(tmdbId: 42, type: .movie, body: """
        {"logos": [{"file_path": "/abc.png", "iso_639_1": "en", "vote_average": 8.0}]}
        """)

        let cache1 = TMDBLogoCache(session: makeMockSession(), directory: tempDir)
        _ = await cache1.logoURL(tmdbId: 42, type: .movie)

        // New instance (cold memory); should read from disk, not network.
        let cache2 = TMDBLogoCache(session: makeMockSession(), directory: tempDir)
        let url = await cache2.logoURL(tmdbId: 42, type: .movie)

        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w500/abc.png")
        XCTAssertEqual(TMDBMockURLProtocol.hitCounts["3/movie/42/images?"], 1)
    }

    func testNetworkFailureDoesNotPoisonCache() async {
        TMDBMockURLProtocol.responses["3/movie/42/images?"] = (500, Data())

        let cache = TMDBLogoCache(session: makeMockSession(), directory: tempDir)
        let first = await cache.logoURL(tmdbId: 42, type: .movie)
        XCTAssertNil(first)

        // Now the response succeeds; a second call should retry and succeed,
        // proving the failure did not persist to disk or block memory.
        stub(tmdbId: 42, type: .movie, body: """
        {"logos": [{"file_path": "/abc.png", "iso_639_1": "en", "vote_average": 8.0}]}
        """)
        let second = await cache.logoURL(tmdbId: 42, type: .movie)
        XCTAssertEqual(second?.absoluteString, "https://image.tmdb.org/t/p/w500/abc.png")
    }

    // MARK: - Helpers

    private func stub(tmdbId: Int, type: TMDBMediaType, body: String) {
        let key = "3/\(type.rawValue)/\(tmdbId)/images?"
        TMDBMockURLProtocol.responses[key] = (200, body.data(using: .utf8)!)
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TMDBMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private extension TMDBImageEntry {
    static func make(path: String?, lang: String?, vote: Double) -> TMDBImageEntry {
        var json: [String: Any] = ["vote_average": vote]
        if let path { json["file_path"] = path }
        if let lang { json["iso_639_1"] = lang }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(TMDBImageEntry.self, from: data)
    }
}
