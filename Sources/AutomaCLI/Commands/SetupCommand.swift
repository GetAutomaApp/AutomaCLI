// SetupCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

internal struct SetupCommand: Command {
    internal struct Signature: CommandSignature {}

    var help: String {
        "Sets up the Automa CLI for the current project by creating a default automa.config.json file."
    }

    func run(using context: CommandContext, signature _: Signature) throws {
        let configPath = "automa.config.json"
        if FileManager.default.fileExists(atPath: configPath) {
            context.console.print("automa.config.json already exists.")
        } else {
            let defaultConfig = AutomaConfig(
                fly: FlyConfig(configFilesRoot: "fly", environments: ["production", "sandbox", "staging"]),
                actionsSecrets: ActionsSecretsConfig(ownerRepo: ""),
                grafana: GrafanaProjectConfig(currentEnvironment: "staging"),
                obsidian: ObsidianConfig(vaultName: "")
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(defaultConfig)
            try data.write(to: URL(fileURLWithPath: configPath))
            context.console.print("Created empty automa.config.json.")
        }
    }
}
