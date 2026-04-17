// SecretsCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

internal struct SecretsCommand: CommandGroup {
    let commands: [String: AnyCommand] = [
        "read": ReadSecretCommand(),
        "set": SetSecretCommand(),
        "pull": PullSecretCommand()
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
        @Argument(name: "filename", help: "The file to read from the configured Obsidian vault.")
        var filename: String
    }

    var help: String {
        "Reads a secret file from the configured Obsidian vault."
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let obsidian = try ObsidianSecretsClient(context: context)
        let content = try obsidian.read(file: signature.filename)
        context.console.print(content)
    }
}

internal struct SetSecretCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "filename", help: "The file to update in the configured Obsidian vault.")
        var filename: String

        @Argument(name: "key", help: "The env key to set.")
        var key: String

        @Argument(name: "value", help: "The env value to set.")
        var value: String

        @Flag(name: "pull", help: "Pull the updated file into the current directory after setting the secret.")
        var pull: Bool
    }

    var help: String {
        "Sets or replaces a secret value in a file in the configured Obsidian vault."
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let obsidian = try ObsidianSecretsClient(context: context)
        let existingContent = try obsidian.read(file: signature.filename)
        let updatedContent = updatedEnvFileContent(
            existingContent,
            key: signature.key.trimmingCharacters(in: .whitespacesAndNewlines),
            value: signature.value
        )

        try obsidian.update(file: signature.filename, content: updatedContent)

        if signature.pull {
            try LocalSecretsFileManager.writePulledFile(
                named: signature.filename,
                content: updatedContent
            )
        }

        context.console.success("Updated \(signature.key) in \(signature.filename).")
    }

    private func updatedEnvFileContent(_ content: String, key: String, value: String) -> String {
        let normalizedLine = "\(key)=\(value)"
        let newline = content.contains("\r\n") ? "\r\n" : "\n"
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        var replaced = false
        let updatedLines = lines.map { rawLine -> String in
            var line = String(rawLine)
            if line.hasSuffix("\r") {
                line.removeLast()
            }

            if line.hasPrefix("\(key)=") {
                replaced = true
                return normalizedLine
            }

            return line
        }

        if replaced {
            return updatedLines.joined(separator: newline)
        }

        if content.isEmpty {
            return normalizedLine
        }

        let needsTrailingNewline = !content.hasSuffix("\n") && !content.hasSuffix("\r\n")
        let separator = needsTrailingNewline ? newline : ""
        return content + separator + normalizedLine
    }
}

internal struct PullSecretCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "filename", help: "The file to pull from the configured Obsidian vault.")
        var filename: String
    }

    var help: String {
        "Pulls a secret file from the configured Obsidian vault into the current directory."
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let obsidian = try ObsidianSecretsClient(context: context)
        let content = try obsidian.read(file: signature.filename)
        let outputPath = try LocalSecretsFileManager.writePulledFile(
            named: signature.filename,
            content: content
        )

        context.console.success("Pulled \(signature.filename) to \(outputPath.lastPathComponent).")
    }
}

private enum LocalSecretsFileManager {
    static func writePulledFile(named filename: String, content: String) throws -> URL {
        let outputPath = localEnvPath(for: filename)
        let wrappedContent = wrappedLocalEnvContent(content)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: outputPath.path) {
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: outputPath.path)
        }

        try wrappedContent.write(to: outputPath, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: outputPath.path)

        return outputPath
    }

    private static func localEnvPath(for filename: String) -> URL {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let localFilename = trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(localFilename)
    }

    private static func wrappedLocalEnvContent(_ content: String) -> String {
        let banner = [
            "# ============================================================",
            "# This file is managed by Automa secrets.",
            "#",
            "# To pull the latest copy locally:",
            "#   automa secrets pull <file-name>",
            "#",
            "# To set a secret and refresh the local file:",
            "#   automa secrets set <file-name> KEY VALUE --pull",
            "#",
            "# Do not edit local .env files directly.",
            "# Local edits create a broken state and a poor developer experience.",
            "# ============================================================"
        ].joined(separator: "\n")

        if content.isEmpty {
            return [banner, banner].joined(separator: "\n")
        }

        return [banner, content, banner].joined(separator: "\n")
    }
}

private struct ObsidianSecretsClient {
    private let context: CommandContext
    private let vaultName: String

    init(context: CommandContext) throws {
        self.context = context

        let config = try ConfigHelper.getAutomaConfig()
        let vaultName =
            config.obsidian?.vaultName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if vaultName.isEmpty {
            context.console.error("Error: obsidian.vault_name is not set in automa.config.json.")
            context.console.print(
                "Please edit automa.config.json and set obsidian.vault_name to your Obsidian vault name."
            )
            throw CLIError.shellError(message: "Missing Obsidian vault name.", error: nil)
        }

        let obsidianCLI = try Shell.run("command -v obsidian")
        if obsidianCLI.isError {
            context.console.error("Error: obsidian CLI is not installed or not on PATH.")
            throw CLIError.shellError(message: "Missing obsidian CLI.", error: obsidianCLI.stderr)
        }

        self.vaultName = vaultName
    }

    func read(file: String) throws -> String {
        let filename = normalizedFilename(file)
        let output = try Shell.run(
            "obsidian vault=\(vaultName.shellEscapedArgument) read file=\(filename.shellEscapedArgument)"
        )
        try handle(output, failureMessage: "Failed to read secret from Obsidian.")
        return output.stdout?.trimmingCharacters(in: .newlines) ?? ""
    }

    func update(file: String, content: String) throws {
        let path = try resolvedPath(for: file)
        let output = try Shell.run(
            "obsidian vault=\(vaultName.shellEscapedArgument) create path=\(path.shellEscapedArgument) content=\(content.shellEscapedArgument) overwrite"
        )
        try handle(output, failureMessage: "Failed to update secret file in Obsidian.")
    }

    private func normalizedFilename(_ filename: String) -> String {
        filename.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedPath(for file: String) throws -> String {
        let filename = normalizedFilename(file)
        let output = try Shell.run(
            "obsidian vault=\(vaultName.shellEscapedArgument) file file=\(filename.shellEscapedArgument)"
        )
        try handle(output, failureMessage: "Failed to resolve Obsidian file path.")

        guard let stdout = output.stdout else {
            throw CLIError.shellError(message: "Obsidian did not return file metadata.", error: output.stderr)
        }

        for line in stdout.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("path\t") {
                return String(line.dropFirst(5))
            }
        }

        throw CLIError.shellError(message: "Obsidian did not return a file path.", error: output.stdout)
    }

    private func handle(_ output: ShellOutput, failureMessage: String) throws {
        if let stderr = output.stderr?.trimmingCharacters(in: .whitespacesAndNewlines), !stderr.isEmpty {
            context.console.error(stderr)
        }

        if output.isError {
            throw CLIError.shellError(message: failureMessage, error: output.stderr)
        }
    }
}
