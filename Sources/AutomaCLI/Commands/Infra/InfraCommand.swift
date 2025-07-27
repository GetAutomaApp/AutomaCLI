import ConsoleKit
import Foundation

// MARK: - Infra Group (Entry Point)

struct InfraCommand: CommandGroup {
    let commands: [String: AnyCommand] = [
        "set-actions-secrets": SetActionsSecretsCommand(),
    ]

    let help = "Infrastructure related commands."

    func run(using context: inout CommandContext) throws {
        if let command = try self.commmand(using: &context) {
            try command.run(using: &context)
        } else if let `default` = self.defaultCommand {
            return try `default`.run(using: &context)
        } else {
            try self.outputHelp(using: &context)
            throw CommandError.missingCommand
        }
    }

    private func commmand(using context: inout CommandContext) throws -> AnyCommand? {
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

struct SetActionsSecretsCommand: Command {
    public init() {}

    public var help: String {
        "Sets GitHub Actions secrets from an environment file."
    }

    public struct Signature: CommandSignature {
        public init() {}

        @Argument(name: "env-file", help: "Path to the .env file containing secrets.")
        public var envFile: String
    }

    public func run(using context: CommandContext, signature: Signature) throws {
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

        // 3. Get Owner and Repo from user
        let owner = context.console.ask("Enter the repository owner (e.g., 'your-github-username'):")
        let repo = context.console.ask("Enter the repository name (e.g., 'your-repo-name'):")

        if owner.isEmpty || repo.isEmpty {
            context.console.error("Error: Owner and repository name cannot be empty.")
            return
        }

        // 4. Set secrets using gh CLI
        context.console.print("Setting secrets for \(owner)/\(repo)...")
        let command = "gh secret set -f \"\(envFilePath)\" --repo \"\(owner)/\(repo)\""
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
            context.console.print("Please ensure you are authenticated with 'gh auth login' and have the correct permissions for the repository.")
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
