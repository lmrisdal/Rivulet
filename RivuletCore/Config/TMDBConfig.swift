// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

/// Direct TMDB access shared by search, metadata, artwork and recommendations.
enum TMDBConfig {
    // Keep the trailing slash: relative paths must retain the /3/ API version.
    static let apiBaseURL = URL(string: "https://api.themoviedb.org/3/")!
    static let localCacheTTL: TimeInterval = 60 * 60 * 24 * 30

    static func request(path: String, queryItems: [URLQueryItem] = [],
                        baseURL: URL = apiBaseURL) -> URLRequest? {
        let apiKey = Secrets.tmdbAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty,
              let url = URL(string: path, relativeTo: baseURL),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        components.queryItems = queryItems + [URLQueryItem(name: "api_key", value: apiKey)]
        guard let finalURL = components.url else { return nil }
        var request = URLRequest(url: finalURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
