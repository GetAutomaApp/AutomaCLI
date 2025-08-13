
// GrafanaCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

// MARK: - Grafana Group (Entry Point)

internal struct GrafanaCommand: CommandGroup {
    let commands: [String: AnyCommand] = [
        "setup": GrafanaSetupCommand(),
        "apply": GrafanaApplyCommand(),
    ]

    let help = "Grafana related commands."

    func run(using context: inout CommandContext) throws {
        if let command = try commmand(using: &context) {
            try command.run(using: &context)
        } else if let `default` = defaultCommand {
            try `default`.run(using: &context)
            return
        } else {
            try outputHelp(using: &context)
            throw CommandError.missingCommand
        }
    }

    private func commmand(using context: inout CommandContext) throws -> AnyCommand? {
        if let name = context.input.arguments.first {
            context.input.arguments.removeFirst()
            guard let command = commands[name] else {
                throw CommandError.unknownCommand(name, available: Array(commands.keys))
            }
            context.input.executablePath.append(name)
            return command
        } else {
            return nil
        }
    }
}
