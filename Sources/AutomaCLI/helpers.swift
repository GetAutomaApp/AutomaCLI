// helpers.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import Foundation

internal struct Config: Codable {
    internal var repoPath: String
    internal var grafana: [String: GrafanaConfig]?
}

internal struct GrafanaConfig: Codable {
    internal let url: String
    internal let token: String
}

internal enum ConfigError: Error, CustomStringConvertible {
    case decodingError(Error)
    case fileNotFound(path: String)
    case invalidPath

    internal var description: String {
        switch self {
        case let .fileNotFound(path):
            return "Config file not found at: \(path)"
        case let .decodingError(error):
            return "Error decoding config file: \(error.localizedDescription)"
        case .invalidPath:
            return "Invalid configuration path."
        }
    }
}

internal func loadConfig() throws -> Config {
    let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/automacli")
    let configFile = configDir.appendingPathComponent("config.json")

    guard FileManager.default.fileExists(atPath: configFile.path) else {
        throw ConfigError.fileNotFound(path: configFile.path)
    }

    do {
        let data = try Data(contentsOf: configFile)
        return try JSONDecoder().decode(Config.self, from: data)
    } catch {
        throw ConfigError.decodingError(error)
    }
}

internal func saveConfig(_ config: Config) throws {
    let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/automacli")
    let configFile = configDir.appendingPathComponent("config.json")

    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)
        try data.write(to: configFile, options: .atomic)
    } catch {
        throw ConfigError.decodingError(error)
    }
}
