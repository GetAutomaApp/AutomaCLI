// InfraCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

// MARK: - Infra Group (Entry Point)

internal struct InfraCommand: CommandGroup {
    let commands: [String: AnyCommand] = [
        "set-actions-secrets": SetActionsSecretsCommand(),
        "deploy-fly-secrets": DeployFlySecretsCommand(),
    ]

    let help = "Infrastructure related commands."

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

internal struct SetActionsSecretsCommand: Command {
    init() {}

    var help: String {
        "Sets GitHub Actions secrets from an environment file."
    }

    struct Signature: CommandSignature {
        init() {}

        @Argument(name: "env-file", help: "Path to the .env file containing secrets.")
        var envFile: String
    }

    func run(using context: CommandContext, signature: Signature) throws {
        // 1. Check for gh CLI
        do {
            _ = try Shell.run("command -v gh")
        } catch {
            context.console.warning("GitHub CLI (gh) is not installed.")
            context.console.print("Please install it with 'brew install gh' and then run 'gh auth login'.")
            context.console.print("Once setup is complete, please run this command again.")
            return // Exit gracefully
        }

        // 2. Check env file existence
        let envFilePath = signature.envFile
        if !FileManager.default.fileExists(atPath: envFilePath) {
            context.console.error("Error: Could not find env file at \(envFilePath)")
            return
        }

        // 3. Get Owner and Repo from config
        let config = try ConfigHelper.getAutomaConfig()
        let ownerRepo = config.actionsSecrets.ownerRepo

        if ownerRepo.isEmpty {
            context.console.error("Error: ownerRepo is not set in automa.config.json.")
            context.console.print("Please edit the config file and set the value to 'owner/repo'.")
            context.console.print("Set actionsSecrets.owner_repo value as <owner>/<repo> ")
            return
        }

        // 4. Set secrets using gh CLI
        context.console.print("Setting secrets for \(ownerRepo)...")
        let command = "gh secret set -f \"\(envFilePath)\" --repo \"\(ownerRepo)\""
        do {
            let output = try Shell.run(command)
            if let stdout = output.stdout {
                context.console.print(stdout)
            }
            if let stderr = output.stderr, !stderr.isEmpty {
                context.console.error(stderr)
            }
            context.console.success("Successfully set secrets.")
        } catch {
            context.console.error("Failed to set secrets.")
            context.console.error("Error: \(error)")
            context.console.print("Please ensure you are authenticated with 'gh auth login'")
            context.console.print("and have the correct permissions for the repository.")
            throw error
        }

        // 5. Generate and print the env block
        context.console.print("\nGenerating env block for GitHub Actions workflow...\n")
        context.console.print("env:")

        let fileURL = URL(fileURLWithPath: envFilePath)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(whereSeparator: \.isNewline)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.starts(with: "#") {
                continue
            }

            if let separatorIndex = trimmedLine.firstIndex(of: "=") {
                let key = String(trimmedLine[..<separatorIndex])
                context.console.print("  \(key): ${{ secrets.\(key) }}")
            }
        }
    }
}

internal struct DeployFlySecretsCommand: Command {
    init() {}

    var help: String {
        """
        Imports ordered Obsidian env files into each configured Fly app using fly.deploy_secrets.

        Config format:
          "fly": {
            "deploy_secrets": {
              "your-fly-app": ["base.env", "override.env"]
            }
          }

        Env files are imported in order, so later files override earlier values.
        Run without arguments to deploy secrets for every configured Fly app.
        """
    }

    struct Signature: CommandSignature {
        init() {}
    }

