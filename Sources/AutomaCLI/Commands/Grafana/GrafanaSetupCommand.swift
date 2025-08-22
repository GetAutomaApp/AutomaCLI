
// GrafanaSetupCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

internal struct GrafanaSetupCommand: Command {
    init() {}

    var help: String {
        "Sets up Grafana credentials for a specific environment."
    }

    struct Signature: CommandSignature {
        init() {}

        @Argument(name: "environment", help: "The environment to configure (e.g., 'staging', 'production').")
        var environment: String

        @Argument(name: "url", help: "The Grafana URL.")
        var url: String

        @Argument(name: "access_token", help: "The Grafana access token.")
        var accessToken: String
    }

    func run(using context: CommandContext, signature: Signature) throws {
        context.console.print("Setting up Grafana for \(signature.environment) environment...")

        var config = try loadConfig()
        var grafanaConfigs = config.grafana ?? [:]
        grafanaConfigs[signature.environment] = GrafanaConfig(url: signature.url, token: signature.accessToken)
        config.grafana = grafanaConfigs
        try saveConfig(config)

        context.console.success("Grafana setup complete for \(signature.environment) environment.")
    }
}
