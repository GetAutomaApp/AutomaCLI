import ConsoleKit
import Foundation
import Alamofire
import AnyCodable

internal struct GrafanaApplyCommand: AsyncCommand {
    var help: String { "Applies rendered Grafana JSON artifacts and updates state IDs." }

    struct Signature: CommandSignature {
        @Option(name: "environment", help: "Grafana environment. Defaults to automa.config.json current_environment.")
        var environment: String?
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let automaConfig = try ConfigHelper.getAutomaConfig()
        let environment = signature.environment ?? automaConfig.grafana.currentEnvironment

        let grafanaConfig = try GrafanaTemplateSupport.loadGrafanaCredentials(environment: environment)

        let manifestPath = GrafanaTemplateSupport.manifestPath(environment: environment)
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            context.console.error("No render manifest found. Run `automa grafana render --environment \(environment)` first.")
            return
        }

        let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
        let manifest = try JSONDecoder().decode(GrafanaRenderManifest.self, from: manifestData)

        guard !manifest.outputs.isEmpty else {
            context.console.print("No Grafana configuration files found to apply.")
            return
        }

        var state = try GrafanaTemplateSupport.readState(environment: environment)
        var failureCount = 0

        for artifact in manifest.outputs {
            do {
                try await processArtifact(
                    artifact: artifact,
                    environment: environment,
                    grafanaConfig: grafanaConfig,
                    state: &state,
                    context: context
                )
            } catch {
                failureCount += 1
                context.console.error("Error applying \(artifact.output): \(error.localizedDescription)")
            }
        }

        let statePath = GrafanaTemplateSupport.stateEnvironmentDir(environment: environment)
        try GrafanaTemplateSupport.writeState(state, environment: environment)
        if failureCount == 0 {
            context.console.success("Grafana apply completed successfully. State updated at \(statePath).")
        } else {
            context.console.error("Grafana apply finished with \(failureCount) failed artifact(s). State updated at \(statePath).")
        }
    }

    private func processArtifact(
        artifact: GrafanaRenderedArtifact,
        environment: String,
        grafanaConfig: GrafanaConfig,
        state: inout GrafanaStateFile,
        context: CommandContext
    ) async throws {
        let fileName = URL(fileURLWithPath: artifact.output).lastPathComponent
        let configFileContent = try String(contentsOfFile: artifact.output, encoding: .utf8)

        if artifact.kind == "dashboard" || fileName.contains("_dash.") {
            try await applyDashboard(
                artifact: artifact,
                content: configFileContent,
                grafanaConfig: grafanaConfig,
                state: &state,
                context: context
            )
        } else if artifact.kind == "alert" || fileName.contains("_alert.") {
            try await applyAlert(
                artifact: artifact,
                content: configFileContent,
                grafanaConfig: grafanaConfig,
                state: &state,
                context: context
            )
        } else {
            context.console.error("Skipping \(fileName): Invalid suffix.")
        }
    }

    private func applyDashboard(
        artifact: GrafanaRenderedArtifact,
        content: String,
        grafanaConfig: GrafanaConfig,
        state: inout GrafanaStateFile,
        context: CommandContext
    ) async throws {
        let fileName = URL(fileURLWithPath: artifact.output).lastPathComponent
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

        if let data = response.data,
           let parsed = try? JSONDecoder().decode(GrafanaDashboardUpsertResponse.self, from: data) {
            state.dashboards[artifact.key] = GrafanaDashboardState(uid: parsed.uid, id: parsed.id, title: parsed.title)
        }
    }

    private func applyAlert(
        artifact: GrafanaRenderedArtifact,
        content: String,
        grafanaConfig: GrafanaConfig,
        state: inout GrafanaStateFile,
        context: CommandContext
    ) async throws {
        let fileName = URL(fileURLWithPath: artifact.output).lastPathComponent
        guard var alertJSON = try? JSONDecoder().decode([String: AnyCodableValue].self, from: Data(content.utf8)) else {
            context.console.error("Could not parse alert JSON from \(fileName).")
            return
        }

        if alertJSON["folderUID"] == nil && alertJSON["folderUid"] == nil {
            let folderIdentifier = alertJSON["folder"]?.stringValue ?? "General"
            let resolvedFolderUid = try await resolveFolder(folderIdentifier: folderIdentifier, grafanaConfig: grafanaConfig, context: context)
            if let folderUid = resolvedFolderUid {
                alertJSON["folderUID"] = AnyCodableValue(folderUid)
            }
        }

        let existingUID = state.alertRules[artifact.key]?.uid
        let endpoint = "\(grafanaConfig.url)/api/v1/provisioning/alert-rules" + (existingUID != nil ? "/\(existingUID!)" : "")

        let method: HTTPMethod = existingUID != nil ? .put : .post
        let request = AF.request(
            endpoint,
            method: method,
            parameters: alertJSON,
            encoder: JSONParameterEncoder.default,
            headers: ["Authorization": "Bearer \(grafanaConfig.token)"]
        )

        let response = await request.serializingData().response
        try handleResponse(response, context: context, fileName: fileName)

        if let uid = alertJSON["uid"]?.stringValue {
            let title = alertJSON["title"]?.stringValue
            state.alertRules[artifact.key] = GrafanaAlertRuleState(uid: uid, title: title)
        }
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
        if let httpResponse = response.response, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: response.data ?? Data(), encoding: .utf8) ?? "<no body>"
            context.console.error("API call failed for \(fileName): \(body)")
            throw CommandError.unknownCommand("", available: [])
        }
        if let error = response.error, response.response == nil {
            throw error
        }
        context.console.success("Successfully applied Grafana config for \(fileName).")
    }
}

private struct GrafanaFolder: Codable {
    let id: Int
    let uid: String
    let title: String
}

private struct GrafanaDashboardUpsertResponse: Codable {
    let id: Int?
    let uid: String
    let title: String?
}
