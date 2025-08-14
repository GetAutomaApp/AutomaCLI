
// GrafanaApplyCommand.swift
// Copyright (c) 2025 GetAutomaApp
// All source code and related assets are the property of GetAutomaApp.
// All rights reserved.

import ConsoleKit
import Foundation

internal struct GrafanaApplyCommand: Command {
    init() {}

    var help: String {
        "Applies a Grafana dashboard or alert configuration."
    }

    struct Signature: CommandSignature {
        init() {}

        @Option(name: "config-file", help: "Path to the YAML or JSON configuration file (e.g., my_dash.json, my_alert.json).")
        var configFile: String?

        @Flag(name: "all", help: "Apply all Grafana configuration files in the project recursively.")
        var all: Bool
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let automaConfig = try ConfigHelper.getAutomaConfig()
        let environment = automaConfig.grafana.currentEnvironment

        guard let userConfig = try? loadConfig(),
              let grafanaConfigs = userConfig.grafana,
              let grafanaConfig = grafanaConfigs[environment] else {
            context.console.error("don't know env please!! run automa grafana setup")
            throw CommandError.unknownCommand("", available: [])
        }

        var filesToApply: [String] = []

        if signature.all {
            guard signature.configFile == nil else {
                context.console.error("Cannot use --all flag with --config-file option.")
                throw CommandError.unknownCommand("", available: [])
            }

            let projectRoot = FileManager.default.currentDirectoryPath
            let enumerator = FileManager.default.enumerator(atPath: projectRoot)

            while let element = enumerator?.nextObject() as? String {
                let fullPath = (projectRoot as NSString).appendingPathComponent(element)
                let fileName = (fullPath as NSString).lastPathComponent

                if fileName.contains("_dash.") || fileName.contains("_alert.") {
                    filesToApply.append(fullPath)
                }
            }
        } else if let configFile = signature.configFile {
            filesToApply.append(configFile)
        } else {
            context.console.error("Either --config-file option or --all flag must be provided.")
            throw CommandError.unknownCommand("", available: [])
        }

        guard !filesToApply.isEmpty else {
            context.console.print("No Grafana configuration files found to apply.")
            return
        }

        for filePath in filesToApply {
            context.console.print("Applying Grafana configuration for \(environment) environment from \(filePath)...")

            let endpoint: String
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent

            if fileName.contains("_dash.") {
                endpoint = "/api/dashboards/db"
            } else if fileName.contains("_alert.") {
                endpoint = "/api/v1/provisioning/alert-rules"
            } else {
                context.console.error("Skipping \(fileName): Invalid file name. Please use one of the following suffixes: _dash.ext, _alert.ext")
                continue
            }

            let configFileContent: String
            do {
                configFileContent = try String(contentsOfFile: filePath)
            } catch {
                context.console.error("Error reading config file \(fileName): \(error.localizedDescription)")
                continue
            }

            let url = URL(string: "\(grafanaConfig.url)\(endpoint)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(grafanaConfig.token)", forHTTPHeaderField: "Authorization")
            request.httpBody = configFileContent.data(using: .utf8)

            let semaphore = DispatchSemaphore(value: 0)
            var success = false

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    context.console.error("API call error for \(fileName): \(error.localizedDescription)")
                    semaphore.signal()
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    success = true
                } else {
                    if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                        context.console.error("API call failed for \(fileName) with response: \(responseBody)")
                    } else {
                        context.console.error("API call failed for \(fileName) with status code \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    }
                }
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()

            if success {
                context.console.success("Grafana configuration applied successfully for \(fileName).")
            } else {
                context.console.error("Failed to apply Grafana configuration for \(fileName).")
            }
        }
    }
}
