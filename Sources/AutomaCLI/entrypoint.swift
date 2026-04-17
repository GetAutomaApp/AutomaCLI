// entrypoint.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

// The Swift Programming Language
// https://docs.swift.org/swift-book
import ConsoleKit
import Foundation
import Logging

@main
internal struct AutomaCLI {
    internal static func main() async {
        let console = Terminal()
        var input = CommandInput(arguments: ProcessInfo.processInfo.arguments)

        if !input.arguments.contains("--no-update") {
            #if NO_AUTOMATIC_UPDATE
            // for binary releases we don't automatically update
            #else
                autoUpdate()
            #endif
        } else {
            input.arguments.removeAll { $0 == "--no-update" }
        }

        var commands = AsyncCommands(enableAutocomplete: true)
        commands.use(GenerateGroup(), as: "generate", isDefault: false)
        commands.use(InfraCommand(), as: "infra", isDefault: false)
        commands.use(SecretsCommand(), as: "secrets", isDefault: false)
        commands.use(SetupCommand(), as: "setup", isDefault: false)
        commands.use(GrafanaCommand(), as: "grafana")

        do {
            let group = commands.group(help: "The AUTOMA CLI tool")
            try await console.run(group, input: input)
        } catch {
            console.error("\(error)")
        }
    }

    internal static func autoUpdate() {
        do {
            let config = try loadConfig()
            let repoPath = config.repoPath

            // Change current directory to repoPath
            let currentDirectory = FileManager.default.currentDirectoryPath
            defer {
                // Restore original directory after function exits
                _ = FileManager.default.changeCurrentDirectoryPath(currentDirectory)
            }
            guard FileManager.default.changeCurrentDirectoryPath(repoPath) else {
                print("Error: Could not change to repository directory: \(repoPath)")
                return
            }

            print("Checking for updates...")
            _ = try Shell.run("git fetch origin main")

            let localCommitOutput = try Shell.run("git rev-parse HEAD")
            guard let localCommit = localCommitOutput.stdout?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !localCommit.isEmpty
            else {
                print("Error: Could not get local commit hash.")
                return
            }

            let remoteCommitOutput = try Shell.run("git rev-parse origin/main")
            guard let remoteCommit = remoteCommitOutput.stdout?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !remoteCommit.isEmpty
            else {
                print("Error: Could not get remote commit hash.")
                return
            }

            if localCommit != remoteCommit {
                print("New version available. Updating...")
                _ = try Shell.run("git pull origin main")
                print("Building AutomaCLI...")
                _ = try Shell.run("/usr/bin/xcrun swift build -c release")

                let binPath = "\(repoPath)/.build/release/automa"
                let linkPath = "/usr/local/bin/automa"

                print("Creating symbolic link for AutomaCLI with elevated permissions...")
                let symlinkResult = try Shell.runPrivileged(
                    "ln -sf \(binPath.shellEscapedArgument) \(linkPath.shellEscapedArgument)"
                )
                if symlinkResult.isError {
                    print("Warning: Failed to create symbolic link.")
                    print(
                        "You may need to add /usr/local/bin to your PATH or run the script with appropriate permissions."
                    )
                    print("Error: \(symlinkResult.stderr ?? "Unknown error")")
                } else {
                    print("AutomaCLI updated and symlinked successfully.")
                }
            } else {
                print("AutomaCLI is already up to date.")
            }
        } catch let error as ConfigError {
            print("Configuration error: \(error.description)")
        } catch {
            print("Update check failed: \(error)")
        }
    }
}
