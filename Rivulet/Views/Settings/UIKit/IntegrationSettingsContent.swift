// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  IntegrationSettingsContent.swift
//  Rivulet
//
//  Settings > Integrations: Seerr, Radarr and Sonarr. Each has an address, an
//  API key and a list of custom headers (reverse proxy auth), and saves as it
//  is edited, so there is no draft to lose on Menu.
//

import Foundation
import UIKit

extension SettingsContent {

    /// The service whose Custom Headers page is open. Set by the service
    /// page's row before pushing (SettingsPage carries no associated data).
    static var pendingIntegration: IntegrationService = .seerr

    /// Set while Test Connection runs, so the row says so and ignores a second press.
    private static var testingIntegration: IntegrationService?

    static var integrations: [SettingsRowItem] {
        IntegrationService.allCases.map { service in
            SettingsRowItem(id: "int_\(service.rawValue)", title: service.displayName,
                            kind: .navigationValue(page(for: service), value: {
                                IntegrationStore.isConfigured(service) ? "On" : "Off"
                            }))
        }
    }

    static func page(for service: IntegrationService) -> SettingsPage {
        switch service {
        case .seerr: return .seerr
        case .radarr: return .radarr
        case .sonarr: return .sonarr
        }
    }

    static func integrationRows(_ service: IntegrationService) -> [SettingsRowItem] {
        let config = { IntegrationStore.config(for: service) }
        var rows: [SettingsRowItem] = [
            SettingsRowItem(id: "int_url", title: "Server URL",
                            kind: .textEntry(value: { config().baseURL },
                                             placeholder: service.urlPlaceholder,
                                             hint: "The address you open \(service.displayName) at in a browser.",
                                             suggestions: [], keyboardType: .URL,
                                             set: { text in
                                                 IntegrationStore.update(service) {
                                                     $0.baseURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                                 }
                                             })),
            SettingsRowItem(id: "int_apiKey", title: "API Key",
                            kind: .textEntry(value: { config().apiKey },
                                             placeholder: "",
                                             hint: "In \(service.displayName), under Settings, then General.",
                                             suggestions: [], keyboardType: .asciiCapable, isSecure: true,
                                             set: { text in
                                                 IntegrationStore.update(service) {
                                                     $0.apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                                 }
                                             })),
            SettingsRowItem(id: "int_headers", title: "Custom Headers",
                            kind: .navigationAction(.integrationHeaders,
                                                    value: {
                                                        let count = config().headers.count
                                                        return count == 0 ? "None" : "\(count)"
                                                    },
                                                    prepare: { pendingIntegration = service })),
            SettingsRowItem(id: "int_test",
                            title: testingIntegration == service ? "Testing…" : "Test Connection",
                            kind: .action(destructive: false, handler: { vc in
                                testConnection(service, on: vc)
                            }),
                            isEnabled: { config().isConfigured })
        ]
        if config() != IntegrationConfig() {
            rows.append(SettingsRowItem(id: "int_remove", title: "Remove \(service.displayName)",
                                        kind: .action(destructive: true, handler: { vc in
                vc.present(ConfirmationPopupViewController(
                    title: "Remove \(service.displayName)?",
                    message: "Forgets its address, API key and custom headers on this Apple TV.",
                    confirmTitle: "Remove", destructive: true, onConfirm: {
                        IntegrationStore.save(IntegrationConfig(), for: service)
                        (vc as? SettingsPageViewController)?.reloadRows()
                    }), animated: true)
            })))
        }
        return rows
    }

    private static func testConnection(_ service: IntegrationService, on vc: UIViewController) {
        guard testingIntegration == nil else { return }
        testingIntegration = service
        (vc as? SettingsPageViewController)?.reloadRows()
        let config = IntegrationStore.config(for: service)
        Task { @MainActor in
            let title: String
            let message: String
            do {
                switch service {
                case .seerr: message = try await SeerrClient(config: config).testConnection()
                case .radarr, .sonarr: message = try await ArrClient(service: service, config: config).testConnection()
                }
                title = "Connected"
            } catch {
                title = "Couldn't Connect"
                message = error.localizedDescription
            }
            testingIntegration = nil
            (vc as? SettingsPageViewController)?.reloadRows()
            guard vc.viewIfLoaded?.window != nil, vc.presentedViewController == nil else { return }
            vc.present(ConfirmationPopupViewController(title: title, message: message, confirmTitle: "OK",
                                                       cancelTitle: nil, onConfirm: {}), animated: true)
        }
    }

    // MARK: Custom Headers

    static var integrationHeaders: [SettingsRowItem] {
        let service = pendingIntegration
        var rows: [SettingsRowItem] = IntegrationStore.config(for: service).headers.map { header in
            SettingsRowItem(id: "intHeader_\(header.name)", title: header.name,
                            kind: .action(destructive: false, handler: { vc in
                vc.present(ConfirmationPopupViewController(
                    title: "Remove \(header.name)?",
                    message: "\(service.displayName) requests stop sending this header.",
                    confirmTitle: "Remove", destructive: true, onConfirm: {
                        IntegrationStore.update(service) { $0.headers.removeAll { $0.name == header.name } }
                        (vc as? SettingsPageViewController)?.reloadRows()
                    }), animated: true)
            }))
        }
        rows.append(SettingsRowItem(id: "int_addHeader", title: "Add Header",
                                    kind: .action(destructive: false, handler: { vc in
            presentAddHeader(service, on: vc, initialText: "")
        })))
        return rows
    }

    private static func presentAddHeader(_ service: IntegrationService, on vc: UIViewController, initialText: String) {
        let entry = TextEntryViewController(
            title: "Add Header", message: "Enter Name: Value, for example CF-Access-Client-Id: abc123",
            fieldName: "Header", initialText: initialText,
            keyboardType: .asciiCapable,
            onCommit: { text in
                guard let header = IntegrationHeader.parse(text) else {
                    vc.present(ConfirmationPopupViewController(
                        title: "Not a Header",
                        message: "Type the header as Name: Value. The name may hold letters, digits and dashes.",
                        confirmTitle: "Try Again", onConfirm: {
                            presentAddHeader(service, on: vc, initialText: text)
                        }), animated: true)
                    return
                }
                IntegrationStore.update(service) { config in
                    // Header names are case-insensitive: a new one replaces the old.
                    config.headers.removeAll { $0.name.caseInsensitiveCompare(header.name) == .orderedSame }
                    config.headers.append(header)
                }
                (vc as? SettingsPageViewController)?.reloadRows()
            })
        vc.present(entry, animated: true)
    }
}
