// SecretsCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

internal struct SecretsCommand: CommandGroup {
    let commands: [String: AnyCommand] = [
        "read": ReadSecretCommand(),
    ]

    let help = "Secrets related commands."

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

internal struct ReadSecretCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "filename", help: "The filename to read from the configured Obsidian vault.")
        var filename: String
    }

    var help: String {
        "Reads a secret file from the configured Obsidian vault."
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let config = try ConfigHelper.getAutomaConfig()
        let vaultName = config.obsidian?.vaultName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if vaultName.isEmpty {
            context.console.error("Error: obsidian.vault_name is not set in automa.config.json.")
            context.console.print("Please edit automa.config.json and set obsidian.vault_name to your Obsidian vault name.")
            return
        }

        let filename = signature.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty {
            context.console.error("Error: filename cannot be empty.")
            return
        }

        let path = normalizedObsidianPath(from: filename)

        do {
            _ = try Shell.run("command -v obsidian")
        } catch {
            context.console.error("Error: obsidian CLI is not installed or not on PATH.")
            return
        }

        let command = "obsidian vault=\(vaultName.shellEscapedArgument) read path=\(path.shellEscapedArgument)"
        let output = try Shell.run(command)

        if let stdout = output.stdout?.trimmingCharacters(in: .whitespacesAndNewlines), !stdout.isEmpty {
            context.console.print(stdout)
        }

        if let stderr = output.stderr?.trimmingCharacters(in: .whitespacesAndNewlines), !stderr.isEmpty {
            context.console.error(stderr)
        }

        if output.isError {
            throw CLIError.shellError(message: "Failed to read secret from Obsidian.", error: output.stderr)
        }
    }

    private func normalizedObsidianPath(from filename: String) -> String {
        if filename.hasSuffix(".md") {
            return filename
        }

        return "\(filename).md"
    }
}

private extension String {
    var shellEscapedArgument: String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
