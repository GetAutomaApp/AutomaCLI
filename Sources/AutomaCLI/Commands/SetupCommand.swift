//
//  SetupCommand.swift
//  AutomaCLI
//
//  Created by Simon Ferns on 2025/08/01.
//

import Foundation
import ConsoleKit

struct SetupCommand: Command {
    struct Signature: CommandSignature {}

    var help: String {
        "Sets up the Automa CLI for the current project by creating a default automa.config.json file."
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let configPath = "automa.config.json"
        if FileManager.default.fileExists(atPath: configPath) {
            context.console.print("automa.config.json already exists.")
        } else {
            let defaultConfig = AutomaConfig(
                fly: FlyConfig(configFilesRoot: "fly", environments: ["production", "sandbox", "staging"]),
                actionsSecrets: ActionsSecretsConfig(ownerRepo: "")
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(defaultConfig)
            try data.write(to: URL(fileURLWithPath: configPath))
            context.console.print("Created empty automa.config.json.")
        }
    }
}
