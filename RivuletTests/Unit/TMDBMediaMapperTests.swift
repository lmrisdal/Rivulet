// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  TMDBMediaMapperTests.swift
//  RivuletTests
//

import XCTest
@testable import Rivulet

final class TMDBMediaMapperTests: XCTestCase {

    func testCatalogDetailsIncludeCreditsAndTrailersAndSurviveCacheRoundTrip() throws {
        let json = #"""
        {"id":42,"title":"Catalog Movie","credits":{
          "cast":[{"id":7,"name":"Actor","character":"Hero","profile_path":"/actor.jpg"}],
          "crew":[{"id":8,"name":"Director","job":"Director","department":"Directing"},
                  {"id":9,"name":"Writer","job":"Screenplay","department":"Writing"}]},
         "videos":{"results":[
          {"id":"trailer","key":"abc123","name":"Official Trailer","site":"YouTube","type":"Trailer"},
          {"id":"other","key":"xyz","name":"Clip","site":"YouTube","type":"Clip"}]}}
        """#
        let decoded = try JSONDecoder().decode(TMDBItemDetail.self, from: Data(json.utf8))
        let cached = try JSONDecoder().decode(TMDBItemDetail.self, from: JSONEncoder().encode(decoded))
        let detail = TMDBMediaMapper.detail(cached)
        XCTAssertEqual(detail.cast.first?.imageURL?.absoluteString, "https://image.tmdb.org/t/p/w185/actor.jpg")
        XCTAssertEqual(detail.cast.first?.titleTmdbId, 42)
        XCTAssertEqual(detail.directors.first?.name, "Director")
        XCTAssertEqual(detail.writers.first?.name, "Writer")
        XCTAssertEqual(detail.extras.count, 1)
        XCTAssertEqual(detail.extras.first?.playbackKey, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(cached.crew.count, 2)
        XCTAssertEqual(cached.videos.count, 2)
    }

    // MARK: - ItemID encoding

    func testEncodeItemIDIncludesTypeAndId() {
        XCTAssertEqual(TMDBMediaMapper.encodeItemID(tmdbId: 42, type: .movie), "movie:42")
        XCTAssertEqual(TMDBMediaMapper.encodeItemID(tmdbId: 100, type: .tv), "tv:100")
    }

    func testDecodeItemIDRoundTrip() {
        let encoded = TMDBMediaMapper.encodeItemID(tmdbId: 1234, type: .tv)
        let decoded = TMDBMediaMapper.decodeItemID(encoded)
        XCTAssertEqual(decoded?.tmdbId, 1234)
        XCTAssertEqual(decoded?.type, .tv)
    }

    func testDecodeItemIDDistinguishesMovieAndTV() {
        let movie = TMDBMediaMapper.decodeItemID("movie:100")
        let tv = TMDBMediaMapper.decodeItemID("tv:100")
        XCTAssertEqual(movie?.type, .movie)
        XCTAssertEqual(tv?.type, .tv)
        XCTAssertEqual(movie?.tmdbId, tv?.tmdbId)
    }

    func testDecodeItemIDRejectsBareNumeric() {
        // Strict decode — legacy bare-numeric format no longer valid, forces
        // callers to go through the mapper which always encodes with type.
        XCTAssertNil(TMDBMediaMapper.decodeItemID("603"))
    }

    func testDecodeItemIDRejectsUnknownType() {
        XCTAssertNil(TMDBMediaMapper.decodeItemID("person:42"))
        XCTAssertNil(TMDBMediaMapper.decodeItemID("foo:42"))
    }

    func testDecodeItemIDRejectsGarbage() {
        XCTAssertNil(TMDBMediaMapper.decodeItemID(""))
        XCTAssertNil(TMDBMediaMapper.decodeItemID("movie:"))
        XCTAssertNil(TMDBMediaMapper.decodeItemID(":42"))
        XCTAssertNil(TMDBMediaMapper.decodeItemID("movie:abc"))
    }

    // MARK: - Mapper produces encoded refs

    func testMapperUsesEncodedItemIDForTVItem() {
        let tv = TMDBListItem(
            id: 777,
            title: "Some Show",
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            releaseDate: nil,
            voteAverage: nil,
            mediaType: .tv
        )
        let item = TMDBMediaMapper.item(tv)
        XCTAssertEqual(item.ref.itemID, "tv:777")
        XCTAssertEqual(item.kind, .show)
    }

    func testMapperUsesEncodedItemIDForMovieItem() {
        let movie = TMDBListItem(
            id: 888,
            title: "Some Movie",
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            releaseDate: nil,
            voteAverage: nil,
            mediaType: .movie
        )
        let item = TMDBMediaMapper.item(movie)
        XCTAssertEqual(item.ref.itemID, "movie:888")
        XCTAssertEqual(item.kind, .movie)
    }
}
