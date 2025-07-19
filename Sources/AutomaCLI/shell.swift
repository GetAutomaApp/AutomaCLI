// shell.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import Foundation

internal enum CLIError: Error {
    case shellError(message: String, error: String?)
}

/// The output information of a shell command.
internal struct ShellOutput {
    /// The standard output of the command.
    public let stdout: String?
    /// The standard error output of the command.
    public let stderr: String?
    /// The exit status of the command.
    public let exitStatus: Int
    /// A flag indicating whether the command resulted in an error.
    public let isError: Bool
    /// The command that was executed.
    public let command: String
}

/// Enum representing different operating systems.
internal enum OperatingSystem {
    case linux
    case macos
    case unknown(value: String)
}

/// A simple shell wrapper in Swift, to execute shell commands.
internal struct Shell {
    /// The operating system on which the shell is running.
    public let operatingSystem: OperatingSystem
    /// The command used to copy text to the clipboard.
    public let copyCommand: String

    /// Initializes a new instance of `Shell`.
    /// - Throws: An error if the operating system cannot be determined.
    public init() throws {
        operatingSystem = try Self.getOperatingSystem()
        copyCommand = Self.getCopyCommand(os: operatingSystem)
    }

    /// Executes a shell command and returns the output.
    /// - Parameter command: The command to execute.
    /// - Returns: The output of the command.
    @discardableResult
    public static func run(_ command: String) throws -> ShellOutput {
        let task = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Set up the process to execute the command
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe
        task.executableURL = URL(filePath: "/bin/zsh")

        let fullCommand = "\(command)"
        task.arguments = ["-c", fullCommand]

        task.standardInput = nil
        try task.run()

        // Read the output from the command
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdoutOutput = String(data: stdoutData, encoding: .utf8)
        let stderrOutput = String(data: stderrData, encoding: .utf8)

        task.waitUntilExit()

        let status = Int(task.terminationStatus)

        return .init(
            stdout: stdoutOutput,
            stderr: stderrOutput,
            exitStatus: status,
            isError: status != 0,
            command: command
        )
    }

    /// Determines the operating system on which the shell is running.
    /// - Returns: The detected operating system.
    /// - Throws: An error if the operating system cannot be determined.
    private static func getOperatingSystem() throws -> OperatingSystem {
        let result = try Self.run("uname -s")

        guard
            let output = result.stdout
        else {
            throw CLIError.shellError(
                message: "Could not get operating system output from stdout.",
                error: result.stderr
            )
        }

        switch output {
        case "Darwin":
            return .macos
        case "Linux":
            return .linux
        default:
            return .unknown(value: output)
        }
    }

    /// Gets the command used to copy text to the clipboard based on the operating system.
    /// - Parameter os: The operating system.
    /// - Returns: The command used to copy text to the clipboard.
    private static func getCopyCommand(os operatingSystem: OperatingSystem) -> String {
        switch operatingSystem {
        case .macos:
            "pbcopy"
        case .linux, .unknown:
            "/tmp/\(UUID().uuidString)"
        }
    }
}
