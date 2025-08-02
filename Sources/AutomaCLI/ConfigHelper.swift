//
//  ConfigHelper.swift
//  AutomaCLI
//
//  Created by Simon Ferns on 2025/08/01.
//

import Foundation

struct AutomaConfig: Codable {
    let fly: FlyConfig
}

struct FlyConfig: Codable {
    let configFilesRoot: String
    let environments: [String]

    enum CodingKeys: String, CodingKey {
        case configFilesRoot = "config_files_root"
        case environments
    }
}

enum ConfigHelper {
    static func getAutomaConfig() throws -> AutomaConfig {
        let configURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("automa.config.json")
        
        if !FileManager.default.fileExists(atPath: configURL.path) {
            let defaultConfig = AutomaConfig(fly: FlyConfig(configFilesRoot: "fly", environments: ["production", "sandbox", "staging"]))
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(defaultConfig)
            try data.write(to: configURL)
            return defaultConfig
        }
        
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        return try decoder.decode(AutomaConfig.self, from: data)
    }
}
