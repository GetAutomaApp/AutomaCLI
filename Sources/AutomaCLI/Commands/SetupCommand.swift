//
//  SetupCommand.swift
//  AutomaCLI
//
//  Created by Simon Ferns on 2025/08/01.
//

import Foundation
import Vapor

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
            let defaultConfig = "{}"
            try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            context.console.print("Created empty automa.config.json.")
        }
    }
}
