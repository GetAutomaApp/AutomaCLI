

// GrafanaApplyCommand.swift Copyright (c) 2025 GetAutomaApp
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

            let fileName = URL(fileURLWithPath: filePath).lastPathComponent

            var configFileContent: String
            do {
                configFileContent = try String(contentsOfFile: filePath, encoding: .utf8)
            } catch {
                context.console.error("Error reading config file \(fileName): \(error.localizedDescription)")
                continue
            }

            if fileName.contains("_dash.") {
                guard var dashboardJSON = try? JSONSerialization.jsonObject(with: configFileContent.data(using: .utf8)!, options: .mutableContainers) as? [String: Any] else {
                    context.console.error("Could not parse dashboard JSON from \(fileName).")
                    continue
                }

                var folderUidForPayload: String?
                if let folderIdentifier = dashboardJSON["folder"] as? String {
                    if let resolvedFolderUid = try resolveFolder(folderIdentifier: folderIdentifier, context: context, grafanaConfig: grafanaConfig) {
                        dashboardJSON["folder"] = nil
                        dashboardJSON["folderUid"] = resolvedFolderUid
                        folderUidForPayload = resolvedFolderUid
                        
                        let updatedData = try JSONSerialization.data(withJSONObject: dashboardJSON, options: .prettyPrinted)
                        try updatedData.write(to: URL(fileURLWithPath: filePath))
                        configFileContent = String(data: updatedData, encoding: .utf8)!
                    }
                } else if let existingFolderUid = dashboardJSON["folderUid"] as? String {
                    folderUidForPayload = existingFolderUid
                }

                let hasUid = dashboardJSON["uid"] as? String != nil

                var payload: [String: Any?] = [
                    "dashboard": dashboardJSON,
                    "overwrite": true,
                    "message": "Updated by AutomaCLI",
                ]
                if folderUidForPayload != nil {
                    payload["folderUid"] = folderUidForPayload
                }

                let endpoint = "/api/dashboards/db"
                let url = URL(string: "\(grafanaConfig.url)\(endpoint)")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(grafanaConfig.token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
                
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
                        if !hasUid, let data = data {
                            do {
                                if let responseJSON = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                                   let newUid = responseJSON["uid"] as? String {
                                    
                                    dashboardJSON["uid"] = newUid
                                    if let newId = responseJSON["id"] as? Int {
                                       dashboardJSON["id"] = newId
                                    }
                                    if let newVersion = responseJSON["version"] as? Int {
                                       dashboardJSON["version"] = newVersion
                                    }

                                    let updatedData = try JSONSerialization.data(withJSONObject: dashboardJSON, options: .prettyPrinted)
                                    try updatedData.write(to: URL(fileURLWithPath: filePath))
                                    context.console.info("Updated \(fileName) with new dashboard uid: \(newUid)")
                                }
                            } catch {
                                context.console.error("Failed to update \(fileName) with new uid: \(error.localizedDescription)")
                            }
                        }
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
                    if !hasUid {
                        context.console.success("Successfully created new Grafana dashboard from \(fileName).")
                    } else {
                        context.console.success("Successfully updated Grafana dashboard from \(fileName).")
                    }
                } else {
                    context.console.error("Failed to apply Grafana configuration for \(fileName).")
                }

            } else if fileName.contains("_alert.") {
                guard var alertJSON = try? JSONSerialization.jsonObject(with: configFileContent.data(using: .utf8)!, options: .mutableContainers) as? [String: Any] else {
                    context.console.error("Could not parse alert JSON from \(fileName).")
                    continue
                }

                // Extract folderUID and ruleGroup
                guard let folderIdentifier = alertJSON["folder"] as? String else {
                    context.console.error("Error: Alert JSON from \(fileName) is missing 'folder' field.")
                    continue
                }
                
                guard let ruleGroup = alertJSON["ruleGroup"] as? String else {
                    context.console.error("Error: Alert JSON from \(fileName) is missing 'ruleGroup' field.")
                    continue
                }

                // Resolve folder UID (and create if it doesn't exist)
                guard let resolvedFolderUid = try resolveFolder(folderIdentifier: folderIdentifier, context: context, grafanaConfig: grafanaConfig) else {
                    context.console.error("Error: Could not resolve folder '\(folderIdentifier)' for alert in \(fileName).")
                    continue
                }
                alertJSON["folderUID"] = resolvedFolderUid
                alertJSON["folder"] = nil // Remove the "folder" field as it's replaced by "folderUID"

                let endpoint = "/api/v1/provisioning/alert-rules"
                let uid = alertJSON["uid"] as? String
                
                var request: URLRequest
                if let uid = uid {
                    let url = URL(string: "\(grafanaConfig.url)\(endpoint)/\(uid)")!
                    request = URLRequest(url: url)
                    request.httpMethod = "PUT"
                } else {
                    let url = URL(string: "\(grafanaConfig.url)\(endpoint)")!
                    request = URLRequest(url: url)
                    request.httpMethod = "POST"
                }

                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(grafanaConfig.token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try? JSONSerialization.data(withJSONObject: alertJSON, options: [])

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
                        if uid == nil, let data = data { // It was a new alert
                            do {
                                if let responseJSON = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                                   let newUid = responseJSON["uid"] as? String {
                                    
                                    alertJSON["uid"] = newUid
                                    let updatedData = try JSONSerialization.data(withJSONObject: alertJSON, options: .prettyPrinted)
                                    try updatedData.write(to: URL(fileURLWithPath: filePath))
                                    context.console.info("Updated \(fileName) with new alert uid: \(newUid)")
                                }
                            } catch {
                                context.console.error("Failed to update \(fileName) with new uid: \(error.localizedDescription)")
                            }
                        }
                    }
                    else {
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
                    if uid == nil {
                        context.console.success("Successfully created new Grafana alert from \(fileName).")
                    } else {
                        context.console.success("Successfully updated Grafana alert from \(fileName).")
                    }
                } else {
                    context.console.error("Failed to apply Grafana configuration for \(fileName).")
                }
            } else {
                context.console.error("Skipping \(fileName): Invalid file name. Please use one of the following suffixes: _dash.ext, _alert.ext")
                continue
            }
        }
    }

    private struct GrafanaFolder: Codable {
        let id: Int
        let uid: String
        let title: String
    }

    private func resolveFolder(folderIdentifier: String, context: CommandContext, grafanaConfig: GrafanaConfig) throws -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var folderUid: String?
        var folderError: Error?

        let allFoldersUrl = URL(string: "\(grafanaConfig.url)/api/folders")!
        var allFoldersRequest = URLRequest(url: allFoldersUrl)
        allFoldersRequest.setValue("Bearer \(grafanaConfig.token)", forHTTPHeaderField: "Authorization")

        let allFoldersTask = URLSession.shared.dataTask(with: allFoldersRequest) { data, response, error in
            if let error = error {
                folderError = error
                semaphore.signal()
                return
            }

            if let data = data, let folders = try? JSONDecoder().decode([GrafanaFolder].self, from: data) {
                let identifier = folderIdentifier.starts(with: "folder://") ? String(folderIdentifier.dropFirst("folder://".count)) : folderIdentifier
                
                if identifier == "general" {
                    folderUid = "general"
                    semaphore.signal()
                    return
                }

                for folder in folders {
                    if folder.uid == identifier || folder.title == identifier {
                        folderUid = folder.uid
                        semaphore.signal()
                        return
                    }
                }
            }

            // If we are here, folder is not found. Let's create it.
            let identifier = folderIdentifier.starts(with: "folder://") ? String(folderIdentifier.dropFirst("folder://".count)) : folderIdentifier
            let createFolderUrl = URL(string: "\(grafanaConfig.url)/api/folders")!
            var createFolderRequest = URLRequest(url: createFolderUrl)
            createFolderRequest.httpMethod = "POST"
            createFolderRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            createFolderRequest.setValue("Bearer \(grafanaConfig.token)", forHTTPHeaderField: "Authorization")
            let body = ["title": identifier]
            createFolderRequest.httpBody = try? JSONEncoder().encode(body)

            let createTask = URLSession.shared.dataTask(with: createFolderRequest) { data, response, error in
                if let error = error {
                    folderError = error
                    semaphore.signal()
                    return
                }

                if let data = data, let newFolder = try? JSONDecoder().decode(GrafanaFolder.self, from: data) {
                    folderUid = newFolder.uid
                } else {
                    if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                        context.console.error("Failed to create folder. Response: \(responseBody)")
                    }
                    folderError = CommandError.unknownCommand("", available: []) // A bit of a hack for error
                }
                semaphore.signal()
            }
            createTask.resume()
        }
        allFoldersTask.resume()
        semaphore.wait()

        if let folderError = folderError {
            throw folderError
        }

        return folderUid
    }
}

