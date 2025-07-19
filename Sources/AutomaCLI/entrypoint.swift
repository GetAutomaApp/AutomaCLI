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
            let shell = try Shell()

            let localTagOutput = try Shell.run("git describe --tags --abbrev=0")
            guard let localTag = localTagOutput.stdout?.trimmingCharacters(in: .whitespacesAndNewlines), !localTag.isEmpty else {
                print("No local tag found.")
                return
            }

            let remoteTagsOutput = try Shell.run("git ls-remote --tags origin")
            guard let remoteTags = remoteTagsOutput.stdout else {
                print("No remote tags found.")
                return
            }

            let tagPattern = #"refs/tags/([^\^\n]+)"#
            let tagRegex = try NSRegularExpression(pattern: tagPattern)
            let matches = tagRegex.matches(in: remoteTags, range: NSRange(remoteTags.startIndex..., in: remoteTags))

            let remoteTagList = matches.compactMap {
                Range($0.range(at: 1), in: remoteTags).map { String(remoteTags[$0]) }
            }.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending })

            guard let latestRemoteTag = remoteTagList.first, latestRemoteTag != localTag else {
                print("Already on the latest version: \(localTag)")
                return
            }

            print("New version available: \(latestRemoteTag). Updating from \(localTag)...")

            let osName: String
            switch shell.operatingSystem {
            case .macos:
                osName = "macos"
            case .linux:
                osName = "linux"
            case .unknown(let value):
                print("Unsupported OS: \(value)")
                return
            }

            let fileName = "\(osName)-\(latestRemoteTag).bin"
            let downloadURL = "https://github.com/YourOrg/YourRepo/releases/download/\(latestRemoteTag)/\(fileName)"

            let downloadCommand = "curl -L -o /tmp/\(fileName) \(downloadURL)"
            let downloadResult = try Shell.run(downloadCommand)

            if downloadResult.isError {
                print("Failed to download update: \(downloadResult.stderr ?? "Unknown error")")
                return
            }

            print("Downloaded new binary to /tmp/\(fileName)")
        } catch {
            print("Update check failed: \(error)")
        }
    }
}
