
// GrafanaCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

// MARK: - Grafana Group (Entry Point)

internal struct GrafanaCommand: AsyncCommandGroup {
    struct Signature: CommandSignature {}

    var commands: [String: AnyAsyncCommand] = [
        "setup": GrafanaSetupCommand(),
        "apply": GrafanaApplyCommand(),
    ]

    var help: String = "Grafana related commands."

    func run(using context: inout CommandContext, signature: Signature) async throws {
        if let command = try await self.commmand(using: &context) {
            try await command.run(using: &context)
        } else if let `default` = self.defaultCommand {
            try await `default`.run(using: &context)
            return
        } else {
            try self.outputHelp(using: &context)
            throw CommandError.missingCommand
        }
    }

    private func commmand(using context: inout CommandContext) async throws -> AnyAsyncCommand? {
        if let name = context.input.arguments.first {
            context.input.arguments.removeFirst()
            guard let command = self.commands[name] else {
                throw CommandError.unknownCommand(name, available: Array(self.commands.keys))
            }
            context.input.executablePath.append(name)
            return command
        } else {
            return nil
        }
    }
}
