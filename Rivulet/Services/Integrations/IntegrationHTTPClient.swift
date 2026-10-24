// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  IntegrationHTTPClient.swift
//  Rivulet
//
//  The one HTTP path to Seerr, Radarr and Sonarr. All three authenticate with
//  an `X-Api-Key` header; the user's custom headers (reverse proxy auth) go on
//  every request after it.
//

import Foundation

nonisolated enum IntegrationError: LocalizedError, Equatable {
    case notConfigured
    case invalidURL
    case unauthorized
    case http(Int, String?)
    case transport(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add a server URL and an API key first."
        case .invalidURL: return "The server URL is not valid. It must start with http:// or https://."
        case .unauthorized: return "The server rejected the API key or your custom headers."
        case .http(let code, let message):
            if let message, !message.isEmpty { return "The server answered \(code): \(message)" }
            return "The server answered with status \(code)."
        case .transport(let message): return message
        case .decoding: return "The server's answer was not what was expected. Check the URL points at the right service."
        }
    }
}

nonisolated struct IntegrationHTTPClient: Sendable {
    let config: IntegrationConfig

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET",
                 body: Data? = nil) throws -> URLRequest {
        guard config.isConfigured else { throw IntegrationError.notConfigured }
        guard let base = config.normalizedBaseURL,
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw IntegrationError.invalidURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw IntegrationError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Api-Key")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for header in config.headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        return request
    }

    func send(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> Data {
        let request = try request(path, query: query, method: method, body: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw IntegrationError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw IntegrationError.decoding }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw IntegrationError.unauthorized
        default: throw IntegrationError.http(http.statusCode, Self.serverMessage(in: data))
        }
    }

    func get<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await send(path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw IntegrationError.decoding
        }
    }

    /// Seerr and the *arr apps both explain a failure in a `message` field.
    private static func serverMessage(in data: Data) -> String? {
        struct Message: Decodable { let message: String? }
        return (try? JSONDecoder().decode(Message.self, from: data))?.message
    }
}
