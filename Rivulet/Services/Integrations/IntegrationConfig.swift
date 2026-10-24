// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  IntegrationConfig.swift
//  Rivulet
//
//  Connection settings for the request and download services (Seerr, Radarr,
//  Sonarr). The whole config lives in the Keychain: the API key is a secret,
//  and so are most custom headers (reverse proxy auth tokens).
//

import Foundation

nonisolated enum IntegrationService: String, CaseIterable, Sendable {
    case seerr, radarr, sonarr

    var displayName: String {
        switch self {
        case .seerr: return "Seerr"
        case .radarr: return "Radarr"
        case .sonarr: return "Sonarr"
        }
    }

    var urlPlaceholder: String {
        switch self {
        case .seerr: return "https://seerr.example.com"
        case .radarr: return "https://radarr.example.com"
        case .sonarr: return "https://sonarr.example.com"
        }
    }
}

nonisolated struct IntegrationHeader: Codable, Equatable, Sendable {
    var name: String
    var value: String

    /// Parses one header typed as `Name: Value`. The value may itself contain
    /// colons (a URL, a base64 token), so only the first one splits.
    static func parse(_ text: String) -> IntegrationHeader? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let name = text[..<colon].trimmingCharacters(in: .whitespaces)
        let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !value.isEmpty,
              name.unicodeScalars.allSatisfy({ isTokenCharacter($0) }) else { return nil }
        return IntegrationHeader(name: name, value: value)
    }

    /// RFC 9110 token characters, the only ones a header name may hold.
    private static func isTokenCharacter(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.isASCII else { return false }
        if CharacterSet.alphanumerics.contains(scalar) { return true }
        return "!#$%&'*+-.^_`|~".unicodeScalars.contains(scalar)
    }
}

nonisolated struct IntegrationConfig: Codable, Equatable, Sendable {
    var baseURL: String = ""
    var apiKey: String = ""
    var headers: [IntegrationHeader] = []

    var isConfigured: Bool { normalizedBaseURL != nil && !apiKey.isEmpty }

    /// The base URL with surrounding whitespace and trailing slashes removed,
    /// or nil unless it is an http(s) URL with a host. Paths are kept, so a
    /// service behind `https://host/seerr` works.
    var normalizedBaseURL: URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

/// Reads and writes `IntegrationConfig`s. Kept in memory after the first read
/// so the detail page does not hit the Keychain per card.
@MainActor
enum IntegrationStore {
    private static var cache: [IntegrationService: IntegrationConfig] = [:]

    private static func key(_ service: IntegrationService) -> String { "integration_\(service.rawValue)" }

    static func config(for service: IntegrationService) -> IntegrationConfig {
        if let cached = cache[service] { return cached }
        let loaded = KeychainHelper.get(key(service))
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(IntegrationConfig.self, from: $0) }
            ?? IntegrationConfig()
        cache[service] = loaded
        return loaded
    }

    static func save(_ config: IntegrationConfig, for service: IntegrationService) {
        cache[service] = config
        if config == IntegrationConfig() {
            KeychainHelper.delete(key(service))
        } else if let data = try? JSONEncoder().encode(config), let json = String(data: data, encoding: .utf8) {
            KeychainHelper.set(json, forKey: key(service))
        }
        MediaRequestStatusResolver.shared.invalidate()
    }

    static func update(_ service: IntegrationService, _ change: (inout IntegrationConfig) -> Void) {
        var config = config(for: service)
        change(&config)
        save(config, for: service)
    }

    static func isConfigured(_ service: IntegrationService) -> Bool {
        config(for: service).isConfigured
    }
}
