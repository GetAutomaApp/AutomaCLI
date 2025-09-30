// GenerateCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

internal struct GenerateGroup: CommandGroup {
    let commands: [String: AnyCommand] = {
        var cmds: [String: AnyCommand] = [
            "fly": GenerateFly(),
        ]

        #if !NO_BUILTIN_TEMPLATE_GENERATE
            cmds["generate"] = GenerateCommand()
        #endif

        return cmds
    }()

    let help = "Generates code templates."

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

internal struct GenerateCommand: Command {
    init() {}

    var help: String {
        "Generates an app component based on the given name."
    }

    struct Signature: CommandSignature {
        init() {}
        @Argument(
            name: "name",
            help: "The component to generate."
        )
        var component: String

        @Argument(name: "filename", help: "The name of the component to generate.")
        var filename: String

        @Option(
            name: "nestedDir",
            help: "The directory you want to nest the component into (added to the default path)."
        )
        var nestedDir: String?

        @Flag(name: "copy", help: "Copy files to the destination directory.")
        var copy: Bool
    }

    /// Executes the command with the given context and signature.
    /// - Parameters:
    ///   - context: The context in which the command is executed.
    ///   - signature: The command's signature containing arguments.
    /// - Throws: Any errors that occur during command execution.
    func run(using context: CommandContext, signature: Signature) throws {
        let config = try loadConfig()
        let basePath = "\(config.repoPath)/generators/"
        let fileTypes = FileTypeHelper.getFileTypes()

        let componentName = signature.filename
        let copy = signature.copy
        var output = ""

        context.console.print("🚀 Current Working Directory: \(FileManager.default.currentDirectoryPath)")

        for fileType in fileTypes {
            guard fileType.name == signature.component else { continue }

            for fileConfig in fileType.configurations {
                let fromDirectory = URL(fileURLWithPath: "\(basePath)\(fileConfig.fromDirectory)").standardized.path
                let toDirectory = URL(
                    fileURLWithPath: fileConfig.toDirectory,
                    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                ).standardized.path
                let nestedDir = signature.nestedDir ?? ""

                let toNestedDir = URL(fileURLWithPath: "\(toDirectory)/\(arrayToPascalCase([nestedDir]))/")
                    .standardized.path

                let nestToDirectory = rename(text: fileConfig.nestToDirectory, componentName: componentName)
                let destinationPath = URL(fileURLWithPath: "\(toNestedDir)/\(nestToDirectory)").standardized.path

                context.console.print("🛠️  Resolving Paths:")
                context.console.print("- From Directory: \(fromDirectory)")
                context.console.print("- To Directory: \(toDirectory)")
                context.console.print("- To Nested Directory: \(toNestedDir)")
                context.console.print("- Final Destination Path: \(destinationPath)")

                if FileManager.default.fileExists(atPath: nestToDirectory) {
                    context.console.error("Component directory '\(nestToDirectory)' already exists.")
                    throw URLError(.badURL)
                }

                try FileManager.default.createDirectory(
                    atPath: destinationPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                for template in fileConfig.templates {
                    let sourceFile = URL(fileURLWithPath: "\(fromDirectory)/\(template)").standardized.path
                    let fileNameFormatted = rename(text: template, componentName: componentName)
                        .replacingOccurrences(of: ".template", with: "")

                    let destinationFile = URL(fileURLWithPath: "\(destinationPath)/\(fileNameFormatted)")
                        .standardized.path

                    if FileManager.default.fileExists(atPath: destinationFile), !copy {
                        context.console.error("Component implementation '\(destinationFile)' already exists.")
                        throw URLError(.badURL)
                    }

                    output += try moveAndRenameFile(
                        source: sourceFile,
                        destination: destinationFile,
                        componentName: componentName,
                        shouldWrite: !copy,
                        console: context.console
                    )
                }

                context.console
                    .print("✅ Successfully created a \(fileType.name) called '\(componentName)' in '\(toNestedDir)'.")
            }
        }

        let shell = try Shell()
        if copy {
            try Shell.run("echo '\(output)' | \(shell.copyCommand)")
        }
    }

    private func moveAndRenameFile(
        source: String,
        destination: String,
        componentName: String,
        shouldWrite: Bool = true,
        console: Console
    ) throws -> String {
        let absoluteSourcePath = URL(fileURLWithPath: source).standardized.path
        console.print("Absolute Source Path: \(absoluteSourcePath)")

        let absoluteDestinationPath = URL(fileURLWithPath: destination).standardized.path
        console.print("Absolute Destination Path: \(absoluteDestinationPath)")

        let destinationDirectory = (absoluteDestinationPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: destinationDirectory) {
            try FileManager.default.createDirectory(
                atPath: destinationDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        guard FileManager.default.fileExists(atPath: absoluteSourcePath) else {
            console.error("Template file not found: \(absoluteSourcePath)")
            throw URLError(.badURL)
        }

        var content = try String(contentsOfFile: absoluteSourcePath, encoding: .utf8)
        content = rename(text: content, componentName: componentName)

        if shouldWrite {
            console.print("Writing \(absoluteDestinationPath)")
            try content.write(toFile: absoluteDestinationPath, atomically: true, encoding: .utf8)
        }

        return "\(destination)\n\(content)"
    }

    private func rename(text: String, componentName: String) -> String {
        let words = pascalToWordsArray(componentName)
        return text
            .replacingOccurrences(of: "__CAPNAME__", with: componentName)
            .replacingOccurrences(of: "__CAPNAME_LOWER__", with: componentName.lowercased())
            .replacingOccurrences(of: "__CAPNAME_DASHED__", with: arrayToDashed(words))
            .replacingOccurrences(of: "__CAPNAME_DASHEDUPPER__", with: arrayToDashed(words, capitalized: true))
            .replacingOccurrences(of: "__CAPNAME_HASKELL__", with: arrayToHaskell(words))
            .replacingOccurrences(of: "__CAPNAME_SPACING__", with: arrayToSpaceDelimited(words))
            .replacingOccurrences(of: "__TIMESTAMP__", with: "\(Int(Date().timeIntervalSince1970))")
    }

    private func pascalToWordsArray(_ pascal: String) -> [String] {
        let pattern = "([A-Z])"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: pascal.utf16.count)
            let modifiedString = regex.stringByReplacingMatches(
                in: pascal,
                options: [],
                range: range,
                withTemplate: " $1"
            )
            return modifiedString.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        } catch {
            return []
        }
    }

    private func arrayToDashed(_ array: [String], capitalized: Bool = false) -> String {
        let dashedString = array.joined(separator: "-")
        if capitalized, let firstCharacter = dashedString.first {
            return "\(firstCharacter.uppercased())\(dashedString.dropFirst())"
        }
        return dashedString
    }

    private func arrayToHaskell(_ array: [String]) -> String {
        guard !array.isEmpty else { return "" }
        return array
            .enumerated()
            .map { index, element in
                if index == 0 {
                    element.lowercased()
                } else {
                    element.lowercased().capitalized
                }
            }
            .joined(separator: "")
    }

    private func arrayToSpaceDelimited(_ array: [String]) -> String {
        array.joined(separator: " ")
    }

    private func arrayToPascalCase(_ array: [String]) -> String {
        array.map(\.capitalized).joined()
    }

    struct FileType: Sendable {
        let name: String
        let configurations: [FileConfig]
    }

    struct FileConfig: Sendable {
        let fromDirectory: String
        let toDirectory: String
        let nestToDirectory: String
        let templates: [String]
    }

    private enum FileTypeHelper {
        // swiftlint:disable:next function_body_length
        public static func getFileTypes() -> [FileType] {
            [
                FileType(name: "ui-component", configurations: [
                    FileConfig(
                        fromDirectory: "ui-component/",
                        toDirectory: "App/AutomaUIKit/Sources/AutomaUIKit/Components/",
                        nestToDirectory: "__CAPNAME__Component/",
                        templates: [
                            "__CAPNAME__Component.swift.template",
                            "__CAPNAME__ComponentPreviews.swift.template",
                            "__CAPNAME__ComponentConfig.swift.template",
                        ]
                    ),
                ]),
                FileType(name: "ui-modifier", configurations: [
                    FileConfig(
                        fromDirectory: "ui-modifier/",
                        toDirectory: "App/AutomaUIKit/Sources/AutomaUIKit/Core/Modifiers/",
                        nestToDirectory: "__CAPNAME__Modifier/",
                        templates: [
                            "__CAPNAME__Modifier.swift.template",
                            "__CAPNAME__ModifierPreviews.swift.template",
                        ]
                    ),
                ]),
                FileType(
                    name: "backend-controller",
                    configurations: [
                        FileConfig(
                            fromDirectory: "backend-controller/",
                            toDirectory: "Backend/Sources/App/Controllers/",
                            nestToDirectory: "__CAPNAME__Controller/",
                            templates: [
                                "__CAPNAME__Controller.swift.template",
                            ]
                        ),
                        FileConfig(
                            fromDirectory: "controller-interactor/",
                            toDirectory: "App/AutomaAppShared/Sources/AutomaAppShared/Interactors/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME__ControllerInteractor.swift.template",
                            ]
                        ),
                    ]
                ),
                FileType(
                    name: "model",
                    configurations: [
                        FileConfig(
                            fromDirectory: "model/",
                            toDirectory: "Backend/Sources/App/Models/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME__Model.swift.template",
                            ]
                        ),
                        FileConfig(
                            fromDirectory: "model/",
                            toDirectory: "Backend/DataTypes/Sources/DataTypes/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME__DTO.swift.template",
                            ]
                        ),
                        FileConfig(
                            fromDirectory: "migration/",
                            toDirectory: "Backend/Sources/App/Migrations/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME__Migration.swift.template",
                            ]
                        ),
                    ]
                ),
                FileType(
                    name: "dto",
                    configurations: [
                        FileConfig(
                            fromDirectory: "dto/",
                            toDirectory: "Backend/DataTypes/Sources/DataTypes/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME__DTO.swift.template",
                            ]
                        ),
                    ]
                ),
                FileType(
                    name: "migration",
                    configurations: [
                        FileConfig(
                            fromDirectory: "migration/",
                            toDirectory: "Backend/Sources/App/Migrations/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME__Migration.swift.template",
                            ]
                        ),
                    ]
                ),
                FileType(
                    name: "backend-service",
                    configurations: [
                        FileConfig(
                            fromDirectory: "backend-service/",
                            toDirectory: "Backend/Sources/App/Services/",
                            nestToDirectory: "__CAPNAME__Service/",
                            templates: [
                                "__CAPNAME__Service.swift.template",
                            ]
                        ),
                    ]
                ),
                FileType(
                    name: "backend-interactor",
                    configurations: [
                        FileConfig(
                            fromDirectory: "controller-interactor/",
                            toDirectory: "App/AutomaAppShared/Sources/AutomaAppShared/Interactors/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME__ControllerInteractor.swift.template",
                            ]
                        ),
                    ]
                ),
                FileType(
                    name: "async-job",
                    configurations: [
                        FileConfig(
                            fromDirectory: "backend-async-job/",
                            toDirectory: "Backend/Sources/App/Procs/Jobs/",
                            nestToDirectory: "__CAPNAME__AsyncJob/",
                            templates: [
                                "__CAPNAME__AsyncJob.swift.template",
                            ]
                        ),
                    ]
                ),
                FileType(
                    name: "command",
                    configurations: [
                        FileConfig(
                            fromDirectory: "command/",
                            toDirectory: "Backend/Sources/App/Commands/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME_LOWER__.swift.template",
                            ]
                        ),
                    ]
                ),
                FileType(
                    name: "screen",
                    configurations: [
                        FileConfig(
                            fromDirectory: "screen/",
                            toDirectory: "App/AutomaAppShared/Sources/AutomaAppShared/Screens/",
                            nestToDirectory: "",
                            templates: [
                                "__CAPNAME__Screen.swift.template",
                            ]
                        ),
                    ]
                ),
            ]
        }
    }
}

internal struct GenerateFly: Command {
    struct Signature: CommandSignature {
        @Argument(name: "template", help: "The name of the template file (without .toml extension).")
        var template: String

        @Argument(name: "environment", help: "The environment to use for placeholder replacement.")
        var environment: String
    }

    let help = "Generates a fly.toml config file from a template."

    func run(using context: CommandContext, signature: Signature) throws {
        let template = signature.template
        let environment = signature.environment
        let config = try ConfigHelper.getAutomaConfig()

        let configPath = "\(config.fly.configFilesRoot)/\(template).toml"
        print(configPath)

        guard FileManager.default.fileExists(atPath: configPath) else {
            context.console.print("😭 can't find config directory")
            throw URLError(.badURL)
        }

        var content = try String(contentsOfFile: configPath, encoding: .utf8)

        content = content
            .replacingOccurrences(
                of: "__FLY_ENVIRONMENT__",
                with: environment
            )

        let newFileUUID = UUID().uuidString
        let newFilePath = "/tmp/\(newFileUUID)-fly.toml"

        try content.write(to: URL(fileURLWithPath: newFilePath), atomically: true, encoding: .utf8)

        print("\(newFilePath)")
    }
}
