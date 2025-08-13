// helpers.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import Foundation

internal struct Config: Codable {
    internal let repoPath: String
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
