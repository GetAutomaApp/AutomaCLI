import Alamofire
import ConsoleKit
import Foundation

internal struct GrafanaSyncIDsCommand: AsyncCommand {
    var help: String { "Refreshes local dashboard IDs/UIDs from Grafana." }

    struct Signature: CommandSignature {
        @Option(name: "environment", help: "Grafana environment. Defaults to automa.config.json current_environment.")
        var environment: String?
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let automaConfig = try ConfigHelper.getAutomaConfig()
        let environment = signature.environment ?? automaConfig.grafana.currentEnvironment

        let grafanaConfig = try GrafanaTemplateSupport.loadGrafanaCredentials(environment: environment)

        let headers: HTTPHeaders = ["Authorization": "Bearer \(grafanaConfig.token)"]
        let endpoint = "\(grafanaConfig.url)/api/search?type=dash-db&limit=5000"
        let response = await AF.request(endpoint, headers: headers).serializingDecodable([GrafanaSearchDashboard].self).response

        let dashboards: [GrafanaSearchDashboard]
        switch response.result {
        case .success(let payload):
            dashboards = payload
        case .failure(let error):
            throw error
        }

        var state = try GrafanaTemplateSupport.readState(environment: environment)
        for dashboard in dashboards {
            if let existingKey = state.dashboards.first(where: { $0.value.uid == dashboard.uid })?.key {
                state.dashboards[existingKey] = GrafanaDashboardState(uid: dashboard.uid, id: dashboard.id, title: dashboard.title)
            } else {
                let key = slugify(dashboard.title)
                state.dashboards[key] = GrafanaDashboardState(uid: dashboard.uid, id: dashboard.id, title: dashboard.title)
            }
        }

        let statePath = GrafanaTemplateSupport.stateEnvironmentDir(environment: environment)
        try GrafanaTemplateSupport.writeState(state, environment: environment)
        context.console.success("Synced \(dashboards.count) dashboard IDs/UIDs into \(statePath).")
        context.console.print("Alert rule sync is intentionally skipped; apply writes alert UIDs by template key.")
    }

    private func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let pattern = "[^a-z0-9]+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(location: 0, length: lowered.utf16.count)
        let stripped = regex?.stringByReplacingMatches(in: lowered, range: fullRange, withTemplate: "-") ?? lowered
        return stripped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private struct GrafanaSearchDashboard: Codable {
    let id: Int?
    let uid: String
    let title: String
}
