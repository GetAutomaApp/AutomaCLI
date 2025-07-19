
import Foundation

struct Config: Codable {
    let repoPath: String
}

enum ConfigError: Error, CustomStringConvertible {
    case fileNotFound(path: String)
    case decodingError(Error)
    case invalidPath

    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Config file not found at: \(path)"
        case .decodingError(let error):
            return "Error decoding config file: \(error.localizedDescription)"
        case .invalidPath:
            return "Invalid configuration path."
        }
    }
}

func loadConfig() throws -> Config {
    let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/automacli")
    let configFile = configDir.appendingPathComponent("config.json")

    guard FileManager.default.fileExists(atPath: configFile.path) else {
        throw ConfigError.fileNotFound(path: configFile.path)
    }

    do {
        let data = try Data(contentsOf: configFile)
        let config = try JSONDecoder().decode(Config.self, from: data)
        return config
    } catch {
        throw ConfigError.decodingError(error)
    }
}
