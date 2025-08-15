import ConsoleKit
import Foundation
import Alamofire
import AnyCodable

internal struct GrafanaApplyCommand: AsyncCommand {
    var help: String { "Applies a Grafana dashboard or alert configuration." }

    struct Signature: CommandSignature {
        @Option(name: "config-file", help: "Path to the YAML or JSON configuration file.")
        var configFile: String?

        @Flag(name: "all", help: "Apply all Grafana configuration files recursively.")
        var all: Bool
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let automaConfig = try ConfigHelper.getAutomaConfig()
        let environment = automaConfig.grafana.currentEnvironment

        guard let userConfig = try? loadConfig(),
              let grafanaConfigs = userConfig.grafana,
              let grafanaConfig = grafanaConfigs[environment] else {
            context.console.error("don't know env please!! run automa grafana setup")
            throw CommandError.unknownCommand("", available: [])
        }

        let filesToApply = try collectFiles(signature: signature)

        guard !filesToApply.isEmpty else {
            context.console.print("No Grafana configuration files found to apply.")
            return
        }

        for filePath in filesToApply {
            do {
                try await processFile(
                    filePath,
                    environment: environment,
                    grafanaConfig: grafanaConfig,
                    context: context
                )
            } catch {
                context.console.error("Error applying \(filePath): \(error.localizedDescription)")
            }
        }
    }

    private func collectFiles(signature: Signature) throws -> [String] {
        if signature.all {
            guard signature.configFile == nil else {
                throw CommandError.unknownCommand("", available: [])
            }

            let projectRoot = FileManager.default.currentDirectoryPath
            var matches: [String] = []
            if let enumerator = FileManager.default.enumerator(atPath: projectRoot) {
                for case let element as String in enumerator {
                    let fullPath = (projectRoot as NSString).appendingPathComponent(element)
                    let fileName = (fullPath as NSString).lastPathComponent
                    if fileName.contains("_dash.") || fileName.contains("_alert.") {
                        matches.append(fullPath)
                    }
                }
            }
            return matches
        } else if let configFile = signature.configFile {
            return [configFile]
        } else {
            throw CommandError.unknownCommand("", available: [])
        }
    }

    private func processFile(
        _ filePath: String,
        environment: String,
        grafanaConfig: GrafanaConfig,
        context: CommandContext
    ) async throws {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        let configFileContent = try String(contentsOfFile: filePath, encoding: .utf8)

        if fileName.contains("_dash.") {
            try await applyDashboard(
                fileName: fileName,
                filePath: filePath,
                content: configFileContent,
                grafanaConfig: grafanaConfig,
                context: context
            )
        } else if fileName.contains("_alert.") {
            try await applyAlert(
                fileName: fileName,
                filePath: filePath,
                content: configFileContent,
                grafanaConfig: grafanaConfig,
                context: context
            )
        } else {
            context.console.error("Skipping \(fileName): Invalid suffix.")
        }
    }

    private func applyDashboard(
        fileName: String,
        filePath: String,
        content: String,
        grafanaConfig: GrafanaConfig,
        context: CommandContext
    ) async throws {
        guard var payload = try? JSONDecoder().decode([String: AnyCodableValue].self, from: Data(content.utf8)) else {
            context.console.error("Could not parse dashboard JSON from \(fileName).")
            return
        }

        if let folderIdentifier = payload["folder"]?.stringValue,
           let resolvedFolderUid = try await resolveFolder(folderIdentifier: folderIdentifier, grafanaConfig: grafanaConfig, context: context) {
            payload["folderUid"] = AnyCodableValue(resolvedFolderUid)
        }

        let endpoint = "\(grafanaConfig.url)/api/dashboards/db"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(grafanaConfig.token)",
            "Content-Type": "application/json"
        ]
        let request = AF.request(
            endpoint,
            method: .post,
            parameters: payload,
            encoder: JSONParameterEncoder.default,
            headers: headers
        )

        let response = await request.serializingData().response
        try handleResponse(response, context: context, fileName: fileName)
    }

    private func applyAlert(
        fileName: String,
        filePath: String,
        content: String,
        grafanaConfig: GrafanaConfig,
        context: CommandContext
    ) async throws {
        guard var alertJSON = try? JSONDecoder().decode([String: AnyCodableValue].self, from: Data(content.utf8)) else {
            context.console.error("Could not parse alert JSON from \(fileName).")
            return
        }

        if let folderIdentifier = alertJSON["folder"]?.stringValue {
             let resolvedFolderUid = try await resolveFolder(folderIdentifier: folderIdentifier, grafanaConfig: grafanaConfig, context: context)
            if let folderUid = resolvedFolderUid {
                alertJSON["folderUID"] = AnyCodableValue(folderUid)
            }
        }

        let uid = alertJSON["uid"]?.stringValue
        let endpoint = "\(grafanaConfig.url)/api/v1/provisioning/alert-rules" + (uid != nil ? "/\(uid!)" : "")

        let method: HTTPMethod = uid != nil ? .put : .post
        let request = AF.request(
            endpoint,
            method: method,
            parameters: alertJSON,
            encoder: JSONParameterEncoder.default,
            headers: ["Authorization": "Bearer \(grafanaConfig.token)"]
        )

        let response = await request.serializingData().response
        try handleResponse(response, context: context, fileName: fileName)
    }

    private func resolveFolder(folderIdentifier: String, grafanaConfig: GrafanaConfig, context: CommandContext) async throws -> String? {
        let endpoint = "\(grafanaConfig.url)/api/folders"
        let headers: HTTPHeaders = ["Authorization": "Bearer \(grafanaConfig.token)"]

        let dataResponse = await AF.request(endpoint, headers: headers).serializingDecodable([GrafanaFolder].self).response
        switch dataResponse.result {
        case .success(let folders):
            let identifier = folderIdentifier.hasPrefix("folder://")
                ? String(folderIdentifier.dropFirst("folder://".count))
                : folderIdentifier
            if let match = folders.first(where: { $0.uid == identifier || $0.title == identifier }) {
                return match.uid
            }
        case .failure(let err):
            throw err
        }

        // Create folder if not found
        let createResponse = await AF.request(
            endpoint,
            method: .post,
            parameters: ["title": folderIdentifier],
            encoding: JSONEncoding.default,
            headers: headers
        ).serializingDecodable(GrafanaFolder.self).response

        switch createResponse.result {
        case .success(let folder):
            return folder.uid
        case .failure(let err):
            throw err
        }
    }

    private func handleResponse(_ response: AFDataResponse<Data>, context: CommandContext, fileName: String) throws {
        print(String(data: response.data ?? Data(), encoding: .utf8) ?? "<no body>")
        if let error = response.error {
            throw error
        }
        if let httpResponse = response.response, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: response.data ?? Data(), encoding: .utf8) ?? "<no body>"
            context.console.error("API call failed for \(fileName): \(body)")
            throw CommandError.unknownCommand("", available: [])
        }
        context.console.success("Successfully applied Grafana config for \(fileName).")
    }
}

private struct GrafanaFolder: Codable {
    let id: Int
    let uid: String
    let title: String
}
