// The Swift Programming Language
// https://docs.swift.org/swift-book
import ConsoleKit
import Foundation
import Logging

@main
struct AutomaCLI {
    static func main() {
        let console = Terminal()
        let input = CommandInput(arguments: ProcessInfo.processInfo.arguments)

        autoUpdate()

        let commands = Commands(enableAutocomplete: true)
        //commands.use(DemoCommand(), as: "demo", isDefault: false)

        do {
            let group = commands.group(help: "The AUTOMA CLI tool")
            try console.run(group, input: input)
        } catch let error {
            console.error("\(error)")
        }
    }

    static func autoUpdate() {
        do {
            let config = try loadConfig()
            let repoPath = config.repoPath

            // Change current directory to repoPath
            let currentDirectory = FileManager.default.currentDirectoryPath
            defer {
                // Restore original directory after function exits
                FileManager.default.changeCurrentDirectoryPath(currentDirectory)
            }
            guard FileManager.default.changeCurrentDirectoryPath(repoPath) else {
                print("Error: Could not change to repository directory: \(repoPath)")
                return
            }

            print("Checking for updates...")
            _ = try Shell.run("git fetch origin main")

            let localCommitOutput = try Shell.run("git rev-parse HEAD")
            guard let localCommit = localCommitOutput.stdout?.trimmingCharacters(in: .whitespacesAndNewlines), !localCommit.isEmpty else {
                print("Error: Could not get local commit hash.")
                return
            }

            let remoteCommitOutput = try Shell.run("git rev-parse origin/main")
            guard let remoteCommit = remoteCommitOutput.stdout?.trimmingCharacters(in: .whitespacesAndNewlines), !remoteCommit.isEmpty else {
                print("Error: Could not get remote commit hash.")
                return
            }

            if localCommit != remoteCommit {
                print("New version available. Updating...")
                _ = try Shell.run("git pull origin main")
                print("Building AutomaCLI...")
                _ = try Shell.run("swift build -c release")

                let binPath = "\(repoPath)/.build/release/automa"
                let linkPath = "/usr/local/bin/automa"

                print("Creating symbolic link for AutomaCLI...")
                _ = try Shell.run("sudo rm -f \(linkPath)") // Use -f to force remove without prompt
                let symlinkResult = try Shell.run("sudo ln -s \(binPath) \(linkPath)")
                if symlinkResult.isError {
                    print("Warning: Failed to create symbolic link. You may need to add /usr/local/bin to your PATH or run the script with appropriate permissions. Error: \(symlinkResult.stderr ?? "Unknown error")")
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
