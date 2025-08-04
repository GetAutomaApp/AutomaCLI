//
//  ConfigHelper.swift
//  AutomaCLI
//
//  Created by Simon Ferns on 2025/08/01.
//

import Foundation

struct AutomaConfig: Codable {
    let fly: FlyConfig
    let actionsSecrets: ActionsSecretsConfig
}

struct FlyConfig: Codable {
    let configFilesRoot: String
    let environments: [String]

    enum CodingKeys: String, CodingKey {
        case configFilesRoot = "config_files_root"
        case environments
    }
}

struct ActionsSecretsConfig: Codable {
    let ownerRepo: String

    enum CodingKeys: String, CodingKey {
        case ownerRepo = "owner_repo"
    }
}

enum ConfigHelper {
    static func getAutomaConfig() throws -> AutomaConfig {
        let configURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("automa.config.json")
        
        if !FileManager.default.fileExists(atPath: configURL.path) {
            print("Please run `automa setup` to create a config file for this project")
        }
        
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        return try decoder.decode(AutomaConfig.self, from: data)
    }
}