    func run(using context: CommandContext, signature _: Signature) throws {
        do {
            _ = try Shell.run("command -v fly")
        } catch {
            context.console.warning("Fly CLI (fly) is not installed.")
            context.console.print("Please install it and run 'fly auth login', then run this command again.")
            return
        }

        let config = try ConfigHelper.getAutomaConfig()
        guard let deploySecrets = config.fly.deploySecrets, !deploySecrets.isEmpty else {
            printDeploySecretsConfigHelp(using: context)
            return
        }

        let obsidian = try InfraObsidianSecretsClient(context: context)

        for appName in deploySecrets.keys.sorted() {
            let files = deploySecrets[appName] ?? []
            let normalizedFiles = files.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if normalizedFiles.isEmpty {
                context.console.warning("Skipping \(appName): no env files configured.")
                continue
            }

            context.console.print("Deploying Fly secrets for \(appName)...")
            var totalEntriesApplied = 0
            var totalUniqueKeysApplied = Set<String>()
            var totalMachinesUpdated = 0

            for filename in normalizedFiles {
                let content = try obsidian.read(file: filename)

                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    context.console.warning("Skipping empty secret file \(filename) for \(appName).")
                    continue
                }

                let summary = summarizeEnvFile(content)
                context.console.print(
                    "Importing \(filename) into \(appName) (\(summary.entryCount) entries, \(summary.uniqueKeys.count) unique keys)..."
                )

                let importSummary = try importSecrets(content: content, appName: appName, context: context)
                totalEntriesApplied += summary.entryCount
                totalUniqueKeysApplied.formUnion(summary.uniqueKeys)
                totalMachinesUpdated += importSummary.updatedMachineCount

                context.console.print(
                    "Applied \(summary.entryCount) entries from \(filename); Fly updated \(importSummary.updatedMachineCount) machine(s)."
                )
            }

            context.console.success(
                "Successfully imported \(totalEntriesApplied) entries across \(totalUniqueKeysApplied.count) unique key(s) into \(appName); Fly updated \(totalMachinesUpdated) machine(s)."
            )
        }
    }

    private func importSecrets(content: String, appName: String, context: CommandContext) throws -> FlySecretImportSummary {
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedAppName.isEmpty {
            context.console.error("Error: app-name cannot be empty.")
            throw CLIError.shellError(message: "Missing Fly app name.", error: nil)
        }

        let command = "printf %s \(content.shellEscapedArgument) | fly secrets import -a \(normalizedAppName.shellEscapedArgument)"
        let output = try Shell.run(command)

        if let stdout = output.stdout?.trimmingCharacters(in: .whitespacesAndNewlines), !stdout.isEmpty {
            printChildOutput(stdout, using: context)
        }

        if let stderr = output.stderr?.trimmingCharacters(in: .whitespacesAndNewlines), !stderr.isEmpty {
            printChildOutput(stderr, using: context, isError: true)
        }

        if output.isError {
            context.console.error("Failed to import Fly secrets.")
            context.console.print("Please ensure 'fly auth login' has completed and the app name is correct.")
            throw CLIError.shellError(message: "Failed to import Fly secrets.", error: output.stderr)
        }

        return FlySecretImportSummary(output: output)
    }

    private func summarizeEnvFile(_ content: String) -> EnvFileSummary {
        let lines = content.split(whereSeparator: \.isNewline)
        var keys = [String]()

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.starts(with: "#") {
                continue
            }

            if let separatorIndex = trimmedLine.firstIndex(of: "=") {
                let key = String(trimmedLine[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    keys.append(key)
                }
            }
        }

        return EnvFileSummary(entryCount: keys.count, uniqueKeys: Set(keys))
    }

    private func printChildOutput(_ output: String, using context: CommandContext, isError: Bool = false) {
        for line in output.split(whereSeparator: \.isNewline) {
            let prefixedLine = "    \(line)"
            if isError {
                context.console.error(prefixedLine)
            } else {
                context.console.print(prefixedLine)
            }
        }
    }

    private func printDeploySecretsConfigHelp(using context: CommandContext) {
        context.console.print("No fly.deploy_secrets configuration found in automa.config.json.")
        context.console.print("Add it in this format to enable automatic Fly secret deployment:")
        context.console.print("{")
        context.console.print("  \"fly\": {")
        context.console.print("    \"deploy_secrets\": {")
        context.console.print("      \"your-fly-app\": [\"base.env\", \"override.env\"]")
        context.console.print("    }")
        context.console.print("  }")
        context.console.print("}")
        context.console.print("Env files are imported in order, so later files override earlier values.")
    }
}

private struct EnvFileSummary {
    let entryCount: Int
    let uniqueKeys: Set<String>
}

private struct FlySecretImportSummary {
    let updatedMachineCount: Int

    init(output: ShellOutput) {
        let stdout = output.stdout ?? ""
        let stderr = output.stderr ?? ""
        let combinedOutput = "\(stdout)\n\(stderr)"

        updatedMachineCount = combinedOutput
            .split(whereSeparator: \.isNewline)
            .filter { $0.contains("update succeeded") }
            .count
    }
}

private struct InfraObsidianSecretsClient {
    private let context: CommandContext
    private let vaultName: String

    init(context: CommandContext) throws {
        self.context = context

        let config = try ConfigHelper.getAutomaConfig()
        let vaultName = config.obsidian?.vaultName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

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
        let filename = file.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = try Shell.run(
            "obsidian vault=\(vaultName.shellEscapedArgument) read file=\(filename.shellEscapedArgument)"
        )

        if let stderr = output.stderr?.trimmingCharacters(in: .whitespacesAndNewlines), !stderr.isEmpty {
            context.console.error(stderr)
        }

        if output.isError {
            throw CLIError.shellError(message: "Failed to read secret from Obsidian.", error: output.stderr)
        }

        return output.stdout?.trimmingCharacters(in: .newlines) ?? ""
    }
}
