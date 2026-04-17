// ConfigHelper.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import Foundation

internal struct AutomaConfig: Codable {
    /// Fly configuration options
    let fly: FlyConfig
    /// GH Actions add secrets config
    let actionsSecrets: ActionsSecretsConfig
    /// Grafana project configuration
    let grafana: GrafanaProjectConfig
    /// Obsidian vault configuration
    let obsidian: ObsidianConfig?
}

internal struct GrafanaProjectConfig: Codable {
    /// The current environment for Grafana
    let currentEnvironment: String

    /// coding keys
    enum CodingKeys: String, CodingKey {
        case currentEnvironment = "current_environment"
    }
}

internal struct FlyConfig: Codable {
    /// Where the config files are stored for fly
    let configFilesRoot: String
    /// Mapping of Fly app names to ordered Obsidian env files for secret import
    let deploySecrets: [String: [String]]?

    /// coding keys
    enum CodingKeys: String, CodingKey {
        case configFilesRoot = "config_files_root"
        case deploySecrets = "deploy_secrets"
    }
}

internal struct ActionsSecretsConfig: Codable {
    /// <owner>/<repo> value for setting secrets
    let ownerRepo: String

    /// coding keys
    enum CodingKeys: String, CodingKey {
        case ownerRepo = "owner_repo"
    }
}

internal struct ObsidianConfig: Codable {
    /// The name of the Obsidian vault to target for secret reads
    let vaultName: String

    enum CodingKeys: String, CodingKey {
        case vaultName = "vault_name"
    }
}

internal enum ConfigHelper {
    /// retrieves the automa config
    /// throws .badURL error when the config file doesn't exist `run automa setup`
    internal static func getAutomaConfig() throws -> AutomaConfig {
        let configURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
        )
        .appendingPathComponent("automa.config.json")

        if !FileManager.default.fileExists(atPath: configURL.path) {
            print("Please run `automa setup` to create a config file for this project")
            throw URLError(.badURL)
        }

        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        return try decoder.decode(AutomaConfig.self, from: data)
    }
}
